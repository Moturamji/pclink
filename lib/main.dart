import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'core/theme/theme_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/screen_share_service.dart';
import 'data/services/share_target_service.dart';
import 'data/services/windows_autostart_service.dart';
import 'features/clipboard/services/clipboard_service.dart';
import 'firebase_options.dart';

/// Application bootstrap entry point with command line argument support.
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safety handler for platform crashes
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught platform error: $error\n$stack');
    return true; // prevent unhandled crash
  };

  // Parse any file paths passed via CLI / Explorer SendTo / Context Menu
  if (args.isNotEmpty) {
    final validFiles = args.where((arg) {
      if (arg.startsWith('-')) return false;
      return File(arg).existsSync() || Directory(arg).existsSync();
    }).toList();
    if (validFiles.isNotEmpty) {
      ShareTargetService.setInitialFiles(validFiles);
    }
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize Share Target Service for system share sheets (Android) and Explorer (Windows)
    await ShareTargetService().initialize();

    // Register FCM Background Handler, early Notification Channels & Foreground Clipboard Task on Android
    if (!kIsWeb && Platform.isAndroid) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await NotificationService.initializeEarly();
      await ClipboardService.initForegroundTask();
    }

    // Initialize live Windows system features directly from registry & persistence
    if (!kIsWeb && Platform.isWindows) {
      await WindowsAutostartService.isAutostartEnabled();
      await ScreenShareService.isConsentGranted();
    }

    // Initialize Theme preference
    await ThemeService().init();
  } catch (e, stack) {
    debugPrint('Initialization warning: $e\n$stack');
  }

  runApp(const DeskPocketApp());
}
