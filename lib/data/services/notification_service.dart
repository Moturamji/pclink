import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../firebase_options.dart';
import 'database_service.dart';

/// Top-level background message handler for FCM when the app is in background or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
  debugPrint('NotificationService: Background FCM message received [${message.messageId}]: ${message.notification?.title}');
}

/// Service managing Firebase Cloud Messaging (FCM), permissions, and local notification display.
class NotificationService {
  static const String channelId = 'pclink_server_channel';
  static const String channelName = 'PCLink Server Alerts';
  static const String channelDescription =
      'Notifications when your Windows PC link is live and ready for connection.';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    channelId,
    channelName,
    description: channelDescription,
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  static bool _isInitialized = false;
  static const int serverLiveNotificationId = 8881;

  /// Initializes notification services, channels, and registers FCM listeners on supported platforms.
  static Future<void> initialize({
    User? user,
    DatabaseService? databaseService,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    if (_isInitialized) {
      if (user != null && databaseService != null) {
        await _syncCurrentToken(user, databaseService);
      }
      return;
    }

    try {
      // 1. Initialize local notifications plugin
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('Notification clicked with payload: ${details.payload}');
        },
      );

      // 2. Create the high importance Android channel & request permissions on Android 13+
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(_androidChannel);
        await androidPlugin.requestNotificationsPermission();
      }

      // 3. Request permissions from user
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('NotificationService: User granted permission: ${settings.authorizationStatus}');

      // 4. Foreground notification presentation options
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 5. Fetch and synchronize FCM Token
      if (user != null && databaseService != null) {
        await _syncCurrentToken(user, databaseService);
      }

      // 6. Listen for token refresh events
      messaging.onTokenRefresh.listen((newToken) {
        debugPrint('NotificationService: FCM Token refreshed: $newToken');
        if (user != null && databaseService != null) {
          databaseService.updateFcmToken(user: user, fcmToken: newToken);
        }
      });

      // 7. Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('NotificationService: Foreground FCM message: ${message.notification?.title}');
        _showLocalNotification(message);
      });

      // 8. Notification tap while app in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('NotificationService: App opened from notification: ${message.data}');
      });

      // 9. Notification tap when app was completely closed / terminated
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('NotificationService: App launched from notification: ${initialMessage.data}');
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('NotificationService initialize error: $e');
    }
  }

  static Future<void> _syncCurrentToken(
    User user,
    DatabaseService databaseService,
  ) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        debugPrint('NotificationService: Current FCM Token: $token');
        await databaseService.updateFcmToken(user: user, fcmToken: token);
      }
    } catch (e) {
      debugPrint('NotificationService: Failed to retrieve FCM token: $e');
    }
  }

  /// Displays a rich, professional heads-up notification alerting that the Windows PC is online.
  static Future<void> showServerLiveNotification({
    required String hostName,
    String? ipAddress,
    String? publicUrl,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final endpointSummary = (publicUrl != null && publicUrl.isNotEmpty)
          ? 'Cloud Tunnel Active ($publicUrl)'
          : (ipAddress != null && ipAddress.isNotEmpty)
              ? 'Local Network ($ipAddress)'
              : 'Secure Connection Ready';

      final bigTextStyleInformation = BigTextStyleInformation(
        '**$hostName** is running PCLink and ready for secure connection.\n\n'
        '• Status: Online & Live\n'
        '• Endpoint: $endpointSummary\n\n'
        'Tap to open PCLink and sync clipboard or transfer files.',
        htmlFormatBigText: false,
        contentTitle: '🖥️ Windows PC is Online & Ready',
        htmlFormatContentTitle: false,
        summaryText: 'PCLink Live Server',
        htmlFormatSummaryText: false,
      );

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF4F46E5),
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 250, 200, 250]),
        styleInformation: bigTextStyleInformation,
        ticker: '$hostName is Live',
        autoCancel: true,
      );

      final platformDetails = NotificationDetails(android: androidDetails);

      await _localNotifications.show(
        id: serverLiveNotificationId,
        title: '🖥️ Windows PC is Online & Ready',
        body: '$hostName is live • $endpointSummary',
        notificationDetails: platformDetails,
        payload: 'home',
      );
    } catch (e) {
      debugPrint('NotificationService showServerLiveNotification error: $e');
    }
  }

  /// Cancels the server live notification (e.g. when PC turns offline)
  static Future<void> cancelServerLiveNotification() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _localNotifications.cancel(id: serverLiveNotificationId);
    } catch (e) {
      debugPrint('NotificationService cancelServerLiveNotification error: $e');
    }
  }

  /// Displays a local heads-up notification for foreground or data-only FCM messages.
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'PCLink Alert';
    final body = notification?.body ?? message.data['body'] ?? 'Windows PC is Live & Ready!';

    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF4F46E5),
      playSound: true,
      enableVibration: true,
    );

    const platformDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: platformDetails,
      payload: message.data['route'] ?? 'home',
    );
  }
}
