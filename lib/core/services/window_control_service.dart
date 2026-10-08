import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service interfacing with native desktop window control and tray interactions.
class WindowControlService {
  static const MethodChannel _channel = MethodChannel('pclink/window_control');
  static const MethodChannel _macChannel =
      MethodChannel('com.deskpocket.pclink/window_control');

  static MethodChannel get _activeChannel =>
      Platform.isMacOS ? _macChannel : _channel;

  /// Checks if the app was started in hidden mode (via `--autostart` or `--hidden`).
  static Future<bool> isStartedHidden() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS)) return false;
    try {
      final result = await _activeChannel.invokeMethod<bool>('isStartedHidden');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Brings the native desktop window to the foreground.
  static Future<void> showWindow() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS)) return;
    try {
      await _activeChannel.invokeMethod('showWindow');
    } catch (e) {
      debugPrint('WindowControlService showWindow error: $e');
    }
  }

  /// Hides the native desktop window to the system tray / dock.
  static Future<void> hideWindow() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS)) return;
    try {
      await _activeChannel.invokeMethod('hideWindow');
    } catch (e) {
      debugPrint('WindowControlService hideWindow error: $e');
    }
  }
}
