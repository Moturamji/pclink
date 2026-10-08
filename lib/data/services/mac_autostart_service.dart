import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service managing macOS autostart via SMAppService (native) with
/// LaunchAgent fallback (~/Library/LaunchAgents/com.deskpocket.pclink.plist).
class MacAutostartService {
  static const MethodChannel _channel =
      MethodChannel('com.deskpocket.pclink/mac_autostart');
  static const String _plistLabel = 'com.deskpocket.pclink';

  /// Live reactive notifier for macOS autostart status
  static final ValueNotifier<bool> autostartNotifier =
      ValueNotifier<bool>(false);

  static File get _launchAgentPlist {
    final home = Platform.environment['HOME'] ?? '';
    return File('$home/Library/LaunchAgents/$_plistLabel.plist');
  }

  /// Checks if autostart is enabled via native channel or LaunchAgent plist.
  static Future<bool> isAutostartEnabled() async {
    if (kIsWeb || !Platform.isMacOS) return false;

    try {
      final nativeResult =
          await _channel.invokeMethod<bool>('isAutostartEnabled');
      if (nativeResult != null) {
        autostartNotifier.value = nativeResult;
        return nativeResult;
      }
    } catch (_) {}

    // Fallback: check LaunchAgent plist
    try {
      final exists = await _launchAgentPlist.exists();
      autostartNotifier.value = exists;
      return exists;
    } catch (e) {
      debugPrint('MacAutostartService: Error checking LaunchAgent: $e');
    }

    autostartNotifier.value = false;
    return false;
  }

  /// Enables or disables autostart on macOS.
  static Future<bool> setAutostartEnabled(bool enabled) async {
    if (kIsWeb || !Platform.isMacOS) return false;

    // Try native SMAppService first
    try {
      final success = await _channel
          .invokeMethod<bool>('setAutostartEnabled', {'enabled': enabled});
      if (success == true) {
        autostartNotifier.value = enabled;
        return true;
      }
    } catch (_) {}

    // Fallback: create or remove ~/Library/LaunchAgents/com.deskpocket.pclink.plist
    try {
      final plistFile = _launchAgentPlist;
      if (enabled) {
        final exePath = Platform.resolvedExecutable;
        final parentDir = plistFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }

        final plistContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$_plistLabel</string>
    <key>ProgramArguments</key>
    <array>
        <string>$exePath</string>
        <string>--autostart</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
''';
        await plistFile.writeAsString(plistContent, flush: true);
        autostartNotifier.value = true;
        return true;
      } else {
        if (await plistFile.exists()) {
          await plistFile.delete();
        }
        autostartNotifier.value = false;
        return true;
      }
    } catch (e) {
      debugPrint('MacAutostartService: Fallback error: $e');
      return false;
    }
  }
}
