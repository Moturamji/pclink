import 'dart:io';
import 'package:flutter/foundation.dart';

/// True if running on a desktop operating system configured as host (Windows or macOS).
bool get isDesktopHost => !kIsWeb && (Platform.isWindows || Platform.isMacOS);

/// True if running on a mobile operating system acting as client (Android or iOS).
bool get isMobileClient => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Normalized platform identifier key matching Firebase, server routing, and session models.
String get platformKey {
  if (kIsWeb) return 'web';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return 'unknown';
}
