import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'data/services/notification_service.dart';
import 'firebase_options.dart';

/// Application bootstrap entry point.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safety handler for platform crashes
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught platform error: $error\n$stack');
    return true; // prevent unhandled crash
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Register FCM Background Handler on Android
    if (!kIsWeb && Platform.isAndroid) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
  } catch (e, stack) {
    debugPrint('Firebase initialization warning: $e\n$stack');
  }

  runApp(const PCLinkApp());
}
