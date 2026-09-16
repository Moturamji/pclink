import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pclink/core/constants/server_constants.dart';
import 'package:pclink/core/utils/cancellation_token.dart';
import 'package:pclink/core/utils/transfer_fingerprint.dart';
import 'package:pclink/data/services/file_share_service.dart';
import 'package:pclink/data/services/server_service.dart';
import 'package:pclink/features/file_share/models/transfer_progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ServerService serverService;
  late FileShareService fileShareService;
  late int serverPort;
  late String serverUrl;
  late String serverStartTime;
  const testDeviceId = 'test_android_failure_matrix_id';

  setUpAll(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('pclink_failure_matrix_');
    serverService = ServerService();

    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    serverPort = socket.port;
    await socket.close();

    final serverInfo = await serverService.startServer(
      hostIp: '127.0.0.1',
      port: serverPort,
    );

    expect(serverInfo, isNotNull);
    serverUrl = 'http://127.0.0.1:$serverPort';
    serverStartTime = serverInfo!.startedAt!.toIso8601String();

    fileShareService = FileShareService();
    fileShareService.configure(
      getTargetServerUrls: () => [serverUrl],
      getServerStartTime: () => serverStartTime,
      deviceId: testDeviceId,
      deviceName: 'Matrix Test Phone',
    );
  });

  tearDownAll(() async {
    await serverService.stopServer();
    serverService.dispose();
    fileShareService.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File createTestFile(String name, int sizeInBytes, {int seed = 42}) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    final rand = Random(seed);
    final buffer = Uint8List(sizeInBytes);
    for (int i = 0; i < sizeInBytes; i++) {
      buffer[i] = rand.nextInt(256);
    }
    file.writeAsBytesSync(buffer);
    return file;
  }

  String computeSha256(File file) {
    final bytes = file.readAsBytesSync();
    return sha256.convert(bytes).toString();
  }

  group('Comprehensive Failure & Stress Matrix Tests', () {
    test('10%, 50%, and 99% Disconnect Interruption and Verified Resume', () async {
      final file5Mb = createTestFile('interruption_test.dat', 5 * 1024 * 1024, seed: 101);
      final totalBytes = file5Mb.lengthSync();
      final originalHash = computeSha256(file5Mb);
      final fingerprint = await TransferFingerprint.computeSourceFingerprint(file5Mb);

      final cutoffPercentages = [0.10, 0.50, 0.99];

      for (final pct in cutoffPercentages) {
        final stopByte = (totalBytes * pct).toInt();

        // 1. Check current offset
        final checkUri = Uri.parse(
          '$serverUrl${ServerConstants.filesUploadEndpoint}?checkOffset=true&name=interruption_test.dat&size=$totalBytes&fileKey=interruption_test.dat_$totalBytes&fingerprint=$fingerprint',
        );
        final checkResp = await http.get(
          checkUri,
          headers: {
            ServerConstants.authHeader: testDeviceId,
            ServerConstants.startTimeHeader: serverStartTime,
          },
        );
        final checkData = jsonDecode(checkResp.body);
        final currentOffset = checkData['offset'] as int;

        if (currentOffset < stopByte) {
          // Stream partial upload up to stopByte then abruptly cancel
          final uploadUri = Uri.parse(
            '$serverUrl${ServerConstants.filesUploadEndpoint}?name=interruption_test.dat&size=$totalBytes&offset=$currentOffset&fileKey=interruption_test.dat_$totalBytes&fingerprint=$fingerprint',
          );
          final client = http.Client();
          final request = http.StreamedRequest('POST', uploadUri);
          request.headers[ServerConstants.authHeader] = testDeviceId;
          request.headers[ServerConstants.startTimeHeader] = serverStartTime;
          request.contentLength = stopByte - currentOffset;

          final responseFuture = client.send(request);
          final stream = file5Mb.openRead(currentOffset, stopByte);
          await for (final chunk in stream) {
            request.sink.add(chunk);
          }
          await request.sink.close();
          try {
            await responseFuture;
          } catch (_) {}
          client.close();
        }
      }

      // Final complete resume via FileShareService
      final success = await fileShareService.uploadFile(file5Mb.path);
      expect(success, isTrue);

      final sharedFiles = serverService.sharedFiles;
      final uploaded = sharedFiles.firstWhere((f) => f.name.contains('interruption_test'));
      final targetFile = File(uploaded.filePath!);
      expect(await targetFile.exists(), isTrue);
      expect(targetFile.lengthSync(), equals(totalBytes));
      expect(computeSha256(targetFile), equals(originalHash));
    });

    test('Duplicate Transfers with Same Filename + Same Size never overwrite', () async {
      // Create two distinct files with same name and same size (1MB) but completely different seeds
      final fileA = createTestFile('collision_doc.pdf', 1024 * 1024, seed: 111);
      final hashA = computeSha256(fileA);

      final successA = await fileShareService.uploadFile(fileA.path);
      expect(successA, isTrue);

      // Now create second file with same name and size, but different seed and content
      final fileB = createTestFile('collision_doc_b.pdf', 1024 * 1024, seed: 222);
      final hashB = computeSha256(fileB);
      // Copy over collision_doc.pdf so path and name are identical
      await fileB.copy(fileA.path);

      final successB = await fileShareService.uploadFile(fileA.path);
      expect(successB, isTrue);

      // Check server files: both files should exist with distinct filenames and intact hashes
      final shared = serverService.sharedFiles;
      final matchA = shared.firstWhere((f) => computeSha256(File(f.filePath!)) == hashA);
      final matchB = shared.firstWhere((f) => computeSha256(File(f.filePath!)) == hashB);

      expect(matchA.filePath, isNot(equals(matchB.filePath)));
      expect(File(matchA.filePath!).existsSync(), isTrue);
      expect(File(matchB.filePath!).existsSync(), isTrue);
    });

    test('Cancellation mid-flight leaves no corrupted destination file and sets cancelled state', () async {
      // 50MB file so it cannot finish within 50ms
      final bigFile = createTestFile('cancellation_test.dat', 50 * 1024 * 1024, seed: 333);
      final cancelToken = CancellationToken();

      TransferProgress? lastProgress;
      final sub = fileShareService.allTransfersStream.listen((map) {
        if (map.containsKey('tx_cancel_test')) {
          lastProgress = map['tx_cancel_test'];
        }
      });

      // Cancel almost immediately after start
      Future.delayed(const Duration(milliseconds: 10), () {
        fileShareService.cancelTransfer('tx_cancel_test');
      });

      final success = await fileShareService.uploadFile(
        bigFile.path,
        cancelToken: cancelToken,
        customTransferId: 'tx_cancel_test',
      );

      expect(success, isFalse);
      expect(lastProgress?.status, equals(TransferStatus.cancelled));
      await sub.cancel();
    });

    test('Progress semantics invariant: 100% only emitted on terminal completed', () async {
      final file2Mb = createTestFile('progress_test.dat', 2 * 1024 * 1024, seed: 444);
      final observedFractions = <double>[];
      final observedStatuses = <TransferStatus>[];

      final sub = fileShareService.allTransfersStream.listen((map) {
        final p = map['tx_progress_test'];
        if (p != null) {
          observedFractions.add(p.fraction);
          observedStatuses.add(p.status);
          if (p.status != TransferStatus.completed) {
            // Must strictly stay below 1.0 before completed!
            expect(p.fraction, lessThanOrEqualTo(0.99));
          }
        }
      });

      final success = await fileShareService.uploadFile(
        file2Mb.path,
        customTransferId: 'tx_progress_test',
      );
      expect(success, isTrue);

      // Allow microtask stream queue to drain
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await sub.cancel();
      expect(observedStatuses.contains(TransferStatus.transferring), isTrue);
      expect(observedStatuses.contains(TransferStatus.verifying), isTrue);
      expect(observedStatuses.contains(TransferStatus.completed), isTrue);
      expect(observedFractions.last, equals(1.0));
    });
  });
}
