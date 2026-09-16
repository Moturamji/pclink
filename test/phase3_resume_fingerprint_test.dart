import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pclink/core/constants/server_constants.dart';
import 'package:pclink/core/utils/transfer_fingerprint.dart';
import 'package:pclink/data/services/server_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late ServerService serverService;
  late int serverPort;
  late String serverUrl;
  late String serverStartTime;
  const testDeviceId = 'test_device_fingerprint_phase3';

  setUpAll(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('pclink_phase3_tests_');
    serverService = ServerService();

    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    serverPort = socket.port;
    await socket.close();

    final serverInfo = await serverService.startServer(
      hostIp: '127.0.0.1',
      port: serverPort,
    );
    serverUrl = 'http://127.0.0.1:$serverPort';
    serverStartTime = serverInfo!.startedAt!.toIso8601String();
  });

  tearDownAll(() async {
    await serverService.stopServer();
    serverService.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File createTestFile(String name, int sizeInBytes, [int seed = 42]) {
    final file = File('${tempDir.path}\\$name');
    final rand = Random(seed);
    final buffer = Uint8List(sizeInBytes);
    for (int i = 0; i < sizeInBytes; i++) {
      buffer[i] = rand.nextInt(256);
    }
    file.writeAsBytesSync(buffer);
    return file;
  }

  group('Phase 3: Source Fingerprint & Resume Metadata Tests', () {
    test('Fingerprint is deterministic and detects content modification', () async {
      final file1 = createTestFile('original.bin', 100 * 1024, 1);
      final fp1 = await TransferFingerprint.computeSourceFingerprint(file1);
      final fp1Again = await TransferFingerprint.computeSourceFingerprint(file1);

      expect(fp1, equals(fp1Again));
      expect(fp1.isNotEmpty, isTrue);

      // Modify the file content slightly
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final bytes = file1.readAsBytesSync();
      bytes[0] = (bytes[0] + 1) % 256;
      file1.writeAsBytesSync(bytes);

      final fpModified = await TransferFingerprint.computeSourceFingerprint(file1);
      expect(fpModified, isNot(equals(fp1)));
    });

    test('Resume with modified source file safely resets offset to 0 and avoids corruption', () async {
      final testFile = createTestFile('resumable_test.bin', 2 * 1024 * 1024, 100);
      final totalBytes = testFile.lengthSync();
      final initialFp = await TransferFingerprint.computeSourceFingerprint(testFile);
      final encodedName = Uri.encodeQueryComponent('resumable_test.bin');
      final fileKey = '${encodedName}_$totalBytes';

      final client = http.Client();

      // Send first 1MB of the original file
      final uri1 = Uri.parse(
        '$serverUrl${ServerConstants.filesUploadEndpoint}?name=$encodedName&deviceName=TestPhone&size=$totalBytes&offset=0&fileKey=$fileKey&fingerprint=$initialFp',
      );
      final req1 = http.StreamedRequest('POST', uri1);
      req1.headers[ServerConstants.authHeader] = testDeviceId;
      req1.headers[ServerConstants.startTimeHeader] = serverStartTime;
      req1.headers['Content-Type'] = 'application/octet-stream';
      final resp1 = client.send(req1);

      // Stream exactly 1MB then sever connection
      const halfBytes = 1 * 1024 * 1024;
      await for (final chunk in testFile.openRead(0, halfBytes)) {
        req1.sink.add(chunk);
      }
      await req1.sink.close();
      try {
        await resp1;
      } catch (_) {}

      // 1. Check offset with matching fingerprint -> should return 1MB
      final checkUriMatching = Uri.parse(
        '$serverUrl${ServerConstants.filesUploadEndpoint}?checkOffset=true&name=$encodedName&size=$totalBytes&fileKey=$fileKey&fingerprint=$initialFp',
      );
      final checkResp1 = await client.get(checkUriMatching, headers: {
        ServerConstants.authHeader: testDeviceId,
        ServerConstants.startTimeHeader: serverStartTime,
      });
      expect(checkResp1.statusCode, equals(200));
      final body1 = jsonDecode(checkResp1.body);
      expect(body1['offset'], equals(halfBytes));

      // 2. Now simulate source file mutation on device!
      final newFp = 'mismatched_new_fingerprint_999';
      final checkUriMismatched = Uri.parse(
        '$serverUrl${ServerConstants.filesUploadEndpoint}?checkOffset=true&name=$encodedName&size=$totalBytes&fileKey=$fileKey&fingerprint=$newFp',
      );
      final checkResp2 = await client.get(checkUriMismatched, headers: {
        ServerConstants.authHeader: testDeviceId,
        ServerConstants.startTimeHeader: serverStartTime,
      });
      expect(checkResp2.statusCode, equals(200));
      final body2 = jsonDecode(checkResp2.body);
      // Offset MUST reset to 0 to prevent appending new data to old data!
      expect(body2['offset'], equals(0));
    });

    test('Stale .part files older than maxAge are purged', () async {
      final oldPart = File('${tempDir.path}\\.part_old_stale.tmp');
      await oldPart.writeAsString('Old Stale Bytes');
      final oldMeta = File('${tempDir.path}\\.part_old_stale.meta');
      await oldMeta.writeAsString('Old Meta');

      final freshPart = File('${tempDir.path}\\.part_fresh.tmp');
      await freshPart.writeAsString('Fresh Bytes');

      // Purge files older than 0 duration (purge all test part files)
      final purged = await TransferFingerprint.purgeStalePartFiles(
        tempDir,
        maxAge: const Duration(seconds: -1),
      );

      expect(purged, greaterThanOrEqualTo(2));
      expect(await oldPart.exists(), isFalse);
      expect(await oldMeta.exists(), isFalse);
    });
  });
}
