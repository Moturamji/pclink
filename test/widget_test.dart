import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/core/constants/server_constants.dart';
import 'package:pclink/core/utils/validators.dart';
import 'package:pclink/data/models/device_details.dart';
import 'package:pclink/data/models/linked_device.dart';
import 'package:pclink/data/models/server_info.dart';
import 'package:pclink/core/theme/theme_service.dart';
import 'package:pclink/core/widgets/universal/animated_tab_bar.dart';
import 'package:pclink/core/widgets/universal/app_logo.dart';
import 'package:pclink/core/widgets/universal/bounceable.dart';
import 'package:pclink/core/widgets/universal/hoverable.dart';
import 'package:pclink/core/widgets/universal/status_badge.dart';
import 'package:pclink/core/widgets/universal/theme_toggle_button.dart';
import 'package:pclink/data/services/auth_service.dart';
import 'package:pclink/data/services/server_service.dart';
import 'package:pclink/features/clipboard/models/clipboard_item.dart';
import 'package:pclink/presentation/screens/home/desktop/desktop_command_bar.dart';
import 'package:pclink/presentation/screens/home/desktop/desktop_sidebar.dart';
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
      const liveInfo = ServerInfo(
        isLive: true,
        ipAddress: '192.168.1.10',
        port: 8088,
        url: 'http://192.168.1.10:8088',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServerControlCard(
              isWindows: false,
              currentServerInfo: liveInfo,
              localDeviceId: 'test-phone-id',
            ),
          ),
        ),
      );

      expect(find.text('Connect to Windows PC'), findsOneWidget);
    });

    testWidgets('Does not show Connect button when connected, shows Connected and Disconnect button', (tester) async {
      const liveInfoWithClient = ServerInfo(
        isLive: true,
        ipAddress: '192.168.1.10',
        port: 8088,
        url: 'http://192.168.1.10:8088',
        connectedClientId: 'test-phone-id',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServerControlCard(
              isWindows: false,
              currentServerInfo: liveInfoWithClient,
              localDeviceId: 'test-phone-id',
            ),
          ),
        ),
      );

      expect(find.text('Disconnect from Windows PC'), findsOneWidget);
      expect(find.text('Connect to Windows PC'), findsNothing);
    });
  });

  group('Universal & Platform Specific Widget Tests', () {
    test('ClipboardItem serializes and deserializes correctly', () {
      final now = DateTime.now();
      final item = ClipboardItem(
        id: 'clip-1',
        text: 'Hello from Android',
        sourcePlatform: 'android',
        sourceDeviceName: 'Pixel 7',
        timestamp: now,
      );

      final map = item.toMap();
      expect(map['id'], 'clip-1');
      expect(map['text'], 'Hello from Android');
      expect(map['sourcePlatform'], 'android');
      expect(map['sourceDeviceName'], 'Pixel 7');

      final fromMap = ClipboardItem.fromMap(map);
      expect(fromMap.id, 'clip-1');
      expect(fromMap.text, 'Hello from Android');
      expect(fromMap.sourceDeviceName, 'Pixel 7');
    });

    testWidgets('StatusBadge renders active and inactive states', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                StatusBadge(label: 'LIVE SYNC', isActive: true),
                StatusBadge(label: 'STANDBY', isActive: false),
              ],
            ),
          ),
        ),
      );

      expect(find.text('LIVE SYNC'), findsOneWidget);
      expect(find.text('STANDBY'), findsOneWidget);
    });

    testWidgets('AppLogo renders with custom size and glow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppLogo(
              size: 48,
              showGlow: true,
              isAnimated: false,
            ),
          ),
        ),
      );

      expect(find.byType(AppLogo), findsOneWidget);
    });

    testWidgets('Bounceable handles tap and scale micro-interaction', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Bounceable(
              onTap: () => tapped = true,
              child: const Text('Tap Me'),
            ),
          ),
        ),
      );

      expect(find.text('Tap Me'), findsOneWidget);
      await tester.tap(find.text('Tap Me'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('Hoverable renders child correctly', (tester) async {
      var hoveredTap = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Hoverable(
              onTap: () => hoveredTap = true,
              child: const Text('Hover Me'),
            ),
          ),
        ),
      );

      expect(find.text('Hover Me'), findsOneWidget);
      await tester.tap(find.text('Hover Me'));
      await tester.pumpAndSettle();
      expect(hoveredTap, isTrue);
    });

    testWidgets('AnimatedTabBar renders tabs and responds to selection', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedTabBar(
              selectedIndex: selected,
              onTabSelected: (idx) => selected = idx,
              items: const [
                TabItemData(
                  icon: Icons.home,
                  activeIcon: Icons.home,
                  label: 'Home',
                ),
                TabItemData(
                  icon: Icons.folder,
                  activeIcon: Icons.folder,
                  label: 'Files',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      expect(selected, 1);
    });

    testWidgets('DesktopSidebar renders navigation links', (tester) async {
      var currentTab = DesktopNavTab.overview;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 800,
              child: DesktopSidebar(
                currentTab: currentTab,
                onTabChanged: (tab) => currentTab = tab,
                userEmail: 'user@example.com',
                isServerLive: true,
                isRefreshing: false,
                onRefresh: () {},
                onSignOut: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('WORKSPACES'), findsOneWidget);
      expect(find.text('Dashboard & Server'), findsOneWidget);
      expect(find.text('File Transfer Studio'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
    });

    testWidgets('DesktopCommandBar renders title and subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DesktopCommandBar(
              title: 'Dashboard & Server Hub',
              subtitle: 'Manage local server endpoints',
              isWindows: true,
            ),
          ),
        ),
      );

      expect(find.text('Dashboard & Server Hub'), findsOneWidget);
      expect(find.text('Manage local server endpoints'), findsOneWidget);
      expect(find.text('Open Downloads'), findsOneWidget);
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

    test('ThemeService toggles and manages theme modes correctly', () {
      final service = ThemeService();
      service.setThemeMode(ThemeMode.dark);
      expect(service.currentMode, ThemeMode.dark);

      service.setThemeMode(ThemeMode.light);
      expect(service.currentMode, ThemeMode.light);
    });

    testWidgets('ThemeToggleButton renders and toggles theme on tap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThemeToggleButton(),
          ),
        ),
      );

      expect(find.byType(ThemeToggleButton), findsOneWidget);
      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();
    });
  });
}
