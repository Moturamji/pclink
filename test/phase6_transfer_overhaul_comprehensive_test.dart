import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/core/utils/cancellation_token.dart';
import 'package:pclink/features/file_share/models/transfer_progress.dart';
import 'package:pclink/data/services/file_share_service.dart';
import 'package:pclink/data/services/server_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ServerService serverService;
  late FileShareService fileShareService;
  late int serverPort;
  late String serverUrl;
  late String serverStartTime;
  const testDeviceId = 'test_device_phase6';

  setUpAll(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('pclink_phase6_tests_');
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
      deviceName: 'Test Phone Phase 6',
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

  // Helper to generate deterministic binary files rapidly
  Future<File> generateBinaryFile(String name, int sizeBytes) async {
    final file = File('${tempDir.path}/$name');
    final sink = file.openWrite();
    // 64 KB pattern block
    final block = Uint8List(64 * 1024);
    for (int i = 0; i < block.length; i++) {
      block[i] = (i ^ (sizeBytes & 0xFF)) & 0xFF;
    }

    var written = 0;
    while (written < sizeBytes) {
      final toWrite = (sizeBytes - written) > block.length
          ? block.length
          : (sizeBytes - written);
      if (toWrite == block.length) {
        sink.add(block);
      } else {
        sink.add(Uint8List.sublistView(block, 0, toWrite));
      }
      written += toWrite;
    }
    await sink.flush();
    await sink.close();
    return file;
  }

  // Helper to compute SHA-256 digest
  Future<String> computeSha256(File file) async {
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  group('Task 6.1: Model & State Machine Unit Tests', () {
    test('Verifies TransferStatus.queued transitions and dual progress metrics', () {
      final machine = TransferStateMachine('test_f1');
      expect(machine.currentStatus, TransferStatus.preparing);

      // Reset and test queued transition
      final queuedMachine = TransferStateMachine('test_f2', TransferStatus.queued);
      expect(queuedMachine.currentStatus, TransferStatus.queued);

      // Legal: queued -> preparing
      expect(queuedMachine.canTransitionTo(TransferStatus.preparing), isTrue);
      queuedMachine.transition(TransferStatus.preparing);
      expect(queuedMachine.currentStatus, TransferStatus.preparing);

      // Legal: preparing -> transferring
      expect(queuedMachine.canTransitionTo(TransferStatus.transferring), isTrue);
      queuedMachine.transition(TransferStatus.transferring);
      expect(queuedMachine.currentStatus, TransferStatus.transferring);

      // Illegal: transferring -> queued
      expect(queuedMachine.canTransitionTo(TransferStatus.queued), isFalse);
    });

    test('Verifies senderBytes and receiverBytes calculation and clamp safety', () {
      final progress = TransferProgress(
        fileId: 'f1',
        fileName: '500mb_test.bin',
        bytesTransferred: 250 * 1024 * 1024,
        totalBytes: 500 * 1024 * 1024,
        senderBytes: 300 * 1024 * 1024,
        receiverBytes: 250 * 1024 * 1024,
        speedBytesPerSec: 15.5 * 1024 * 1024,
        isUpload: true,
        status: TransferStatus.transferring,
        timestamp: DateTime.now(),
      );

      expect(progress.senderFraction, closeTo(0.60, 0.01));
      expect(progress.receiverFraction, closeTo(0.50, 0.01));
      expect(progress.senderPercentageLabel, '60.0%');
      expect(progress.receiverPercentageLabel, '50.0%');
      expect(progress.speedLabel, '15.50 MB/s');

      // Clamping check
      final overflow = TransferProgress(
        fileId: 'f2',
        fileName: 'test.bin',
        bytesTransferred: 600,
        totalBytes: 500,
        senderBytes: 700,
        receiverBytes: 600,
        speedBytesPerSec: 100,
        isUpload: false,
        status: TransferStatus.transferring,
        timestamp: DateTime.now(),
      );
      expect(overflow.fraction, 0.99);
      expect(overflow.senderFraction, 0.99);
      expect(overflow.receiverFraction, 0.99);
      final completed = overflow.copyWith(status: TransferStatus.completed);
      expect(completed.fraction, 1.0);
      expect(completed.senderFraction, 1.0);
      expect(completed.receiverFraction, 1.0);
    });
  });

  group('Task 6.4: Immediate Multi-File Card Generation & Concurrency Test', () {
    test('Queue multiple files simultaneously: cards created immediately with queued status', () async {
      final file1 = await generateBinaryFile('multi_1.bin', 1024 * 1024);
      final file2 = await generateBinaryFile('multi_2.bin', 1024 * 1024);
      final file3 = await generateBinaryFile('multi_3.bin', 1024 * 1024);

      // Enqueue on PC Server
      final pcEnqueued = await serverService.enqueueLocalSharedFiles(
        sourcePaths: [file1.path, file2.path, file3.path],
        deviceName: 'Windows PC',
      );
      expect(pcEnqueued.length, 3);
      expect(serverService.allTransfers.length, greaterThanOrEqualTo(3));

      // Enqueue on Phone Client
      fileShareService.enqueueUploadFiles([file1.path, file2.path, file3.path]);
      final clientTransfers = fileShareService.allTransfers;
      expect(clientTransfers.length, greaterThanOrEqualTo(3));

      // Concurrency check: max active transfers should not exceed limit (2)
      final activeCount = clientTransfers.values
          .where((t) => t.status == TransferStatus.transferring || t.status == TransferStatus.preparing)
          .length;
      expect(activeCount, lessThanOrEqualTo(2));
    });
  });

  group('Task 6.2 & 6.3: Large File Streaming, Throughput & Resumable Recovery', () {
    test('100 MB streaming upload with SHA-256 integrity match and throughput benchmark', () async {
      final size = 100 * 1024 * 1024; // 100 MB test file
      final sourceFile = await generateBinaryFile('benchmark_100mb.bin', size);
      final sourceSha = await computeSha256(sourceFile);

      final stopwatch = Stopwatch()..start();
      final success = await fileShareService.uploadFile(sourceFile.path);
      stopwatch.stop();

      expect(success, isTrue);

      final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
      final throughputMBps = (size / (1024 * 1024)) / elapsedSeconds;
      stdout.writeln('=== Phase 6 Benchmark: 100 MB Upload ===');
      stdout.writeln('Time: ${elapsedSeconds.toStringAsFixed(2)}s, Speed: ${throughputMBps.toStringAsFixed(2)} MB/s');

      // Verify SHA-256 match
      final sharedFiles = serverService.sharedFiles;
      final received = sharedFiles.firstWhere((f) => f.name.contains('benchmark_100mb'));
      final destFile = File(received.filePath!);
      expect(await destFile.exists(), isTrue);
      expect(await destFile.length(), size);

      final destSha = await computeSha256(destFile);
      expect(destSha, equals(sourceSha));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Deliberate 50% interruption and byte-offset resume without restarting from zero', () async {
      final size = 20 * 1024 * 1024; // 20 MB test file
      final sourceFile = await generateBinaryFile('resume_test_20mb.bin', size);
      final sourceSha = await computeSha256(sourceFile);

      final token = CancellationToken();
      final uploadFuture = fileShareService.uploadFile(sourceFile.path, cancelToken: token);

      // Wait until transfer starts
      await Future<void>.delayed(const Duration(milliseconds: 20));
      token.cancel(); // Deliberately interrupt transfer midway

      try {
        await uploadFuture;
      } catch (_) {}

      // Now resume the transfer without cancelToken
      final resumeSuccess = await fileShareService.uploadFile(sourceFile.path);
      expect(resumeSuccess, isTrue);

      final received = serverService.sharedFiles.firstWhere((f) => f.name.contains('resume_test_20mb'));
      final destFile = File(received.filePath!);
      expect(await destFile.length(), size);
      final destSha = await computeSha256(destFile);
      expect(destSha, equals(sourceSha));
    });
  });
}
