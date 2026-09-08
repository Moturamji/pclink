import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../../data/services/database_service.dart';
import '../models/clipboard_item.dart';

/// Manages continuous background system clipboard monitoring and bidirectional synchronization.
class ClipboardService with WidgetsBindingObserver {
  Timer? _clipboardPollTimer;
  StreamSubscription<List<ClipboardItem>>? _remoteSub;

  User? _currentUser;
  String? _currentDeviceName;
  String? _currentPlatformName;
  DatabaseService? _currentDatabaseService;

  String? _lastLocalText;
  String? _lastReceivedRemoteText;
  bool isAutoSyncEnabled = true;

  bool get isListening => _clipboardPollTimer != null;

  /// Initializes Android Foreground Task configurations.
  static Future<void> initForegroundTask() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'pclink_foreground_sync',
          channelName: 'PCLink Background Sync',
          channelDescription: 'Maintains live background connection and real-time clipboard sync with PC',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(1000),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    } catch (e) {
      debugPrint('ClipboardService initForegroundTask error: $e');
    }
  }

  /// Starts background clipboard polling, remote stream listening, and foreground service.
  void startListening({
    required User user,
    required String deviceName,
    required bool isWindows,
    required DatabaseService databaseService,
    Function(ClipboardItem)? onNewRemoteClipReceived,
  }) {
    if (_clipboardPollTimer != null) return;

    _currentUser = user;
    _currentDeviceName = deviceName;
    _currentPlatformName = isWindows ? 'windows' : 'android';
    _currentDatabaseService = databaseService;

    WidgetsBinding.instance.addObserver(this);

    // 1. High-frequency local clipboard poll (750ms)
    _clipboardPollTimer = Timer.periodic(const Duration(milliseconds: 750), (_) async {
      await _checkLocalClipboard();
    });

    // 2. Start Android Foreground Service so Android does NOT freeze the app in background
    if (!kIsWeb && Platform.isAndroid) {
      _startAndroidForegroundService();
    }

    // 3. Listen to incoming remote clips
    _remoteSub = databaseService.watchClipboardItems(user).listen((items) async {
      if (items.isEmpty) return;
      final latest = items.first;

      // Only process clips from the other platform
      if (latest.sourcePlatform != _currentPlatformName && latest.text != _lastReceivedRemoteText) {
        _lastReceivedRemoteText = latest.text;
        onNewRemoteClipReceived?.call(latest);

        if (isAutoSyncEnabled && latest.text.isNotEmpty) {
          try {
            await Clipboard.setData(ClipboardData(text: latest.text));
            debugPrint('ClipboardService: Auto-synced remote text to system clipboard');
          } catch (e) {
            debugPrint('ClipboardService auto-sync error: $e');
          }
        }
      }
    });

    debugPrint('ClipboardService: Started clipboard listener for $_currentPlatformName ($deviceName)');
  }

  Future<void> _startAndroidForegroundService() async {
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'PCLink Sync Active',
          notificationText: 'Live background sync with Windows PC',
        );
      }
    } catch (e) {
      debugPrint('ClipboardService _startAndroidForegroundService error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Whenever app is paused, hidden, or resumed, check clipboard immediately
    _checkLocalClipboard();
  }

  Future<void> _checkLocalClipboard() async {
    if (_currentUser == null || _currentDatabaseService == null) return;

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final currentText = data?.text;

      if (currentText == null || currentText.trim().isEmpty) return;

      // Ignore if text is unchanged or matches text we just received from remote
      if (currentText == _lastLocalText || currentText == _lastReceivedRemoteText) {
        return;
      }

      _lastLocalText = currentText;

      final item = ClipboardItem(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        text: currentText,
        sourcePlatform: _currentPlatformName ?? 'unknown',
        sourceDeviceName: _currentDeviceName ?? 'Device',
        timestamp: DateTime.now(),
      );

      await _currentDatabaseService!.pushClipboardItem(
        user: _currentUser!,
        item: item,
      );

      debugPrint('ClipboardService: Uploaded new local clip to RTDB (${item.charCount} chars)');
    } catch (e) {
      debugPrint('ClipboardService check error: $e');
    }
  }

  /// Stops clipboard listener.
  void stopListening() {
    WidgetsBinding.instance.removeObserver(this);
    _clipboardPollTimer?.cancel();
    _clipboardPollTimer = null;
    _remoteSub?.cancel();
    _remoteSub = null;

    if (!kIsWeb && Platform.isAndroid) {
      FlutterForegroundTask.stopService();
    }
  }

  void dispose() {
    stopListening();
  }
}
