import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service managing Windows System Autostart via `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
/// Enables PCLink to boot silently with Windows in the background with zero UI,
/// ensuring clipboard sync, file sharing, and remote screen mirror are immediately ready.
class WindowsAutostartService {
  static const String _registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _valueName = 'PCLink';

  /// Resolves the actual executable path for PCLink.
  static String get _executablePath => Platform.resolvedExecutable;

  /// Checks if PCLink is registered to start with Windows.
  static Future<bool> isAutostartEnabled() async {
    if (kIsWeb || !Platform.isWindows) return false;

    try {
      final result = await Process.run('reg', [
        'query',
        _registryKey,
        '/v',
        _valueName,
      ]);

      if (result.exitCode == 0) {
        final stdout = result.stdout.toString().toLowerCase();
        return stdout.contains('pclink') && stdout.contains('--autostart');
      }
    } catch (e) {
      debugPrint('WindowsAutostartService: Query error: $e');
    }
    return false;
  }

  /// Enables or disables PCLink autostart on Windows startup.
  /// When enabled, registers: `"<executablePath>" --autostart`
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

        final success = result.exitCode == 0;
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
