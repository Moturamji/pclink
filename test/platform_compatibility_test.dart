import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/data/models/device_details.dart';
import 'package:pclink/data/services/platform_helpers.dart';
import 'package:pclink/data/services/system_power_service.dart';
import 'dart:io';

void main() {
  group('Platform Helpers Unit Tests', () {
    test('platformKey reflects current platform or fallback', () {
      final key = platformKey;
      if (Platform.isWindows) {
        expect(key, equals('windows'));
        expect(isDesktopHost, isTrue);
        expect(isMobileClient, isFalse);
      } else if (Platform.isMacOS) {
        expect(key, equals('macos'));
        expect(isDesktopHost, isTrue);
        expect(isMobileClient, isFalse);
      } else if (Platform.isAndroid) {
        expect(key, equals('android'));
        expect(isDesktopHost, isFalse);
        expect(isMobileClient, isTrue);
      } else if (Platform.isIOS) {
        expect(key, equals('ios'));
        expect(isDesktopHost, isFalse);
        expect(isMobileClient, isTrue);
      }
    });
  });

  group('DeviceDetails Platform Compatibility Tests', () {
    test('Windows device flags work correctly', () {
      const details = DeviceDetails(
        platform: 'Windows',
        deviceId: 'win-123',
        deviceName: 'My-PC',
        osVersion: 'Windows 11',
        primaryIp: '192.168.1.100',
        interfaces: [],
        additionalDetails: {},
      );

      expect(details.isWindows, isTrue);
      expect(details.isMacOS, isFalse);
      expect(details.isAndroid, isFalse);
      expect(details.isIOS, isFalse);
      expect(details.isDesktop, isTrue);
      expect(details.isMobile, isFalse);
      expect(details.isConnected, isTrue);
    });

    test('macOS device flags work correctly', () {
      const details = DeviceDetails(
        platform: 'macOS',
        deviceId: 'mac-123',
        deviceName: 'My-MacBook',
        osVersion: 'macOS 14.4',
        primaryIp: '192.168.1.101',
        interfaces: [],
        additionalDetails: {},
      );

      expect(details.isWindows, isFalse);
      expect(details.isMacOS, isTrue);
      expect(details.isAndroid, isFalse);
      expect(details.isIOS, isFalse);
      expect(details.isDesktop, isTrue);
      expect(details.isMobile, isFalse);
      expect(details.isConnected, isTrue);
    });

    test('Android device flags work correctly', () {
      const details = DeviceDetails(
        platform: 'Android',
        deviceId: 'and-123',
        deviceName: 'Pixel 8',
        osVersion: 'Android 14',
        primaryIp: '192.168.1.102',
        interfaces: [],
        additionalDetails: {},
      );

      expect(details.isWindows, isFalse);
      expect(details.isMacOS, isFalse);
      expect(details.isAndroid, isTrue);
      expect(details.isIOS, isFalse);
      expect(details.isDesktop, isFalse);
      expect(details.isMobile, isTrue);
      expect(details.isConnected, isTrue);
    });

    test('iOS device flags work correctly', () {
      const details = DeviceDetails(
        platform: 'iOS',
        deviceId: 'ios-123',
        deviceName: 'iPhone 15',
        osVersion: 'iOS 17.4',
        primaryIp: '192.168.1.103',
        interfaces: [],
        additionalDetails: {},
      );

      expect(details.isWindows, isFalse);
      expect(details.isMacOS, isFalse);
      expect(details.isAndroid, isFalse);
      expect(details.isIOS, isTrue);
      expect(details.isDesktop, isFalse);
      expect(details.isMobile, isTrue);
      expect(details.isConnected, isTrue);
    });

    test('Offline or loopback IP correctly marks isConnected false', () {
      const detailsDisconnected = DeviceDetails(
        platform: 'Windows',
        deviceId: 'win-123',
        deviceName: 'My-PC',
        osVersion: 'Windows 11',
        primaryIp: 'Not Connected',
        interfaces: [],
        additionalDetails: {},
      );
      expect(detailsDisconnected.isConnected, isFalse);

      const detailsLoopback = DeviceDetails(
        platform: 'macOS',
        deviceId: 'mac-123',
        deviceName: 'My-MacBook',
        osVersion: 'macOS 14.4',
        primaryIp: '127.0.0.1',
        interfaces: [],
        additionalDetails: {},
      );
      expect(detailsLoopback.isConnected, isFalse);
    });
  });

  group('SystemPowerService Platform Unit Tests', () {
    final originalRunner = SystemPowerService.processRunner;

    tearDown(() {
      SystemPowerService.processRunner = originalRunner;
    });

    test('macOS sleep executes pmset sleepnow', () async {
      String? executedExe;
      List<String>? executedArgs;

      SystemPowerService.processRunner = (exe, args) async {
        executedExe = exe;
        executedArgs = args;
        return ProcessResult(1234, 0, '', '');
      };

      final result = await SystemPowerService.executeAction(
        action: 'sleep',
        isMacOSOverride: true,
        isWindowsOverride: false,
      );

      expect(result.success, isTrue);
      expect(executedExe, equals('pmset'));
      expect(executedArgs, equals(['sleepnow']));
    });

    test('macOS shutdown executes osascript System Events shut down', () async {
      String? executedExe;
      List<String>? executedArgs;

      SystemPowerService.processRunner = (exe, args) async {
        executedExe = exe;
        executedArgs = args;
        return ProcessResult(1234, 0, '', '');
      };

      final result = await SystemPowerService.executeAction(
        action: 'shutdown',
        isMacOSOverride: true,
        isWindowsOverride: false,
      );

      expect(result.success, isTrue);
      expect(executedExe, equals('osascript'));
      expect(executedArgs, contains('tell application "System Events" to shut down'));
    });

    test('macOS restart executes osascript System Events restart', () async {
      String? executedExe;
      List<String>? executedArgs;

      SystemPowerService.processRunner = (exe, args) async {
        executedExe = exe;
        executedArgs = args;
        return ProcessResult(1234, 0, '', '');
      };

      final result = await SystemPowerService.executeAction(
        action: 'restart',
        isMacOSOverride: true,
        isWindowsOverride: false,
      );

      expect(result.success, isTrue);
      expect(executedExe, equals('osascript'));
      expect(executedArgs, contains('tell application "System Events" to restart'));
    });

    test('macOS lock executes pmset displaysleepnow and keystroke lock', () async {
      final calls = <Map<String, dynamic>>[];

      SystemPowerService.processRunner = (exe, args) async {
        calls.add({'exe': exe, 'args': args});
        return ProcessResult(1234, 0, '', '');
      };

      final result = await SystemPowerService.executeAction(
        action: 'lock',
        isMacOSOverride: true,
        isWindowsOverride: false,
      );

      expect(result.success, isTrue);
      expect(calls.length, equals(2));
      expect(calls[0]['exe'], equals('pmset'));
      expect(calls[0]['args'], equals(['displaysleepnow']));
      expect(calls[1]['exe'], equals('osascript'));
    });

    test('Windows shutdown executes shutdown with correct arguments', () async {
      String? executedExe;
      List<String>? executedArgs;

      SystemPowerService.processRunner = (exe, args) async {
        executedExe = exe;
        executedArgs = args;
        return ProcessResult(1234, 0, '', '');
      };

      final result = await SystemPowerService.executeAction(
        action: 'shutdown',
        timeoutSeconds: 30,
        isMacOSOverride: false,
        isWindowsOverride: true,
      );

      expect(result.success, isTrue);
      expect(executedExe, equals('shutdown'));
      expect(executedArgs, contains('/s'));
      expect(executedArgs, contains('/f'));
      expect(executedArgs, contains('/t'));
      expect(executedArgs, contains('30'));
    });

    test('Executing power command on non-desktop host returns error', () async {
      final result = await SystemPowerService.executeAction(
        action: 'shutdown',
        isMacOSOverride: false,
        isWindowsOverride: false,
      );

      expect(result.success, isFalse);
      expect(result.message, contains('only supported on Windows and macOS'));
    });
  });
}
