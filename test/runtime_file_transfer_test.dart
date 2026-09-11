import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pclink/core/constants/server_constants.dart';
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
  const testDeviceId = 'test_android_device_id_123';

  setUpAll(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('pclink_runtime_tests_');
    serverService = ServerService();

    // Pick an available port
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
      deviceName: 'Test Phone',
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

  // Helper to generate deterministic binary payload
  File createTestFile(String name, int sizeInBytes) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    final rand = Random(42);
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

  group('Runtime File Upload Tests (Android -> Windows)', () {
    test('1 MB Uninterrupted Upload - Integrity & SHA-256 match', () async {
      final file1Mb = createTestFile('test_1mb.dat', 1 * 1024 * 1024);
      final originalHash = computeSha256(file1Mb);

      final success = await fileShareService.uploadFile(file1Mb.path);
      expect(success, isTrue);

      final sharedFiles = serverService.sharedFiles;
      expect(sharedFiles.isNotEmpty, isTrue);
      final uploadedItem = sharedFiles.firstWhere((f) => f.name == 'test_1mb.dat');
      expect(uploadedItem.size, equals(file1Mb.lengthSync()));

      final uploadedFile = File(uploadedItem.filePath!);
      expect(await uploadedFile.exists(), isTrue);
      expect(computeSha256(uploadedFile), equals(originalHash));
    });

    test('10 MB Resumable Upload with 50% Interruption and Byte-Offset Resume', () async {
      final file10Mb = createTestFile('test_10mb_resumable.dat', 10 * 1024 * 1024);
      final totalBytes = file10Mb.lengthSync();
      final originalHash = computeSha256(file10Mb);
      final encodedName = Uri.encodeQueryComponent('test_10mb_resumable.dat');
      final fileKey = '${encodedName}_$totalBytes';

      // 1. Simulate an interrupted stream at ~50% (5 MB)
      final interruptBytes = 5 * 1024 * 1024;
      final uriFirst = Uri.parse(
        '$serverUrl${ServerConstants.filesUploadEndpoint}?name=$encodedName&deviceName=TestPhone&size=$totalBytes&offset=0&fileKey=$fileKey',
      );

      final client = http.Client();
      final requestFirst = http.StreamedRequest('POST', uriFirst);
      requestFirst.headers[ServerConstants.authHeader] = testDeviceId;
      requestFirst.headers[ServerConstants.startTimeHeader] = serverStartTime;
      requestFirst.headers['Content-Type'] = 'application/octet-stream';
      // Do not set contentLength on artificially interrupted chunk to avoid client-side validator exception
      final responseFutureFirst = client.send(requestFirst);

      // Stream only up to interruptBytes then abruptly close
      var bytesSent = 0;
      await for (final chunk in file10Mb.openRead()) {
        if (bytesSent + chunk.length > interruptBytes) {
          final take = interruptBytes - bytesSent;
          if (take > 0) {
            requestFirst.sink.add(chunk.sublist(0, take));
            bytesSent += take;
          }
          break;
        }
        requestFirst.sink.add(chunk);
        bytesSent += chunk.length;
      }
      await requestFirst.sink.close();

      try {
        await responseFutureFirst;
      } catch (_) {}

      // 2. Check that the server preserved the .part file
      final checkUri = Uri.parse(
        '$serverUrl${ServerConstants.filesUploadEndpoint}?checkOffset=true&name=$encodedName&size=$totalBytes&fileKey=$fileKey',
      );
      final checkResp = await client.get(checkUri, headers: {
        ServerConstants.authHeader: testDeviceId,
        ServerConstants.startTimeHeader: serverStartTime,
      });
      expect(checkResp.statusCode, equals(200));
      final checkBody = jsonDecode(checkResp.body);
      expect(checkBody['offset'], equals(interruptBytes));

      // 3. Perform Resume from offset (50% -> 100%)
      final resumeSuccess = await fileShareService.uploadFile(file10Mb.path);
      expect(resumeSuccess, isTrue);

      final sharedFiles = serverService.sharedFiles;
      final uploadedItem = sharedFiles.firstWhere((f) => f.name == 'test_10mb_resumable.dat');
      expect(uploadedItem.size, equals(totalBytes));

      final uploadedFile = File(uploadedItem.filePath!);
      expect(await uploadedFile.exists(), isTrue);
      expect(computeSha256(uploadedFile), equals(originalHash));
    });

    test('50 MB Resumable Upload with Multi-Stage Interruptions (20%, 50%, 95%)', () async {
      final file50Mb = createTestFile('test_50mb_multi_resume.dat', 50 * 1024 * 1024);
      final totalBytes = file50Mb.lengthSync();
      final originalHash = computeSha256(file50Mb);
      final encodedName = Uri.encodeQueryComponent('test_50mb_multi_resume.dat');
      final fileKey = '${encodedName}_$totalBytes';

      final client = http.Client();
      final stages = [
        (totalBytes * 0.20).toInt(), // 20%
        (totalBytes * 0.50).toInt(), // 50%
        (totalBytes * 0.95).toInt(), // 95%
      ];

      var currentOffset = 0;

      for (final targetOffset in stages) {
        final uri = Uri.parse(
          '$serverUrl${ServerConstants.filesUploadEndpoint}?name=$encodedName&deviceName=TestPhone&size=$totalBytes&offset=$currentOffset&fileKey=$fileKey',
        );
        final req = http.StreamedRequest('POST', uri);
        req.headers[ServerConstants.authHeader] = testDeviceId;
        req.headers[ServerConstants.startTimeHeader] = serverStartTime;
        req.headers['Content-Type'] = 'application/octet-stream';
        // Omit contentLength on artificially interrupted segments
        final respFuture = client.send(req);

        var bytesSent = currentOffset;
        await for (final chunk in file50Mb.openRead(currentOffset)) {
          if (bytesSent + chunk.length > targetOffset) {
            final take = targetOffset - bytesSent;
            if (take > 0) {
              req.sink.add(chunk.sublist(0, take));
              bytesSent += take;
            }
            break;
          }
          req.sink.add(chunk);
          bytesSent += chunk.length;
        }
        await req.sink.close();

        try {
          await respFuture;
        } catch (_) {}
        currentOffset = targetOffset;

        // Verify offset recorded on server
        final checkUri = Uri.parse(
          '$serverUrl${ServerConstants.filesUploadEndpoint}?checkOffset=true&name=$encodedName&size=$totalBytes&fileKey=$fileKey',
        );
        final checkResp = await client.get(checkUri, headers: {
          ServerConstants.authHeader: testDeviceId,
          ServerConstants.startTimeHeader: serverStartTime,
        });
        expect(checkResp.statusCode, equals(200));
        final checkBody = jsonDecode(checkResp.body);
        expect(checkBody['offset'], equals(currentOffset));
      }

      // Final Resume from 95% to 100% via FileShareService
      final resumeSuccess = await fileShareService.uploadFile(file50Mb.path);
      expect(resumeSuccess, isTrue);

      final uploadedItem = serverService.sharedFiles.firstWhere(
        (f) => f.name == 'test_50mb_multi_resume.dat',
      );
      expect(uploadedItem.size, equals(totalBytes));
      final uploadedFile = File(uploadedItem.filePath!);
      expect(computeSha256(uploadedFile), equals(originalHash));
    });
  });

  group('Runtime File Download Tests (Windows -> Android with HTTP Range)', () {
    test('10 MB Resumable Download with HTTP Range 206 Partial Content', () async {
      final sourceFile = createTestFile('test_download_10mb.dat', 10 * 1024 * 1024);
      final totalBytes = sourceFile.lengthSync();
      final originalHash = computeSha256(sourceFile);

      // Register file on server
      final sharedItem = await serverService.addLocalSharedFile(
        sourcePath: sourceFile.path,
        deviceName: 'Mohit PC',
      );
      expect(sharedItem, isNotNull);

      // 1. Partial GET request with Range: bytes=0-4999999 (First 5 MB)
      final client = http.Client();
      final uri = Uri.parse(
        '$serverUrl${ServerConstants.filesDownloadEndpoint}?id=${sharedItem!.id}',
      );

      final reqFirst = http.Request('GET', uri);
      reqFirst.headers[ServerConstants.authHeader] = testDeviceId;
      reqFirst.headers[ServerConstants.startTimeHeader] = serverStartTime;
      reqFirst.headers['Range'] = 'bytes=0-5242879'; // First 5 MB

      final respFirst = await client.send(reqFirst);
      expect(respFirst.statusCode, equals(206)); // Partial content
      expect(respFirst.headers['accept-ranges'], equals('bytes'));
      expect(respFirst.headers['content-range'], contains('bytes 0-5242879/$totalBytes'));

      final partDownloadDir = await Directory.systemTemp.createTemp('pclink_dl_test_');
      final partFile = File('${partDownloadDir.path}${Platform.pathSeparator}.part_${sharedItem.id}_${sharedItem.name}');
      final sink = partFile.openWrite();
      await for (final chunk in respFirst.stream) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      expect(partFile.lengthSync(), equals(5242880));

      // 2. Second GET request with Range: bytes=5242880- (Remaining 5 MB)
      final reqSecond = http.Request('GET', uri);
      reqSecond.headers[ServerConstants.authHeader] = testDeviceId;
      reqSecond.headers[ServerConstants.startTimeHeader] = serverStartTime;
      reqSecond.headers['Range'] = 'bytes=5242880-';

      final respSecond = await client.send(reqSecond);
      expect(respSecond.statusCode, equals(206));
      expect(respSecond.headers['content-range'], contains('bytes 5242880-${totalBytes - 1}/$totalBytes'));

      final sinkSecond = partFile.openWrite(mode: FileMode.append);
      await for (final chunk in respSecond.stream) {
        sinkSecond.add(chunk);
      }
      await sinkSecond.flush();
      await sinkSecond.close();

      expect(partFile.lengthSync(), equals(totalBytes));

      // 3. Finalize and verify SHA-256 byte-for-byte match
      final finalDest = File('${partDownloadDir.path}${Platform.pathSeparator}${sharedItem.name}');
      await partFile.rename(finalDest.path);

      expect(finalDest.lengthSync(), equals(totalBytes));
      expect(computeSha256(finalDest), equals(originalHash));

      await partDownloadDir.delete(recursive: true);
    });

    test('Full Download via FileShareService - End-to-End Test', () async {
      final sourceFile = createTestFile('test_download_e2e.dat', 2 * 1024 * 1024);
      final originalHash = computeSha256(sourceFile);
      final sharedItem = await serverService.addLocalSharedFile(
        sourcePath: sourceFile.path,
        deviceName: 'Mohit PC',
      );
      expect(sharedItem, isNotNull);

      final downloadedFile = await fileShareService.downloadFile(sharedItem!);
      expect(downloadedFile, isNotNull);
      expect(await downloadedFile!.exists(), isTrue);
      expect(downloadedFile.lengthSync(), equals(sourceFile.lengthSync()));
      expect(computeSha256(downloadedFile), equals(originalHash));
    });
  });
}
