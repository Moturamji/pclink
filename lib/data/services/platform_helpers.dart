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

/// Firebase RTDB device/session slot for this host.
///
/// The data model has exactly two slots: one PC (`windows`) and one phone
/// (`android`). Every desktop host (Windows *or* macOS) occupies the PC slot
/// and every mobile client (Android *or* iOS) occupies the phone slot.
///
/// This MUST be the single source of truth for session registration,
/// session watching, heartbeats and device sync. Mixing keys (e.g. `macos`
/// in one place and `android` in another) causes a fresh login to be
/// evicted immediately as "another device logged in".
String get sessionSlotKey => isDesktopHost ? 'windows' : 'android';

/// Same as [sessionSlotKey] but derived from a reported platform name.
String sessionSlotKeyFor({required bool isDesktop}) =>
    isDesktop ? 'windows' : 'android';

/// True while running under `flutter test` (the test runner sets FLUTTER_TEST).
bool get isFlutterTest =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

Directory? _testSandbox;

/// Per-process scratch directory used instead of real user folders during
/// tests. Without this, running the suite on a Mac/PC overwrites the real
/// app's login (auth_session.json) and dumps test files into
/// ~/Downloads/DeskPocket, which the live app then serves to the phone.
Directory get testSandboxDir {
  final existing = _testSandbox;
  if (existing != null) return existing;
  final dir = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}pclink_test_$pid',
  );
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return _testSandbox = dir;
}
