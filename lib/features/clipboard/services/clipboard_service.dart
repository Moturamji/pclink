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

  // Connection health tracking
  bool _serverReachable = false;
  int _consecutiveFailures = 0;
  bool _refreshInProgress = false;
  String? _lastLoggedUrl;

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

    // 1. Check local clipboard immediately and start local clipboard poll (400ms)
    _checkLocalClipboard();
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
      // Android: Poll latest clip from Windows server (2s interval with smart backoff)
      _remoteFetchTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        await _fetchLatestRemoteClipFromWindowsServer();
      });

      // Start Android Foreground Service with 1-tap notification action
      if (!kIsWeb && Platform.isAndroid) {
        FlutterForegroundTask.addTaskDataCallback(_onForegroundDataReceived);
        _startAndroidForegroundService();
      }

      // Initial connectivity check + history fetch
      _checkServerConnectivityAndSync();
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
      _consecutiveFailures = 0; // Reset backoff on app resume
      _fetchLatestRemoteClipFromWindowsServer();
    }
  }

  /// Checks connectivity to the Windows server and syncs history if reachable.
  Future<void> _checkServerConnectivityAndSync() async {
    final serverUrl = _getTargetServerUrl?.call();
    if (serverUrl == null || serverUrl.isEmpty) {
      debugPrint('ClipboardService: ⚠️ Server URL is null/empty — waiting for discovery...');
      return;
    }

    final sanitizedUrl = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;

    // Log the URL being targeted (only when it changes)
    if (_lastLoggedUrl != sanitizedUrl) {
      _lastLoggedUrl = sanitizedUrl;
      debugPrint('ClipboardService: 🎯 Target server URL: $sanitizedUrl');
    }

    // Try a quick health check first
    try {
      final healthUri = Uri.parse('$sanitizedUrl${ServerConstants.healthEndpoint}');
      debugPrint('ClipboardService: 🔍 Testing connectivity to $healthUri ...');
      final response = await _client.get(healthUri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        _serverReachable = true;
        _consecutiveFailures = 0;
        debugPrint('ClipboardService: ✅ Server reachable! Response: ${response.body}');
        await refreshHistory();
      } else {
        _serverReachable = false;
        debugPrint('ClipboardService: ❌ Server returned status ${response.statusCode}');
      }
    } catch (e) {
      _serverReachable = false;
      debugPrint('ClipboardService: ❌ Cannot reach server at $sanitizedUrl — $e');
      debugPrint('ClipboardService: 💡 Make sure:');
      debugPrint('  1. Both devices are on the SAME Wi-Fi network (192.168.20.x)');
      debugPrint('  2. Windows Firewall allows inbound TCP on port 8088');
      debugPrint('     Run as Admin: netsh advfirewall firewall add rule name="PCLink" dir=in action=allow protocol=TCP localport=8088');
      debugPrint('  3. The Windows PCLink app is running');
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
    if (serverUrl == null || serverUrl.isEmpty) {
      debugPrint('ClipboardService _postClip: serverUrl is null/empty yet');
      return;
    }

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
        _serverReachable = true;
        _consecutiveFailures = 0;
        debugPrint('ClipboardService: ✅ Direct clip sent to Windows server at $sanitizedUrl (${item.charCount} chars)');
      } else {
        debugPrint('ClipboardService _postClip error: status ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _consecutiveFailures++;
      if (_consecutiveFailures <= 3) {
        debugPrint('ClipboardService: ❌ _postClipToWindowsServer error (attempt $_consecutiveFailures): $e');
      }
    }
  }

  /// Android <- Windows: Fetches latest copied clip directly from Windows server.
  Future<void> _fetchLatestRemoteClipFromWindowsServer() async {
    final serverUrl = _getTargetServerUrl?.call();
    if (serverUrl == null || serverUrl.isEmpty) return;

    // Smart backoff: skip polls when server is proven unreachable
    if (_consecutiveFailures > 5) {
      // Only retry every 10th attempt (20s effective interval)
      if (_consecutiveFailures % 10 != 0) {
        return;
      }
      debugPrint('ClipboardService: 🔄 Retrying server connection after $_consecutiveFailures failures...');
    }

    try {
      final sanitizedUrl = serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl;
      final uri = Uri.parse('$sanitizedUrl${ServerConstants.clipboardLatestEndpoint}');

      final response = await _client.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        // Mark as reachable
        if (!_serverReachable) {
          debugPrint('ClipboardService: ✅ Server connection restored!');
        }
        _serverReachable = true;
        _consecutiveFailures = 0;

        if (response.body.isNotEmpty && response.body != 'null') {
          final dynamic data = jsonDecode(response.body);
          if (data is Map) {
            final item = ClipboardItem.fromMap(data);
            if (item.sourcePlatform != _currentPlatformName && item.text != _lastReceivedRemoteText) {
              debugPrint('ClipboardService: 📋 Android received new clip from PC: ${item.previewText}');
              _handleRemoteClipReceived(item);
            }
          }
        }
      }
    } catch (e) {
      _consecutiveFailures++;
      if (_consecutiveFailures <= 3 || _consecutiveFailures % 20 == 0) {
        debugPrint('ClipboardService: ❌ Fetch from server failed ($_consecutiveFailures): $e');
      }
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
  /// Debounced — will not fire concurrently.
  Future<void> refreshHistory() async {
    if (_currentPlatformName == 'windows') {
      if (_serverService != null) {
        _history.clear();
        _history.addAll(_serverService!.clipboardHistory);
        _historyController.add(List.from(_history));
      }
      return;
    }

    // Debounce: skip if already in progress
    if (_refreshInProgress) return;
    _refreshInProgress = true;

    final serverUrl = _getTargetServerUrl?.call();
    if (serverUrl == null || serverUrl.isEmpty) {
      _refreshInProgress = false;
      return;
    }

    try {
      final sanitizedUrl = serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl;
      final uri = Uri.parse('$sanitizedUrl${ServerConstants.clipboardEndpoint}');

      final response = await _client.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200 && response.body.isNotEmpty && response.body != 'null') {
        _serverReachable = true;
        _consecutiveFailures = 0;
        final dynamic listData = jsonDecode(response.body);
        if (listData is List) {
          for (final raw in listData) {
            if (raw is Map) {
              final item = ClipboardItem.fromMap(raw);
              if (!_history.any((c) => c.id == item.id || c.text == item.text)) {
                _history.add(item);
              }
            }
          }
          _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          if (_history.length > 50) {
            _history.removeRange(50, _history.length);
          }
          _historyController.add(List.from(_history));
        }
      }
    } catch (e) {
      _consecutiveFailures++;
      // Only log first 3 failures, then throttle
      if (_consecutiveFailures <= 3) {
        debugPrint('ClipboardService: ❌ refreshHistory error ($_consecutiveFailures): $e');
      } else if (_consecutiveFailures == 4) {
        debugPrint('ClipboardService: ⚠️ Server unreachable — suppressing repeat logs. Will retry periodically.');
      }
    } finally {
      _refreshInProgress = false;
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
