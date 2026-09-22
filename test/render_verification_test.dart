import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/core/constants/app_strings.dart';
import 'package:pclink/core/theme/app_theme.dart';
import 'package:pclink/data/models/device_details.dart';
import 'package:pclink/data/models/linked_device.dart';
import 'package:pclink/data/models/server_info.dart';
import 'package:pclink/presentation/screens/auth/auth_screen.dart';
import 'package:pclink/presentation/screens/home/desktop/desktop_command_bar.dart';
import 'package:pclink/presentation/screens/home/desktop/desktop_overview_tab.dart';
import 'package:pclink/presentation/screens/home/desktop/desktop_sidebar.dart';
import 'package:pclink/presentation/screens/home/mobile/mobile_connect_tab.dart';
import 'package:pclink/data/services/database_service.dart';
import 'package:pclink/data/services/server_service.dart';

class MockDatabaseService extends Fake implements DatabaseService {
  @override
  Stream<ServerInfo?> watchUserServer(User user) => const Stream.empty();
  @override
  Stream<List<LinkedDevice>> watchUserDevices(User user) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dummyDetails = DeviceDetails(
    platform: 'Windows',
    deviceId: 'win-pc-studio-01',
    deviceName: 'Studio Workstation PC',
    osVersion: 'Windows 11 23H2 (Build 22631)',
    primaryIp: '192.168.1.145',
    interfaces: const [
      NetworkAddressInfo(
        interfaceName: 'Wi-Fi 6',
        address: '192.168.1.145',
        type: InternetAddressType.IPv4,
        isLoopback: false,
      ),
    ],
    additionalDetails: const {
      'Host': 'STUDIO-WORKSTATION',
      'CPU Cores': '16 Physical (32 Logical)',
      'Memory': '64 GB DDR5',
      'Local Storage': '2.0 TB NVMe PCIe Gen4',
    },
  );

  final dummyMobileDetails = DeviceDetails(
    platform: 'Android',
    deviceId: 'android-pixel-01',
    deviceName: 'Pixel 8 Pro',
    osVersion: 'Android 14 (API 34)',
    primaryIp: '192.168.1.189',
    interfaces: const [
      NetworkAddressInfo(
        interfaceName: 'wlan0',
        address: '192.168.1.189',
        type: InternetAddressType.IPv4,
        isLoopback: false,
      ),
    ],
    additionalDetails: const {'Manufacturer': 'Google', 'Model': 'Pixel 8 Pro'},
  );

  final dummyServer = ServerInfo(
    isLive: true,
    ipAddress: '192.168.1.145',
    port: 50685,
    url: 'http://192.168.1.145:50685',
    publicUrl: null,
    startedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 24)),
    connectedClientId: 'Pixel 8 Pro (Android 14)',
  );

  testWidgets('Render and Verify AuthScreen on Mobile and Desktop Viewports', (
    tester,
  ) async {
    // 1. Mobile 390x844
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const AuthScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Sign In'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == 'Welcome to PCLink' ||
                w.data == 'PCLink Windows Sign In'),
      ),
      findsOneWidget,
    );

    // 2. Desktop 1280x800
    tester.view.physicalSize = const Size(1280 * 1.5, 800 * 1.5);
    tester.view.devicePixelRatio = 1.5;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const AuthScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == 'Hardware-Link Console' ||
                w.data == 'Seamless PC & Phone Link'),
      ),
      findsOneWidget,
    );
    expect(find.text('Unified PC & Android\nEcosystem.'), findsOneWidget);

    addTearDown(tester.view.reset);
  });

  testWidgets('Render and Verify Desktop Overview Workbench at 1440x900', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440 * 1.5, 900 * 1.5);
    tester.view.devicePixelRatio = 1.5;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Row(
            children: [
              DesktopSidebar(
                currentTab: DesktopNavTab.overview,
                onTabChanged: (_) {},
                userEmail: 'studio@pclink.dev',
                isServerLive: true,
                isRefreshing: false,
                onRefresh: () {},
                onSignOut: () {},
              ),
              Expanded(
                child: Column(
                  children: [
                    DesktopCommandBar(
                      title: 'Dashboard & Server Hub',
                      subtitle:
                          'Manage local server endpoints, network interfaces, and system health.',
                      serverInfo: dummyServer,
                      isWindows: true,
                    ),
                    Expanded(
                      child: DesktopOverviewTab(
                        details: dummyDetails,
                        currentServerInfo: dummyServer,
                        databaseService: MockDatabaseService(),
                        serverService: ServerService(),
                        onToggleServer: () {},
                        onConnectionStateChanged: (_) {},
                        onDisconnectRequested: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Dashboard & Server Hub'), findsOneWidget);
    expect(find.text('PC LINK SERVICE'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == 'SYSTEM SPECIFICATIONS' ||
                w.data == AppStrings.systemSpecsTitle),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == 'Security & Data Privacy' ||
                w.data == 'Security & Privacy'),
      ),
      findsOneWidget,
    );

    addTearDown(tester.view.reset);
  });

  testWidgets('Render and Verify Mobile Connect Tab at 375x812', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375 * 2, 812 * 2);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: MobileConnectTab(
            details: dummyMobileDetails,
            currentServerInfo: dummyServer,
            databaseService: MockDatabaseService(),
            onToggleServer: () {},
            onConnectionStateChanged: (_) {},
            onDisconnectRequested: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('WINDOWS PC LINK'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == 'SYSTEM SPECIFICATIONS' ||
                w.data == AppStrings.systemSpecsTitle),
      ),
      findsOneWidget,
    );

    addTearDown(tester.view.reset);
  });

  testWidgets('Verify Desktop Sidebar Light Mode Nav Hover and Single Container Layout', (tester) async {
    tester.view.physicalSize = const Size(1280 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: DesktopSidebar(
            currentTab: DesktopNavTab.overview,
            onTabChanged: (_) {},
            userEmail: 'studio@pclink.dev',
            isServerLive: true,
            isRefreshing: false,
            onRefresh: () {},
            onSignOut: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Dashboard & Server'), findsOneWidget);
    expect(find.text('File Transfer Studio'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);

    // Hover over 'File Transfer Studio' tab
    final fileStudioFinder = find.text('File Transfer Studio');
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(fileStudioFinder));
    await tester.pumpAndSettle();

    expect(fileStudioFinder, findsOneWidget);

    // Hover over 'Sync' button
    final syncFinder = find.text('Sync');
    await gesture.moveTo(tester.getCenter(syncFinder));
    await tester.pumpAndSettle();

    expect(syncFinder, findsOneWidget);

    addTearDown(tester.view.reset);
  });
}
