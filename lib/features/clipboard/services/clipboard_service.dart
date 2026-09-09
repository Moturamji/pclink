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
  List<String>? Function()? _getTargetServerUrls;
  String? Function()? _getServerStartTime;
  String? _deviceId;
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

  // Adaptive URL routing: remembers the last working PC URL and falls back
  // between the Public WAN and LAN addresses when the active one dies.
  String? _workingServerUrl;
  String? _lastError;
  String? _lastEmittedError;
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  // Probe throttling: only one URL probe runs at a time, and when the PC is
  // unreachable we back off progressively instead of hammering every 2s.
  bool _probeInFlight = false;
  DateTime _nextProbeAllowedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSeenServerSignature;

  bool get isListening => _clipboardPollTimer != null;
  Stream<List<ClipboardItem>> get clipboardHistoryStream =>
      _historyController.stream;
  List<ClipboardItem> get currentHistory => List.unmodifiable(_history);

  String? get lastError => _lastError;
  int get failureCount => _consecutiveFailures;
  bool get isServerReachable => _serverReachable;
  Stream<String?> get errorStream => _errorController.stream;

  /// Initializes Android Foreground Task configurations.
  static Future<void> initForegroundTask() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'pclink_foreground_sync',
          channelName: 'PCLink Background Sync',
          channelDescription:
              'Maintains live background connection and direct clipboard route with PC',
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
    List<String>? Function()? getTargetServerUrls,
    String? Function()? getServerStartTime,
    String? deviceId,
    Function(ClipboardItem)? onNewRemoteClipReceived,
  }) {
    if (_clipboardPollTimer != null) return;

    _currentDeviceName = deviceName;
    _currentPlatformName = isWindows ? 'windows' : 'android';
    _serverService = serverService;
    _getTargetServerUrls = getTargetServerUrls;
    _getServerStartTime = getServerStartTime;
    _deviceId = deviceId;
    _onNewRemoteClipReceived = onNewRemoteClipReceived;

    WidgetsBinding.instance.addObserver(this);

    // 1. Check local clipboard immediately and start local clipboard poll (400ms)
    _checkLocalClipboard();
    _clipboardPollTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) async {
        await _checkLocalClipboard();
      },
    );

    if (isWindows && _serverService != null) {
      // Windows: Server receives direct clips from Android via HTTP POST /api/clipboard
      _serverService!.onClipboardReceived = (item) {
        _handleRemoteClipReceived(item);
      };
      _history.addAll(_serverService!.clipboardHistory);
      _historyController.add(List.from(_history));
    } else {
      // Android: Poll latest clip from Windows server (2s interval with smart backoff)
      _remoteFetchTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) async {
          await _fetchLatestRemoteClipFromWindowsServer();
        },
      );

      // Start Android Foreground Service with 1-tap notification action
      if (!kIsWeb && Platform.isAndroid) {
        FlutterForegroundTask.addTaskDataCallback(_onForegroundDataReceived);
        _startAndroidForegroundService();
      }

      // Initial connectivity check + history fetch
      _checkServerConnectivityAndSync();
    }

    debugPrint(
      'ClipboardService: Started direct server clipboard sync for $_currentPlatformName ($deviceName)',
    );
  }
void _onForegroundDataReceived(dynamic data) {
    if (data == 'sync_clipboard_now') {
      _checkLocalClipboard();
    }
  }

  // -------------------------------------------------------------------------
  // Adaptive URL routing helpers
  // -------------------------------------------------------------------------

  /// All candidate PC server URLs (public WAN first, then LAN), deduplicated.
  List<String> _candidateUrls() {
    final list = _getTargetServerUrls?.call();
    if (list == null || list.isEmpty) return const <String>[];
    final result = <String>[];
    for (final raw in list) {
      if (raw.isEmpty) continue;
      final s = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
      if (!result.contains(s)) result.add(s);
    }
    return result;
  }

  /// Best URL: the last proven-working one, otherwise the first candidate.
  String? get _targetServerUrl {
    if (_workingServerUrl != null && _workingServerUrl!.isNotEmpty) {
      return _workingServerUrl;
    }
    final urls = _candidateUrls();
    return urls.isEmpty ? null : urls.first;
  }

  /// True when a fresh probe should actually hit the network. While the PC is
  /// known to be unreachable we wait out a progressive backoff instead of
  /// timing out on both addresses every 2 seconds.
  bool _shouldProbeNow() {
    if (_consecutiveFailures <= 2) return true;
    return DateTime.now().isAfter(_nextProbeAllowedAt);
  }

  /// Tries every candidate URL (starting from the last working one) and
  /// returns the first response. Serializes concurrent probes into a single
  /// in-flight attempt; marks connectivity + resets backoff on any HTTP
  /// response; treats transport errors as per-candidate failures.
  /// Set [allowBackoffSkip] to false to always attempt (user-initiated ops
  /// like a fresh POST / DELETE).
  Future<http.Response?> _tryUrlFallback(
    Future<http.Response> Function(String baseUrl) send, {
    bool allowBackoffSkip = true,
  }) async {
    // Wait for any in-flight probe so concurrent timers don't stack requests.
    while (_probeInFlight) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    if (allowBackoffSkip && !_shouldProbeNow()) {
      debugPrint('ClipboardService: Probe throttled (offline backoff) - skipping.');
      return null;
    }

    final urls = _candidateUrls();
    if (urls.isEmpty) {
      _reportFailure('Waiting for your PC server address from Firebase...');
      return null;
    }

    _probeInFlight = true;
    try {
      var startIndex = urls.indexOf(_workingServerUrl ?? '');
      if (startIndex < 0) startIndex = 0;

      for (var i = 0; i < urls.length; i++) {
        final url = urls[(startIndex + i) % urls.length];
        try {
          final resp = await send(url);
          _markSuccess();
          _workingServerUrl = url;
          if (_lastLoggedUrl != url) {
            _lastLoggedUrl = url;
            debugPrint('ClipboardService: Using PC server $url');
          }
          return resp;
        } catch (e) {
          debugPrint('ClipboardService: $url unreachable - $e');
        }
      }
    } finally {
      _probeInFlight = false;
    }

    _workingServerUrl = null;
    _consecutiveFailures++;
    // Progressive backoff (5s, 10s, 15s, 20s, then max 30s) so an unreachable
    // PC doesn't cause endless 3s timeouts on every 2s timer.
    final backoffSeconds = const [5, 10, 15, 20, 30][
      (_consecutiveFailures - 1).clamp(0, 4)
    ];
    _nextProbeAllowedAt = DateTime.now().add(Duration(seconds: backoffSeconds));
    _reportFailure(
      'Cannot reach your PC server yet (${urls.join(', ')}). Make sure PCLink is open on the PC, then copy again.',
    );
    return null;
  }

  void _reportFailure(String message) {
    _serverReachable = false;
    _lastError = message;
    if (_lastEmittedError != message) {
      _lastEmittedError = message;
      if (!_errorController.isClosed) {
        _errorController.add(message);
      }
    }
  }

  void _markSuccess() {
    final wasOffline = !_serverReachable;
    _serverReachable = true;
    _consecutiveFailures = 0;
    _lastError = null;
    if (wasOffline) {
      _lastEmittedError = null;
      if (!_errorController.isClosed) {
        _errorController.add(null);
      }
    }
  }

  /// Headers that prove this device is the registered Android phone and knows
  /// the current server session (start time) - used as the clipboard password.
  Map<String, String> _authHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final deviceId = _deviceId;
    if (deviceId != null && deviceId.isNotEmpty) {
      headers[ServerConstants.authHeader] = deviceId;
    }
    final startTime = _getServerStartTime?.call();
    if (startTime != null && startTime.isNotEmpty) {
      headers[ServerConstants.startTimeHeader] = startTime;
    }
    return headers;
  }

  Future<void> _startAndroidForegroundService() async {
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'PCLink Live Sync Active',
          notificationText: 'Tap "Send to PC" to instantly transfer clipboard',
          notificationButtons: [
            const NotificationButton(id: 'sync_now', text: 'Send to PC'),
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
    final serverUrl = _targetServerUrl;
    if (serverUrl == null || serverUrl.isEmpty) {
      debugPrint(
          'ClipboardService: Server URL not discovered yet - waiting for Firebase server info...');
      return;
    }

    final response = await _tryUrlFallback(
      (url) => _client
          .get(Uri.parse('$url${ServerConstants.healthEndpoint}'))
          .timeout(const Duration(seconds: 4)),
    );

    if (response != null && response.statusCode == 200) {
      debugPrint('ClipboardService: PC server reachable. Refreshing history...');
      await refreshHistory();
    } else if (response != null && response.statusCode != 200) {
      _consecutiveFailures++;
      _reportFailure(
        'PC server responded with status ${response.statusCode}. Try restarting PCLink on the PC.',
      );
    }
  }

  /// Called whenever Firebase publishes a fresh server info. Only when the
  /// address or the server session (start time) actually changed do we reset
  /// the offline backoff and probe immediately - otherwise we stay throttled.
  void onServerInfoPublished() {
    final sig =
        '${_candidateUrls().join('|')}#${_getServerStartTime?.call() ?? ''}';
    if (sig == _lastSeenServerSignature) return;
    _lastSeenServerSignature = sig;
    _consecutiveFailures = 0;
    _nextProbeAllowedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _workingServerUrl = null; // re-probe from a fresh candidate list
    debugPrint('ClipboardService: New server info published - probing now.');
    _checkServerConnectivityAndSync();
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

      debugPrint(
          'ClipboardService: Transferred local clip directly (${item.charCount} chars)');
    } catch (e) {
      debugPrint('ClipboardService check error: $e');
    }
  }

  /// Android -> Windows: Directly sends copied text to Windows server.
  Future<void> _postClipToWindowsServer(ClipboardItem item) async {
    var startUrl = _targetServerUrl;
    if (startUrl == null || startUrl.isEmpty) {
      // PC address may still be arriving from Firebase; retry briefly so the
      // first copy isn't lost.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      startUrl = _targetServerUrl;
    }
    if (startUrl == null || startUrl.isEmpty) {
      debugPrint('ClipboardService _postClip: server URL not ready yet');
      return;
    }

    // User just copied something — always attempt, ignoring offline backoff.
    final response = await _tryUrlFallback(
      (url) => _client
          .post(
            Uri.parse('$url${ServerConstants.clipboardEndpoint}'),
            headers: _authHeaders(),
            body: jsonEncode(item.toMap()),
          )
          .timeout(const Duration(seconds: 3)),
      allowBackoffSkip: false,
    );

    if (response == null) {
      debugPrint('ClipboardService: POST failed on all server addresses');
      return;
    }

    if (response.statusCode == 200) {
      debugPrint('ClipboardService: Direct clip sent to PC (${item.charCount} chars)');
    } else {
      debugPrint(
          'ClipboardService _postClip error: status ${response.statusCode} - ${response.body}');
      if (response.statusCode == 401) {
        _reportFailure(
          'PC rejected this device or the server session password. Open PCLink on the PC (restart if needed), then reconnect.',
        );
      }
    }
  }

  /// Android <- Windows: Fetches the latest copied clip directly from the PC server.
  Future<void> _fetchLatestRemoteClipFromWindowsServer() async {
    if (_currentPlatformName == null || _currentPlatformName == 'windows') return;
    final serverUrl = _targetServerUrl;
    if (serverUrl == null || serverUrl.isEmpty) return;

    // Throttling is handled centrally inside [_tryUrlFallback] (serialized
    // probes + progressive backoff), so every timer tick simply delegates.
    final response = await _tryUrlFallback(
      (url) {
        // Tunnel (https) first contact can be slow (cold start / TLS) -
        // allow extra time; LAN stays snappy.
        final tunnel = url.startsWith('https://');
        return _client
            .get(Uri.parse('$url${ServerConstants.clipboardLatestEndpoint}'))
            .timeout(Duration(seconds: tunnel ? 10 : 4));
      },
    );

    if (response == null) return;

    if (response.statusCode == 200 &&
        response.body.isNotEmpty &&
        response.body != 'null') {
      final dynamic data = jsonDecode(response.body);
      if (data is Map) {
        final item = ClipboardItem.fromMap(data);
        if (item.sourcePlatform != _currentPlatformName &&
            item.text != _lastReceivedRemoteText) {
          debugPrint(
              'ClipboardService: Received new clip from PC: ${item.previewText}');
          _handleRemoteClipReceived(item);
        }
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
  /// Debounced - does not fire concurrently; falls back across candidate URLs.
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

    try {
      final response = await _tryUrlFallback(
        (url) => _client
            .get(Uri.parse('$url${ServerConstants.clipboardEndpoint}'))
            .timeout(const Duration(seconds: 4)),
      );

      if (response != null &&
          response.statusCode == 200 &&
          response.body.isNotEmpty &&
          response.body != 'null') {
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
      debugPrint('ClipboardService: refreshHistory error ($_consecutiveFailures): $e');
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
      await _tryUrlFallback(
        (url) => _client
            .delete(
              Uri.parse('$url${ServerConstants.clipboardEndpoint}'),
              headers: _authHeaders(),
            )
            .timeout(const Duration(seconds: 3)),
        allowBackoffSkip: false,
      );
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
    _errorController.close();
  }
}