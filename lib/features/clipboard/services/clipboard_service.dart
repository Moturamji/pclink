import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/server_constants.dart';
import '../../../data/services/server_service.dart';
import '../models/clipboard_item.dart';

@pragma('vm:entry-point')
void startForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(PclinkTaskHandler());
}

class PclinkTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    FlutterForegroundTask.sendDataToMain('sync_clipboard_now');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.sendDataToMain('sync_clipboard_now');
  }
}

/// Manages 100% direct, peer-to-peer clipboard synchronization through the local Windows PC server.
class ClipboardService with WidgetsBindingObserver {
  final http.Client _client = http.Client();
  final List<ClipboardItem> _history = [];
  final StreamController<List<ClipboardItem>> _historyController =
      StreamController<List<ClipboardItem>>.broadcast();

  Timer? _clipboardPollTimer;
  Timer? _remoteFetchTimer;

  ServerService? _serverService;
  String? Function()? _getTargetServerUrl;
  String? _currentDeviceName;
  String? _currentPlatformName;
  Function(ClipboardItem)? _onNewRemoteClipReceived;

  String? _lastLocalText;
  String? _lastReceivedRemoteText;
  bool isAutoSyncEnabled = true;

  bool get isListening => _clipboardPollTimer != null;
  Stream<List<ClipboardItem>> get clipboardHistoryStream => _historyController.stream;
  List<ClipboardItem> get currentHistory => List.unmodifiable(_history);

  /// Initializes Android Foreground Task configurations.
  static Future<void> initForegroundTask() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'pclink_foreground_sync',
          channelName: 'PCLink Background Sync',
          channelDescription: 'Maintains live background connection and direct clipboard route with PC',
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

  /// Starts direct local server clipboard synchronization.
  void startListening({
    required String deviceName,
    required bool isWindows,
    ServerService? serverService,
    String? Function()? getTargetServerUrl,
    Function(ClipboardItem)? onNewRemoteClipReceived,
  }) {
    if (_clipboardPollTimer != null) return;

    _currentDeviceName = deviceName;
    _currentPlatformName = isWindows ? 'windows' : 'android';
    _serverService = serverService;
    _getTargetServerUrl = getTargetServerUrl;
    _onNewRemoteClipReceived = onNewRemoteClipReceived;

    WidgetsBinding.instance.addObserver(this);

    // 1. High-frequency local clipboard poll (400ms)
    _clipboardPollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      await _checkLocalClipboard();
    });

    if (isWindows && _serverService != null) {
      // Windows: Server receives direct clips from Android via HTTP POST /api/clipboard
      _serverService!.onClipboardReceived = (item) {
        _handleRemoteClipReceived(item);
      };
      _history.addAll(_serverService!.clipboardHistory);
      _historyController.add(List.from(_history));
    } else {
      // Android: Fast poll of latest clip directly from Windows server route (800ms)
      _remoteFetchTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
        await _fetchLatestRemoteClipFromWindowsServer();
      });

      // Start Android Foreground Service with 1-tap notification action
      if (!kIsWeb && Platform.isAndroid) {
        FlutterForegroundTask.addTaskDataCallback(_onForegroundDataReceived);
        _startAndroidForegroundService();
      }

      refreshHistory();
    }

    debugPrint('ClipboardService: Started 100% direct server clipboard sync for $_currentPlatformName ($deviceName)');
  }

  void _onForegroundDataReceived(dynamic data) {
    if (data == 'sync_clipboard_now') {
      _checkLocalClipboard();
    }
  }

  Future<void> _startAndroidForegroundService() async {
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'PCLink Live Sync Active',
          notificationText: 'Tap "Send to PC" to instantly transfer clipboard',
          notificationButtons: [
            const NotificationButton(id: 'sync_now', text: '📋 Send to PC'),
          ],
          callback: startForegroundTaskCallback,
        );
      }
    } catch (e) {
      debugPrint('ClipboardService _startAndroidForegroundService error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Whenever app focus changes or resumes, check clipboard immediately
    _checkLocalClipboard();
    if (_currentPlatformName == 'android') {
      _fetchLatestRemoteClipFromWindowsServer();
    }
  }

  /// Checks local system clipboard and pushes changes directly to the local server route.
  Future<void> _checkLocalClipboard() async {
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

      _addClipToLocalHistory(item);

      if (_currentPlatformName == 'windows') {
        // Windows: Store in local server memory history
        _serverService?.addLocalClipboardItem(item);
      } else {
        // Android: Send directly to Windows server via HTTP POST /api/clipboard
        await _postClipToWindowsServer(item);
      }

      debugPrint('ClipboardService: Transferred local clip directly (${item.charCount} chars)');
    } catch (e) {
      debugPrint('ClipboardService check error: $e');
    }
  }

  /// Android -> Windows: Directly sends copied text to Windows server.
  Future<void> _postClipToWindowsServer(ClipboardItem item) async {
    final serverUrl = _getTargetServerUrl?.call();
    if (serverUrl == null || serverUrl.isEmpty) return;

    try {
      final sanitizedUrl = serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl;
      final uri = Uri.parse('$sanitizedUrl${ServerConstants.clipboardEndpoint}');

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(item.toMap()),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        debugPrint('ClipboardService: Direct clip sent to Windows server (${item.charCount} chars)');
      }
    } catch (e) {
      debugPrint('ClipboardService _postClipToWindowsServer error: $e');
    }
  }

  /// Android <- Windows: Fetches latest copied clip directly from Windows server.
  Future<void> _fetchLatestRemoteClipFromWindowsServer() async {
    final serverUrl = _getTargetServerUrl?.call();
    if (serverUrl == null || serverUrl.isEmpty) return;

    try {
      final sanitizedUrl = serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl;
      final uri = Uri.parse('$sanitizedUrl${ServerConstants.clipboardLatestEndpoint}');

      final response = await _client.get(uri).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200 && response.body.isNotEmpty && response.body != 'null') {
        final dynamic data = jsonDecode(response.body);
        if (data is Map) {
          final item = ClipboardItem.fromMap(data);
          if (item.sourcePlatform != _currentPlatformName && item.text != _lastReceivedRemoteText) {
            _handleRemoteClipReceived(item);
          }
        }
      }
    } catch (_) {
      // Server might be temporarily unreachable; handled gracefully
    }
  }

  /// Handles incoming remote clip from the peer device.
  Future<void> _handleRemoteClipReceived(ClipboardItem item) async {
    if (item.text == _lastReceivedRemoteText || item.text == _lastLocalText) return;

    _lastReceivedRemoteText = item.text;
    _addClipToLocalHistory(item);
    _onNewRemoteClipReceived?.call(item);

    if (isAutoSyncEnabled && item.text.isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: item.text));
        debugPrint('ClipboardService: Auto-synced remote text to system clipboard');
      } catch (e) {
        debugPrint('ClipboardService auto-sync error: $e');
      }
    }
  }

  void _addClipToLocalHistory(ClipboardItem item) {
    _history.removeWhere((c) => c.id == item.id || c.text == item.text);
    _history.insert(0, item);
    if (_history.length > 50) {
      _history.removeLast();
    }
    _historyController.add(List.from(_history));
  }

  /// Refreshes full clipboard history directly from the Windows server route.
  Future<void> refreshHistory() async {
    if (_currentPlatformName == 'windows') {
      if (_serverService != null) {
        _history.clear();
        _history.addAll(_serverService!.clipboardHistory);
        _historyController.add(List.from(_history));
      }
      return;
    }

    final serverUrl = _getTargetServerUrl?.call();
    if (serverUrl == null || serverUrl.isEmpty) return;

    try {
      final sanitizedUrl = serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl;
      final uri = Uri.parse('$sanitizedUrl${ServerConstants.clipboardEndpoint}');

      final response = await _client.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200 && response.body.isNotEmpty && response.body != 'null') {
        final dynamic listData = jsonDecode(response.body);
        if (listData is List) {
          _history.clear();
          for (final raw in listData) {
            if (raw is Map) {
              _history.add(ClipboardItem.fromMap(raw));
            }
          }
          _historyController.add(List.from(_history));
        }
      }
    } catch (e) {
      debugPrint('ClipboardService refreshHistory error: $e');
    }
  }

  /// Clears clipboard history directly across the local server route.
  Future<void> clearHistory() async {
    _history.clear();
    _historyController.add([]);

    if (_currentPlatformName == 'windows') {
      _serverService?.clearClipboardHistory();
    } else {
      final serverUrl = _getTargetServerUrl?.call();
      if (serverUrl != null && serverUrl.isNotEmpty) {
        try {
          final sanitizedUrl = serverUrl.endsWith('/')
              ? serverUrl.substring(0, serverUrl.length - 1)
              : serverUrl;
          final uri = Uri.parse('$sanitizedUrl${ServerConstants.clipboardEndpoint}');
          await _client.delete(uri).timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
    }
  }

  /// Manually triggers a clipboard read and push.
  Future<void> triggerManualSync() async {
    await _checkLocalClipboard();
  }

  /// Stops clipboard listener and background tasks.
  void stopListening() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && Platform.isAndroid) {
      FlutterForegroundTask.removeTaskDataCallback(_onForegroundDataReceived);
      FlutterForegroundTask.stopService();
    }
    _clipboardPollTimer?.cancel();
    _clipboardPollTimer = null;
    _remoteFetchTimer?.cancel();
    _remoteFetchTimer = null;
  }

  void dispose() {
    stopListening();
    _historyController.close();
  }
}
