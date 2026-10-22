import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/data/services/file_share_service.dart';
import 'package:pclink/data/services/server_service.dart';

/// A phone whose final upload reply was lost retries with the same transfer
/// id. The PC must confirm the already-finalized file instead of accepting a
/// second full copy, while a deliberate re-send (new transfer id) still works.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ServerService serverService;
  late FileShareService fileShareService;

  setUpAll(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('pclink_lost_reply_');
    serverService = ServerService();
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final info = await serverService.startServer(hostIp: '127.0.0.1', port: port);
    expect(info, isNotNull);
    final startTime = info!.startedAt!.toIso8601String();

    fileShareService = FileShareService()
      ..configure(
        getTargetServerUrls: () => ['http://127.0.0.1:$port'],
        getServerStartTime: () => startTime,
        deviceId: 'lost_reply_test_phone',
        deviceName: 'Test Phone',
      );
  });

  tearDownAll(() async {
    await serverService.stopServer();
    serverService.dispose();
    fileShareService.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  File createFile(String name, int size) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    final rand = Random(7);
    file.writeAsBytesSync(Uint8List.fromList(List.generate(size, (_) => rand.nextInt(256))));
    return file;
  }

  int copiesOf(String prefix) =>
      serverService.sharedFiles.where((f) => f.name.startsWith(prefix)).length;

  test('retry with the same transfer id does not create a duplicate', () async {
    final file = createFile('lost_reply_sample.dat', 512 * 1024);
    const transferId = 'tx_lost_reply_retry';

    expect(await fileShareService.uploadFile(file.path, customTransferId: transferId), isTrue);
    expect(copiesOf('lost_reply_sample'), 1);

    // Same transfer id again = the phone retrying after a lost final reply.
    expect(await fileShareService.uploadFile(file.path, customTransferId: transferId), isTrue);
    expect(copiesOf('lost_reply_sample'), 1);
  });

  test('a deliberate re-send with a new transfer id still creates a new copy', () async {
    final file = createFile('resend_sample.dat', 256 * 1024);

    expect(await fileShareService.uploadFile(file.path, customTransferId: 'tx_resend_1'), isTrue);
    expect(await fileShareService.uploadFile(file.path, customTransferId: 'tx_resend_2'), isTrue);
    expect(copiesOf('resend_sample'), 2);
  });
}
