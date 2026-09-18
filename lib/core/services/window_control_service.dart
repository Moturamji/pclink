import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service interfacing with native Win32 window control and tray interactions.
class WindowControlService {
  static const MethodChannel _channel = MethodChannel('pclink/window_control');

  /// Checks if the app was started in hidden mode (via `--autostart` or `--hidden`).
  static Future<bool> isStartedHidden() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isStartedHidden');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Brings the native Windows window to the foreground.
  static Future<void> showWindow() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await _channel.invokeMethod('showWindow');
    } catch (e) {
      debugPrint('WindowControlService showWindow error: $e');
    }
  }

  /// Hides the native Windows window to the system tray.
  static Future<void> hideWindow() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await _channel.invokeMethod('hideWindow');
    } catch (e) {
      debugPrint('WindowControlService hideWindow error: $e');
    }
  }
}
