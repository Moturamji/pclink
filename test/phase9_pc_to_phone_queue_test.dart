import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/core/constants/server_constants.dart';
import 'package:pclink/data/services/file_share_service.dart';
import 'package:pclink/data/services/server_service.dart';
import 'package:pclink/features/file_share/models/shared_file.dart';
import 'package:pclink/features/file_share/models/transfer_progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('pclink_phase9_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Phase 9: PC-to-Phone Queue & Transfer Resolution', () {
    test('ServerService enqueueLocalSharedFiles creates initial queued card', () async {
      final serverService = ServerService();
      final testFile = File('${tempDir.path}${Platform.pathSeparator}test_doc.pdf');
      await testFile.writeAsString('Hello PCLink PC-to-Phone Transfer Test Content');

      final enqueued = await serverService.enqueueLocalSharedFiles(
        sourcePaths: [testFile.path],
        deviceName: 'Test Windows PC',
      );

      expect(enqueued.length, equals(1));
      final shared = enqueued.first;
      expect(shared.name, equals('test_doc.pdf'));
      expect(shared.sourcePlatform, equals('windows'));

      // Check active transfers
      final active = serverService.allTransfers;
      expect(active.containsKey(shared.id), isTrue);
      expect(active[shared.id]!.status, equals(TransferStatus.queued));
      expect(active[shared.id]!.fileName, equals('test_doc.pdf'));
    });

    test('Live HTTP download transitions server queued card to transferring and completed without orphaning', () async {
      final serverService = ServerService();
      final testFile = File('${tempDir.path}${Platform.pathSeparator}video_sample.mp4');
      final payload = List.generate(64 * 1024, (i) => i % 256);
      await testFile.writeAsBytes(payload);

      // Start the server
      final serverInfo = await serverService.startServer(
        hostIp: '127.0.0.1',
        port: 0,
      );
      expect(serverInfo, isNotNull);
      final port = serverInfo!.port;

      try {
        final enqueued = await serverService.enqueueLocalSharedFiles(
          sourcePaths: [testFile.path],
          deviceName: 'Windows Server',
        );
        expect(enqueued.isNotEmpty, isTrue);
        final fileItem = enqueued.first;
        final fileId = fileItem.id;

        // Verify initially queued
        expect(serverService.allTransfers[fileId]?.status, equals(TransferStatus.queued));

        // Track transfer progress emissions
        final statusesSeen = <TransferStatus>[];
        final sub = serverService.allTransfersStream.listen((transfers) {
          final tx = transfers[fileId];
          if (tx != null && (statusesSeen.isEmpty || statusesSeen.last != tx.status)) {
            statusesSeen.add(tx.status);
          }
        });

        // Simulate phone client download request
        final client = HttpClient();
        final uri = Uri.parse(
          'http://127.0.0.1:$port${ServerConstants.filesDownloadEndpoint}?id=$fileId&transferId=$fileId',
        );
        final req = await client.getUrl(uri);
        final resp = await req.close();
        expect(resp.statusCode, equals(HttpStatus.ok));

        final receivedBytes = <int>[];
        await for (final chunk in resp) {
          receivedBytes.addAll(chunk);
        }
        expect(receivedBytes.length, equals(payload.length));
        client.close();

        await Future<void>.delayed(const Duration(milliseconds: 200));
        await sub.cancel();

        // Verify status transitioned from queued -> transferring -> completed
        expect(statusesSeen.contains(TransferStatus.transferring), isTrue);
        expect(statusesSeen.contains(TransferStatus.completed), isTrue);

        // Verify no orphaned random rx_ or tx_ IDs in active transfers
        for (final key in serverService.allTransfers.keys) {
          expect(key.startsWith('rx_'), isFalse);
          expect(key.startsWith('tx_'), isFalse);
        }
      } finally {
        await serverService.stopServer();
      }
    });

    test('FileShareService downloadFile defaults transferId to item.id', () async {
      final fileService = FileShareService();
      final item = SharedFile(
        id: 'file_custom_12345',
        name: 'picture.png',
        size: 2048,
        sourcePlatform: 'windows',
        sourceDeviceName: 'Desktop PC',
        timestamp: DateTime.now(),
      );

      // Configure with dummy unreachable URL to test immediate transferId emission
      fileService.configure(
        getTargetServerUrls: () => ['http://127.0.0.1:54321'],
        getServerStartTime: () => null,
        deviceId: 'phone-test',
        deviceName: 'Android Phone',
      );

      final progressFuture = fileService.progressStream.first;
      unawaited(fileService.downloadFile(item));

      final firstProgress = await progressFuture;
      expect(firstProgress?.fileId, equals('file_custom_12345'));
      expect(firstProgress?.fileName, equals('picture.png'));

      fileService.cancelActiveTransfers();
      fileService.dispose();
    });

    test('enqueueDownloadFiles maintains 1-at-a-time concurrency', () async {
      final fileService = FileShareService();
      final files = List.generate(
        3,
        (i) => SharedFile(
          id: 'batch_file_$i',
          name: 'batch_$i.dat',
          size: 1024 * 10,
          sourcePlatform: 'windows',
          sourceDeviceName: 'Desktop PC',
          timestamp: DateTime.now(),
        ),
      );

      final dummyServer = await HttpServer.bind('127.0.0.1', 0);
      try {
        fileService.configure(
          getTargetServerUrls: () => ['http://127.0.0.1:${dummyServer.port}'],
          getServerStartTime: () => null,
          deviceId: 'phone-test',
          deviceName: 'Android Phone',
        );

        unawaited(fileService.enqueueDownloadFiles(files));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final active = fileService.allTransfers;
        expect(active.length, equals(3));

        // Exactly 1 in preparing/transferring, 2 in queued
        final queued = active.values.where((t) => t.status == TransferStatus.queued).length;
        final inFlight = active.values.where((t) => t.status != TransferStatus.queued).length;

        expect(queued, equals(2));
        expect(inFlight, equals(1));
      } finally {
        fileService.cancelActiveTransfers();
        fileService.dispose();
        await dummyServer.close(force: true);
      }
    });
  });
}
