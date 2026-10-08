import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service managing Windows System Autostart via `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
/// Enables PCLink to boot silently with Windows in the background with zero UI,
/// ensuring clipboard sync, file sharing, and remote screen mirror are immediately ready.
class WindowsAutostartService {
  static const String _registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _valueName = 'DeskPocket';
  static const String _legacyValueName = 'PCLink';
  static const String _serializeKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize';
  static const String _startupDelayValue = 'StartupDelayInMSec';
  static const String _taskName = 'DeskPocket';
  static const String _legacyTaskName = 'PCLink';

  /// Live reactive notifier for Windows autostart status
  static final ValueNotifier<bool> autostartNotifier = ValueNotifier<bool>(false);

  /// Resolves the actual executable path for DeskPocket.
  static String get _executablePath => Platform.resolvedExecutable;

  /// Checks if DeskPocket is registered to start with Windows directly in HKCU\...\Run
  /// and not marked as disabled in Windows Task Manager / Explorer StartupApproved.
  static Future<bool> isAutostartEnabled() async {
    if (kIsWeb || !Platform.isWindows) return false;

    try {
      var result = await Process.run('reg', [
        'query',
        _registryKey,
        '/v',
        _valueName,
      ]);

      var activeValueName = _valueName;
      if (result.exitCode != 0) {
        // Fallback to check legacy registration
        final legacyResult = await Process.run('reg', [
          'query',
          _registryKey,
          '/v',
          _legacyValueName,
        ]);
        if (legacyResult.exitCode == 0) {
          result = legacyResult;
          activeValueName = _legacyValueName;
        }
      }

      if (result.exitCode == 0) {
        // Now check whether Windows Task Manager / Explorer marked it as disabled
        final approvedResult = await Process.run('reg', [
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
          '/v',
          activeValueName,
        ]);

        if (approvedResult.exitCode == 0) {
          final approvedOut = approvedResult.stdout.toString().toUpperCase();
          if (approvedOut.contains('REG_BINARY')) {
            final tokens = approvedOut.split(RegExp(r'\s+'));
            final idx = tokens.indexOf('REG_BINARY');
            if (idx != -1 && idx + 1 < tokens.length) {
              final hex = tokens[idx + 1];
              // In Windows StartupApproved, 03... or 01... indicates disabled in Task Manager
              if (hex.startsWith('03') || hex.startsWith('01')) {
                autostartNotifier.value = false;
                return false;
              }
            }
          }
        }

        autostartNotifier.value = true;
        return true;
      }
    } catch (e) {
      debugPrint('WindowsAutostartService: Query error: $e');
    }
    autostartNotifier.value = false;
    return false;
  }

  /// Enables or disables PCLink autostart on Windows startup.
  /// When enabled:
  /// 1. Registers: `"<executablePath>" --autostart` in `HKCU\...\Run`
  /// 2. Sets `StartupDelayInMSec = 0` in `Explorer\Serialize` to remove Windows'
  ///    built-in 30-60 second startup throttling delay, ensuring launch within 5-15 seconds.
  /// 3. Attempts to register in Task Scheduler (`ONLOGON`) for instantaneous launch.
  static Future<bool> setAutostartEnabled(bool enabled) async {
    if (kIsWeb || !Platform.isWindows) return false;

    try {
      if (enabled) {
        final exePath = _executablePath;
        // Escape path with quotes and append --autostart flag
        final cmdValue = '"$exePath" --autostart';

        final result = await Process.run('reg', [
          'add',
          _registryKey,
          '/v',
          _valueName,
          '/t',
          'REG_SZ',
          '/d',
          cmdValue,
          '/f',
        ]);

        final success = result.exitCode == 0;
        if (success) {
          // Clean up legacy PCLink registry value and task if present
          try {
            await Process.run('reg', [
              'delete',
              _registryKey,
              '/v',
              _legacyValueName,
              '/f',
            ]);
            await Process.run('schtasks', [
              '/delete',
              '/tn',
              _legacyTaskName,
              '/f',
            ]);
          } catch (_) {}

          // If Windows Task Manager previously recorded a disabled state, remove it
          try {
            await Process.run('reg', [
              'delete',
              r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
              '/v',
              _valueName,
              '/f',
            ]);
          } catch (_) {}

          // Remove Windows Explorer's artificial 30-60 second startup delay:
          // Setting StartupDelayInMSec = 0 tells Explorer to run startup items
          // immediately rather than waiting for system idle.
          try {
            await Process.run('reg', [
              'add',
              _serializeKey,
              '/v',
              _startupDelayValue,
              '/t',
              'REG_DWORD',
              '/d',
              '0',
              '/f',
            ]);
          } catch (e) {
            debugPrint('WindowsAutostartService: Serialize delay config error: $e');
          }

          // Register in Windows Task Scheduler (fires immediately upon logon)
          try {
            await Process.run('schtasks', [
              '/create',
              '/tn',
              _taskName,
              '/tr',
              cmdValue,
              '/sc',
              'onlogon',
              '/f',
            ]);
          } catch (_) {}

          autostartNotifier.value = true;
        }
        debugPrint(
          'WindowsAutostartService: Enable autostart result (code ${result.exitCode}): $cmdValue',
        );
        return success;
      } else {
        final result = await Process.run('reg', [
          'delete',
          _registryKey,
          '/v',
          _valueName,
          '/f',
        ]);
        try {
          await Process.run('reg', [
            'delete',
            _registryKey,
            '/v',
            _legacyValueName,
            '/f',
          ]);
        } catch (_) {}

        try {
          await Process.run('reg', [
            'delete',
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            '/v',
            _valueName,
            '/f',
          ]);
          await Process.run('reg', [
            'delete',
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
            '/v',
            _legacyValueName,
            '/f',
          ]);
        } catch (_) {}

        // Remove Task Scheduler task if registered
        try {
          await Process.run('schtasks', [
            '/delete',
            '/tn',
            _taskName,
            '/f',
          ]);
        } catch (_) {}
        try {
          await Process.run('schtasks', [
            '/delete',
            '/tn',
            _legacyTaskName,
            '/f',
          ]);
        } catch (_) {}

        final success = result.exitCode == 0;
        if (success) {
          autostartNotifier.value = false;
        }
        debugPrint(
          'WindowsAutostartService: Disable autostart result (code ${result.exitCode})',
        );
        return success;
      }
    } catch (e) {
      debugPrint('WindowsAutostartService: Set autostart error: $e');
      return false;
    }
  }
}
