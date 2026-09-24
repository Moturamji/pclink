import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service managing Windows Shell integrations:
/// 1. "Send To" shortcut in `%APPDATA%\Microsoft\Windows\SendTo`
///    (Allows Right-click -> Send to -> DeskPocket on any file or folder).
/// 2. Explorer Context Menu in `HKCU\Software\Classes\*\shell\DeskPocket`
///    (Allows Right-click -> "Send to Phone with DeskPocket" directly on any file/folder).
///
/// Both registrations operate exclusively in current user scope (`HKCU` and `%APPDATA%`),
/// requiring zero Administrator/UAC elevation.
class WindowsShellService {
  static const String _fileRegKey = r'HKCU\Software\Classes\*\shell\DeskPocket';
  static const String _dirRegKey =
      r'HKCU\Software\Classes\Directory\shell\DeskPocket';
  static const String _menuTitle = 'Send to Phone with DeskPocket';

  static String get _sendToShortcutPath {
    final appData = Platform.environment['APPDATA'] ?? '';
    return '$appData\\Microsoft\\Windows\\SendTo\\DeskPocket.lnk';
  }

  /// Checks if the SendTo shortcut is in place.
  static Future<bool> isSendToRegistered() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final file = File(_sendToShortcutPath);
      return await file.exists();
    } catch (e) {
      debugPrint('WindowsShellService: isSendToRegistered error: $e');
      return false;
    }
  }

  /// Registers or refreshes the "DeskPocket.lnk" shortcut in the Windows SendTo folder.
  static Future<bool> registerSendToShortcut() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final exePath = Platform.resolvedExecutable;
      final shortcutPath = _sendToShortcutPath;
      final sendToDir = Directory(
        '${Platform.environment['APPDATA']}\\Microsoft\\Windows\\SendTo',
      );

      if (!await sendToDir.exists()) {
        await sendToDir.create(recursive: true);
      }

      final psScript =
          '\$ws = New-Object -ComObject WScript.Shell; '
          '\$s = \$ws.CreateShortcut(\'$shortcutPath\'); '
          '\$s.TargetPath = \'$exePath\'; '
          '\$s.IconLocation = \'$exePath,0\'; '
          '\$s.Description = \'Send to Phone with DeskPocket\'; '
          '\$s.Save();';

      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        psScript,
      ]);

      if (result.exitCode == 0) {
        debugPrint('WindowsShellService: Registered SendTo shortcut at $shortcutPath');
        return true;
      } else {
        debugPrint(
          'WindowsShellService: SendTo registration failed: ${result.stderr}',
        );
      }
    } catch (e) {
      debugPrint('WindowsShellService: registerSendToShortcut error: $e');
    }
    return false;
  }

  /// Checks if the right-click Explorer context menu is registered in HKCU.
  static Future<bool> isContextMenuRegistered() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', ['query', _fileRegKey]);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('WindowsShellService: isContextMenuRegistered error: $e');
      return false;
    }
  }

  /// Registers the right-click "Send to Phone with DeskPocket" context menu
  /// for both individual files and directories in Windows Explorer.
  static Future<bool> registerContextMenu() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final exePath = Platform.resolvedExecutable;

      // 1. Files registration: HKCU\Software\Classes\*\shell\DeskPocket
      await Process.run('reg', [
        'add',
        _fileRegKey,
        '/ve',
        '/d',
        _menuTitle,
        '/f',
      ]);
      await Process.run('reg', [
        'add',
        _fileRegKey,
        '/v',
        'Icon',
        '/d',
        exePath,
        '/f',
      ]);
      await Process.run('reg', [
        'add',
        '$_fileRegKey\\command',
        '/ve',
        '/d',
        '"$exePath" "%1"',
        '/f',
      ]);

      // 2. Directories registration: HKCU\Software\Classes\Directory\shell\DeskPocket
      await Process.run('reg', [
        'add',
        _dirRegKey,
        '/ve',
        '/d',
        _menuTitle,
        '/f',
      ]);
      await Process.run('reg', [
        'add',
        _dirRegKey,
        '/v',
        'Icon',
        '/d',
        exePath,
        '/f',
      ]);
      await Process.run('reg', [
        'add',
        '$_dirRegKey\\command',
        '/ve',
        '/d',
        '"$exePath" "%1"',
        '/f',
      ]);

      debugPrint('WindowsShellService: Explorer context menu registered successfully.');
      return true;
    } catch (e) {
      debugPrint('WindowsShellService: registerContextMenu error: $e');
      return false;
    }
  }

  /// Removes the context menu keys from the registry.
  static Future<bool> unregisterContextMenu() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      await Process.run('reg', ['delete', _fileRegKey, '/f']);
      await Process.run('reg', ['delete', _dirRegKey, '/f']);
      return true;
    } catch (e) {
      debugPrint('WindowsShellService: unregisterContextMenu error: $e');
      return false;
    }
  }

  /// Automatically ensures all Windows Shell integrations are active.
  static Future<void> registerAll() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await registerSendToShortcut();
      await registerContextMenu();
    } catch (e) {
      debugPrint('WindowsShellService: registerAll error: $e');
    }
  }
}
