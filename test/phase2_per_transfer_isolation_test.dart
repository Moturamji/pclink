import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/core/utils/cancellation_token.dart';
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
  const testDeviceId = 'test_device_isolation_phase2';

  setUpAll(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('pclink_phase2_tests_');
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

    fileShareService = FileShareService();
    fileShareService.configure(
      getTargetServerUrls: () => [serverUrl],
      getServerStartTime: () => serverStartTime,
      deviceId: testDeviceId,
      deviceName: 'Test Phone Phase 2',
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

  File createTestFile(String name, int sizeInBytes) {
    final file = File('${tempDir.path}\\$name');
    final rand = Random(42);
    final buffer = Uint8List(sizeInBytes);
    for (int i = 0; i < sizeInBytes; i++) {
      buffer[i] = rand.nextInt(256);
    }
    file.writeAsBytesSync(buffer);
    return file;
  }

  group('Phase 2: Per-Transfer Cancellation & Isolation Tests', () {
    test('Cancelling Transfer A does not cancel Transfer B', () async {
      // Create 2 distinct files (5MB each)
      final fileA = createTestFile('file_a.dat', 5 * 1024 * 1024);
      final fileB = createTestFile('file_b.dat', 5 * 1024 * 1024);

      final tokenA = CancellationToken();
      final tokenB = CancellationToken();

      const transferIdA = 'tx_custom_test_A';
      const transferIdB = 'tx_custom_test_B';

      // Start upload A and cancel it after 50ms
      final futureA = fileShareService.uploadFile(
        fileA.path,
        cancelToken: tokenA,
        customTransferId: transferIdA,
      );

      // Start upload B concurrently
      final futureB = fileShareService.uploadFile(
        fileB.path,
        cancelToken: tokenB,
        customTransferId: transferIdB,
      );

      // Cancel only Transfer A
      await Future<void>.delayed(const Duration(milliseconds: 30));
      fileShareService.cancelTransfer(transferIdA);

      final resultA = await futureA;
      final resultB = await futureB;

      // Transfer A must be cancelled/failed
      expect(resultA, isFalse);
      // Transfer B must succeed completely!
      expect(resultB, isTrue);

      expect(tokenA.isCancelled, isTrue);
      expect(tokenB.isCancelled, isFalse);
    });

    test('Isolated activeTransfers map tracks concurrent transfer states', () async {
      final file = createTestFile('test_tracking.dat', 1 * 1024 * 1024);
      const customId = 'tx_track_123';

      final uploadFuture = fileShareService.uploadFile(
        file.path,
        customTransferId: customId,
      );

      // Wait a moment for stream to register
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fileShareService.activeTransfers.containsKey(customId), isTrue);

      final success = await uploadFuture;
      expect(success, isTrue);
    });
  });
}
