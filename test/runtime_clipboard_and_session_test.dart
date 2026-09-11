import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pclink/core/constants/server_constants.dart';
import 'package:pclink/data/services/server_service.dart';
import 'package:pclink/features/clipboard/models/clipboard_item.dart';
import 'package:pclink/features/clipboard/services/clipboard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ServerService serverService;
  late ClipboardService clipboardService;
  late int serverPort;
  late String serverUrl;
  late String serverStartTime;
  const testDeviceId = 'test_android_device_id_clipboard';

  setUpAll(() async {
    HttpOverrides.global = null;
    serverService = ServerService();

    final serverInfo = await serverService.startServer(
      hostIp: '127.0.0.1',
      port: 0,
    );
    expect(serverInfo, isNotNull);
    serverPort = serverInfo!.port;
    serverUrl = 'http://127.0.0.1:$serverPort';
    serverStartTime = serverInfo.startedAt!.toIso8601String();

    clipboardService = ClipboardService();
  });

  tearDownAll(() async {
    clipboardService.stopListening();
    clipboardService.dispose();
    await serverService.stopServer();
    serverService.dispose();
  });

  group('Runtime Clipboard Bidirectional Tests', () {
    test('Android -> Windows: Direct Non-blocking POST is received by Server', () async {
      final clipItem = ClipboardItem(
        id: 'clip_android_1',
        text: 'Hello Windows PC from Android Test',
        sourcePlatform: 'android',
        sourceDeviceName: 'Pixel 9',
        timestamp: DateTime.now(),
      );

      final client = http.Client();
      final uri = Uri.parse('$serverUrl${ServerConstants.clipboardEndpoint}');
      final resp = await client.post(
        uri,
        headers: {
          ServerConstants.authHeader: testDeviceId,
          ServerConstants.startTimeHeader: serverStartTime,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(clipItem.toMap()),
      );

      expect(resp.statusCode, equals(200));
      final body = jsonDecode(resp.body);
      expect(body['success'], isTrue);
      expect(body['id'], equals('clip_android_1'));

      final serverHistory = serverService.clipboardHistory;
      expect(serverHistory.any((c) => c.text == 'Hello Windows PC from Android Test'), isTrue);
    });

    test('Windows -> Android: PC adds clip and Android fetches via /api/clipboard/latest', () async {
      final pcClip = ClipboardItem(
        id: 'clip_win_1',
        text: 'Hello Android from Windows Server',
        sourcePlatform: 'windows',
        sourceDeviceName: 'Mohit PC',
        timestamp: DateTime.now(),
      );

      serverService.addLocalClipboardItem(pcClip);

      final client = http.Client();
      final uri = Uri.parse('$serverUrl${ServerConstants.clipboardLatestEndpoint}');
      final resp = await client.get(uri);

      expect(resp.statusCode, equals(200));
      final dynamic data = jsonDecode(resp.body);
      expect(data, isNotNull);
      final fetchedItem = ClipboardItem.fromMap(data);
      expect(fetchedItem.text, equals('Hello Android from Windows Server'));
      expect(fetchedItem.sourcePlatform, equals('windows'));
    });

    test('Rapid successive clipboard events are all captured without loss', () async {
      final client = http.Client();
      final uri = Uri.parse('$serverUrl${ServerConstants.clipboardEndpoint}');

      for (int i = 0; i < 5; i++) {
        final item = ClipboardItem(
          id: 'rapid_clip_$i',
          text: 'Rapid message index $i',
          sourcePlatform: 'android',
          sourceDeviceName: 'Pixel 9',
          timestamp: DateTime.now(),
        );

        final resp = await client.post(
          uri,
          headers: {
            ServerConstants.authHeader: testDeviceId,
            ServerConstants.startTimeHeader: serverStartTime,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(item.toMap()),
        );
        expect(resp.statusCode, equals(200));
      }

      final history = serverService.clipboardHistory;
      for (int i = 0; i < 5; i++) {
        expect(history.any((c) => c.text == 'Rapid message index $i'), isTrue);
      }
    });

    test('Received Android clip preserves Android sourcePlatform tag without flipping to Windows', () async {
      final clip = ClipboardItem(
        id: 'clip_tag_test',
        text: 'Origin Source Tag Test Message',
        sourcePlatform: 'android',
        sourceDeviceName: 'Pixel 9 Pro',
        timestamp: DateTime.now(),
      );

      final client = http.Client();
      final uri = Uri.parse('$serverUrl${ServerConstants.clipboardEndpoint}');
      final resp = await client.post(
        uri,
        headers: {
          ServerConstants.authHeader: testDeviceId,
          ServerConstants.startTimeHeader: serverStartTime,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(clip.toMap()),
      );
      expect(resp.statusCode, equals(200));

      final storedItem = serverService.clipboardHistory.firstWhere((c) => c.id == 'clip_tag_test');
      expect(storedItem.sourcePlatform, equals('android'));
      expect(storedItem.sourceDeviceName, equals('Pixel 9 Pro'));
      expect(storedItem.isFromAndroid, isTrue);
      expect(storedItem.isFromWindows, isFalse);
    });
  });

  group('Session Identity & Server Restart Validation Tests', () {
    test('Valid session token matches and authorizes request', () async {
      final client = http.Client();
      final uri = Uri.parse('$serverUrl${ServerConstants.clipboardEndpoint}');

      final resp = await client.post(
        uri,
        headers: {
          ServerConstants.authHeader: testDeviceId,
          ServerConstants.startTimeHeader: serverStartTime,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'id': 'test_auth_ok',
          'text': 'Auth token test',
          'sourcePlatform': 'android',
          'sourceDeviceName': 'Pixel 9',
        }),
      );
      expect(resp.statusCode, equals(200));
    });

    test('Invalid / Unknown session token is rejected with 401 Unauthorized', () async {
      final client = http.Client();
      final uri = Uri.parse('$serverUrl${ServerConstants.clipboardEndpoint}');

      final resp = await client.post(
        uri,
        headers: {
          ServerConstants.authHeader: testDeviceId,
          ServerConstants.startTimeHeader: '2020-01-01T00:00:00.000Z', // completely wrong session
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'id': 'test_auth_fail',
          'text': 'Should be rejected',
          'sourcePlatform': 'android',
          'sourceDeviceName': 'Pixel 9',
        }),
      );
      expect(resp.statusCode, equals(401));
    });

    test('Server restart creates new session and validates updated start time', () async {
      await serverService.stopServer();
      await Future.delayed(const Duration(milliseconds: 200));

      final newInfo = await serverService.startServer(
        hostIp: '127.0.0.1',
        port: 0,
      );
      expect(newInfo, isNotNull);
      final newStartTime = newInfo!.startedAt!.toIso8601String();
      final newServerUrl = 'http://127.0.0.1:${newInfo.port}';

      final client = http.Client();
      final uri = Uri.parse('$newServerUrl${ServerConstants.clipboardEndpoint}');

      // Old session token should now fail
      final respOld = await client.post(
        uri,
        headers: {
          ServerConstants.authHeader: testDeviceId,
          ServerConstants.startTimeHeader: '2021-01-01T00:00:00.000Z',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'id': 'test_after_restart_old',
          'text': 'Old session text',
          'sourcePlatform': 'android',
          'sourceDeviceName': 'Pixel 9',
        }),
      );
      expect(respOld.statusCode, equals(401));

      // New session token succeeds immediately
      final respNew = await client.post(
        uri,
        headers: {
          ServerConstants.authHeader: testDeviceId,
          ServerConstants.startTimeHeader: newStartTime,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'id': 'test_after_restart_new',
          'text': 'New session text',
          'sourcePlatform': 'android',
          'sourceDeviceName': 'Pixel 9',
        }),
      );
      expect(respNew.statusCode, equals(200));
    });
  });
}
