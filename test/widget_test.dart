import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/core/constants/server_constants.dart';
import 'package:pclink/core/utils/validators.dart';
import 'package:pclink/data/models/device_details.dart';
import 'package:pclink/data/models/linked_device.dart';
import 'package:pclink/data/models/server_info.dart';
import 'package:pclink/core/widgets/universal/status_badge.dart';
import 'package:pclink/data/services/auth_service.dart';
import 'package:pclink/data/services/server_service.dart';
import 'package:pclink/features/clipboard/models/clipboard_item.dart';
import 'package:pclink/presentation/screens/home/widgets/server_control_card.dart';

void main() {
  group('Validators Unit Tests', () {
    test('validateEmail validates correctly', () {
      expect(Validators.validateEmail(''), 'Please enter your email');
      expect(Validators.validateEmail('invalid-email'), 'Please enter a valid email address');
      expect(Validators.validateEmail('user@domain.com'), isNull);
    });

    test('validatePassword validates min length', () {
      expect(Validators.validatePassword(''), 'Please enter your password');
      expect(Validators.validatePassword('12345'), 'Password must be at least 6 characters');
      expect(Validators.validatePassword('123456'), isNull);
    });

    test('validateConfirmPassword checks equality', () {
      expect(Validators.validateConfirmPassword('', '123456'), 'Please confirm your password');
      expect(Validators.validateConfirmPassword('123', '123456'), 'Passwords do not match');
      expect(Validators.validateConfirmPassword('123456', '123456'), isNull);
    });
  });

  group('DeviceDetails Model Tests', () {
    test('DeviceDetails computes helper getters correctly', () {
      const details = DeviceDetails(
        platform: 'Android',
        deviceId: 'test-device-id',
        deviceName: 'Pixel 7',
        osVersion: 'Android 14',
        primaryIp: '192.168.1.100',
        interfaces: [],
        additionalDetails: {},
      );

      expect(details.isAndroid, isTrue);
      expect(details.isWindows, isFalse);
      expect(details.isConnected, isTrue);
    });
  });

  group('LinkedDevice Model Tests', () {
    test('LinkedDevice serializes and deserializes correctly', () {
      final map = {
        'deviceId': 'android-uuid-1234',
        'deviceName': 'TECNO KG5k',
        'osVersion': 'Android 11',
        'ipAddress': '192.168.1.45',
        'lastSeen': '2026-09-08T12:00:00.000Z',
        'isOnline': true,
      };

      final device = LinkedDevice.fromMap('android', map);
      expect(device.platformKey, 'android');
      expect(device.isAndroid, isTrue);
      expect(device.isWindows, isFalse);
      expect(device.deviceId, 'android-uuid-1234');
      expect(device.ipAddress, '192.168.1.45');
      expect(device.isOnline, isTrue);

      final toMapResult = device.toMap();
      expect(toMapResult['deviceId'], 'android-uuid-1234');
      expect(toMapResult['ipAddress'], '192.168.1.45');
      expect(toMapResult['isOnline'], isTrue);
    });
  });

  group('ServerInfo Model Tests', () {
    test('ServerInfo serializes and deserializes correctly', () {
      final now = DateTime.now();
      final map = {
        'isLive': true,
        'ipAddress': '192.168.1.50',
        'port': ServerConstants.defaultPort,
        'url': 'http://192.168.1.50:8088',
        'publicIp': '203.0.113.195',
        'publicUrl': 'http://203.0.113.195:8088',
        'connectionMode': 'cloud_relay',
        'startedAt': now.toIso8601String(),
        'lastHeartbeat': now.toIso8601String(),
        'connectedClientId': 'android-client-123',
      };

      final serverInfo = ServerInfo.fromMap(map);
      expect(serverInfo.isLive, isTrue);
      expect(serverInfo.ipAddress, '192.168.1.50');
      expect(serverInfo.port, 8088);
      expect(serverInfo.url, 'http://192.168.1.50:8088');
      expect(serverInfo.publicIp, '203.0.113.195');
      expect(serverInfo.publicUrl, 'http://203.0.113.195:8088');
      expect(serverInfo.connectionMode, 'cloud_relay');
      expect(serverInfo.connectedClientId, 'android-client-123');

      final serialized = serverInfo.toMap();
      expect(serialized['isLive'], isTrue);
      expect(serialized['ipAddress'], '192.168.1.50');
      expect(serialized['publicIp'], '203.0.113.195');
      expect(serialized['connectionMode'], 'cloud_relay');
      expect(serialized['port'], 8088);
      expect(serialized['connectedClientId'], 'android-client-123');
    });

    test('ServerInfo equality works properly', () {
      const s1 = ServerInfo(
        isLive: true,
        ipAddress: '192.168.1.10',
        port: 8088,
        url: 'http://192.168.1.10:8088',
        publicIp: '203.0.113.10',
        connectionMode: 'cloud_relay',
      );
      const s2 = ServerInfo(
        isLive: true,
        ipAddress: '192.168.1.10',
        port: 8088,
        url: 'http://192.168.1.10:8088',
        publicIp: '203.0.113.10',
        connectionMode: 'cloud_relay',
      );
      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
    });
  });


  group('AuthService Tests', () {
    test('getErrorMessage returns proper message for exceptions', () {
      expect(
        AuthService.getErrorMessage(Exception('Generic error')),
        contains('Generic error'),
      );
    });
  });

  group('ServerControlCard Widget Tests', () {
    testWidgets('Shows Connect button when disconnected and server is live', (tester) async {
      final server = ServerInfo(
        isLive: true,
        ipAddress: '192.168.1.10',
        port: 8088,
        url: 'http://192.168.1.10:8088',
        connectedClientId: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServerControlCard(
              isWindows: false,
              localDeviceId: 'my-android-id',
              serverStream: Stream.value(server),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Connect to Windows PC'), findsOneWidget);
      expect(find.text('Connected to Windows PC'), findsNothing);
      expect(find.text('Disconnect from Windows PC'), findsNothing);
    });

    testWidgets('Does not show Connect button when connected, shows Connected and Disconnect button', (tester) async {
      final server = ServerInfo(
        isLive: true,
        ipAddress: '192.168.1.10',
        port: 8088,
        url: 'http://192.168.1.10:8088',
        connectedClientId: 'my-android-id',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServerControlCard(
              isWindows: false,
              localDeviceId: 'my-android-id',
              serverStream: Stream.value(server),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // "Connect to Windows PC" must NOT be shown when connected
      expect(find.text('Connect to Windows PC'), findsNothing);
      // Connected state UI elements MUST be shown
      expect(find.text('Connected to Windows PC'), findsOneWidget);
      expect(find.text('Disconnect from Windows PC'), findsOneWidget);
      expect(find.text('CONNECTED'), findsOneWidget);
    });
  });

  group('Clipboard Feature & Universal Widget Tests', () {
    test('ClipboardItem serializes and deserializes correctly', () {
      final now = DateTime.now();
      final item = ClipboardItem(
        id: 'clip_123',
        text: 'Hello from Windows PC!',
        sourcePlatform: 'windows',
        sourceDeviceName: 'Desktop-Workstation',
        timestamp: now,
      );

      expect(item.isFromWindows, isTrue);
      expect(item.isFromAndroid, isFalse);
      expect(item.charCount, 22);
      expect(item.previewText, 'Hello from Windows PC!');

      final map = item.toMap();
      expect(map['id'], 'clip_123');
      expect(map['text'], 'Hello from Windows PC!');
      expect(map['sourcePlatform'], 'windows');

      final fromMapItem = ClipboardItem.fromMap(map);
      expect(fromMapItem.id, 'clip_123');
      expect(fromMapItem.text, 'Hello from Windows PC!');
      expect(fromMapItem.sourcePlatform, 'windows');
    });

    testWidgets('StatusBadge renders active and inactive states', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              label: 'TEST SYNC',
              isActive: true,
            ),
          ),
        ),
      );

      expect(find.text('TEST SYNC'), findsOneWidget);
    });

    test('ServerService stores and clears local clipboard items in memory', () {
      final serverService = ServerService();
      expect(serverService.clipboardHistory, isEmpty);

      final item = ClipboardItem(
        id: 'c1',
        text: 'Direct local clip',
        sourcePlatform: 'windows',
        sourceDeviceName: 'PC',
        timestamp: DateTime.now(),
      );

      serverService.addLocalClipboardItem(item);
      expect(serverService.clipboardHistory.length, 1);
      expect(serverService.clipboardHistory.first.text, 'Direct local clip');

      serverService.clearClipboardHistory();
      expect(serverService.clipboardHistory, isEmpty);
    });
  });
}

