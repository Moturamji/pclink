import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screen_capture/flutter_screen_capture.dart';
import 'package:image/image.dart' as image;
import '../../core/constants/server_constants.dart';
import 'platform_helpers.dart';

/// Task payload passed to background worker isolate for JPEG encoding.
class _FrameEncodeTask {
  final Uint8List buffer;
  final int width;
  final int height;
  final int bytesPerPixel;
  final int maxWidth;
  final int quality;
  final bool isBgra;

  const _FrameEncodeTask({
    required this.buffer,
    required this.width,
    required this.height,
    required this.bytesPerPixel,
    required this.maxWidth,
    required this.quality,
    required this.isBgra,
  });
}

/// Standalone top-level worker for background isolate processing fallback.
/// Uses BGRA pixel channel ordering on Windows/macOS to ensure 100% color accuracy.
Uint8List _encodeFrameWorker(_FrameEncodeTask task) {
  final img = image.Image.fromBytes(
    width: task.width,
    height: task.height,
    bytes: task.buffer.buffer,
    order: task.isBgra ? image.ChannelOrder.bgra : image.ChannelOrder.rgba,
  );

  final image.Image processed;
  if (task.maxWidth > 0 && img.width > task.maxWidth) {
    processed = image.copyResize(
      img,
      width: task.maxWidth,
      interpolation: image.Interpolation.linear,
    );
  } else {
    processed = img;
  }

  return Uint8List.fromList(image.encodeJpg(processed, quality: task.quality));
}

/// Preset resolution and compression quality profiles.
/// Ordered from highest bandwidth -> lowest, used for adaptive downgrade.
class ScreenShareQualityPreset {
  final String name;
  final int maxWidth;
  final int jpegQuality;
  final int targetFps; // used by server loop

  const ScreenShareQualityPreset({
    required this.name,
    required this.maxWidth,
    required this.jpegQuality,
    required this.targetFps,
  });

  /// Ultra Sharp: 1080p / Native up to 1920px with 85% JPEG quality.
  /// Razor-sharp text, terminal code, and fine desktop UI.
  static const ultra = ScreenShareQualityPreset(
    name: 'ultra',
    maxWidth: 1920,
    jpegQuality: 85,
    targetFps: 30,
  );

  /// High / Balanced: 1440px with 78% quality.
  static const high = ScreenShareQualityPreset(
    name: 'high',
    maxWidth: 1440,
    jpegQuality: 78,
    targetFps: 30,
  );

  /// Fast / Smooth: 1080px with 70% quality.
  static const fast = ScreenShareQualityPreset(
    name: 'fast',
    maxWidth: 1080,
    jpegQuality: 70,
    targetFps: 30,
  );

  /// Low / Resilient: 960px with 60% quality — 60% smaller payload for 2G/3G or congested Wi-Fi.
  static const low = ScreenShareQualityPreset(
    name: 'low',
    maxWidth: 960,
    jpegQuality: 60,
    targetFps: 24,
  );

  /// Minimum: 720px with 50% quality — last resort for very poor links.
  static const eco = ScreenShareQualityPreset(
    name: 'eco',
    maxWidth: 720,
    jpegQuality: 50,
    targetFps: 20,
  );

  /// Ordered list high -> low for adaptive selection.
  static const List<ScreenShareQualityPreset> ordered = [ultra, high, fast, low, eco];

  static ScreenShareQualityPreset fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'eco':
        return eco;
      case 'low':
        return low;
      case 'fast':
        return fast;
      case 'high':
        return high;
      case 'ultra':
      default:
        return ultra;
    }
  }

  ScreenShareQualityPreset stepDown() {
    final idx = ordered.indexWhere((p) => p.name == name);
    if (idx == -1 || idx >= ordered.length - 1) return this;
    return ordered[idx + 1];
  }

  ScreenShareQualityPreset stepUp() {
    final idx = ordered.indexWhere((p) => p.name == name);
    if (idx <= 0) return this;
    return ordered[idx - 1];
  }
}

/// Active WebSocket client connection tracking for backpressure, RTT and adaptive quality.
class _ScreenShareWsClient {
  final WebSocket socket;
  final String id;
  final String viewerName;
  ScreenShareQualityPreset quality;
  ScreenShareQualityPreset requestedQuality; // user-selected upper bound
  DateTime lastSentAt = DateTime.now();
  DateTime connectedAt = DateTime.now();

  /// Send time of every frame not yet acknowledged, oldest first. WebSocket
  /// runs over TCP, so ACKs arrive in send order and each one pops the head.
  final Queue<DateTime> _inFlight = Queue<DateTime>();

  // Adaptive streaming signals
  int consecutiveSlowAcks = 0;
  int consecutiveFastAcks = 0;
  int lastRttMs = 0;
  DateTime lastAdaptiveChangeAt = DateTime.fromMillisecondsSinceEpoch(0);

  _ScreenShareWsClient({
    required this.socket,
    required this.id,
    required this.viewerName,
    required this.quality,
  }) : requestedQuality = quality;

  /// At most this many frames may be unacknowledged. Two keeps the pipe busy
  /// during one round trip; more would only queue stale frames in the socket.
  static const int maxFramesInFlight = 2;

  /// A viewer that stops acknowledging (stalled decoder, backgrounded app) is
  /// treated as having dropped its frames after this long, so it can recover.
  static const int stalledAckResetMs = 3000;

  bool get isReadyOrTimedOut {
    if (_inFlight.length < maxFramesInFlight) return true;
    if (DateTime.now().difference(lastSentAt).inMilliseconds > stalledAckResetMs) {
      _inFlight.clear();
      return true;
    }
    return false;
  }

  void markFrameSent(DateTime at) {
    lastSentAt = at;
    _inFlight.addLast(at);
  }

  /// Round trip of the frame this ACK belongs to, or null for a stray ACK.
  int? acknowledgeFrame() {
    if (_inFlight.isEmpty) return null;
    return DateTime.now().difference(_inFlight.removeFirst()).inMilliseconds;
  }

  bool get canAdaptNow =>
      DateTime.now().difference(lastAdaptiveChangeAt).inMilliseconds > 2500;
}

/// Windows-only, view-only real-time screen sharing service.
/// Uses native Win32 GDI + GDI+ SIMD hardware compression with isolate fallback,
/// WebSocket push delivery, and ACK backpressure with timeout watchdog.
class ScreenShareService {
  static const String _preferenceFileName = 'pclink_screen_share_consent.txt';

  static const int hostEndedCloseCode =
      ServerConstants.screenShareHostEndedCloseCode;

  /// An HTTP-started session with no WebSocket viewer and no frame polls for
  /// this long is considered abandoned (e.g. the phone app was killed).
  static const Duration _abandonedSessionTimeout = Duration(seconds: 30);
  static const MethodChannel _nativeChannel =
      MethodChannel('pclink/native_screen_share');

  static ScreenShareService? _activeInstance;
  static final ValueNotifier<bool> consentNotifier = ValueNotifier<bool>(false);

  final List<_ScreenShareWsClient> _wsClients = [];
  Timer? _fallbackPollTimer;
  bool _fallbackCaptureInFlight = false;
  DateTime? _lastViewerSeenAt;
  DateTime? _lastFramePollAt;
  Uint8List? _latestFrame;
  DateTime? _lastFrameAt;
  String? _viewerName;
  bool _isCapturing = false;
  bool _loopRunning = false;
  bool _useNativeCapture = true;

  final StreamController<ScreenShareStatus> _statusController =
      StreamController<ScreenShareStatus>.broadcast();

  ScreenShareService() {
    _activeInstance = this;
    // Asynchronously synchronize notifier with system consent file
    isConsentGranted();
  }

  Stream<ScreenShareStatus> get statusStream => _statusController.stream;
  ScreenShareStatus get status => ScreenShareStatus(
        isStreaming: _isCapturing || _wsClients.isNotEmpty,
        isAuthorized: consentNotifier.value,
        viewerName: _viewerName,
        lastFrameAt: _lastFrameAt,
        clientCount: _wsClients.length,
      );

  static String get _appDataDir {
    if (!kIsWeb && Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      return appData == null || appData.isEmpty ? '.' : '$appData\\pclink';
    } else if (!kIsWeb && Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      return home == null || home.isEmpty
          ? '.'
          : '$home/Library/Application Support/pclink';
    }
    return '.';
  }

  static File get _preferenceFile {
    if (!kIsWeb && Platform.isWindows) {
      return File('$_appDataDir\\$_preferenceFileName');
    }
    return File('$_appDataDir/$_preferenceFileName');
  }

  static Future<bool> hasConsentPreference() async {
    if (kIsWeb || !isDesktopHost) return false;
    try {
      return await _preferenceFile.exists();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isConsentGranted() async {
    if (kIsWeb || !isDesktopHost) return false;
    try {
      if (await _preferenceFile.exists()) {
        final content = (await _preferenceFile.readAsString()).trim().toLowerCase();
        final granted = content == 'enabled';
        consentNotifier.value = granted;
        return granted;
      }
      consentNotifier.value = false;
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setConsentGranted(bool granted) async {
    if (kIsWeb || !isDesktopHost) return;
    final dir = Directory(_appDataDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    await _preferenceFile.writeAsString(granted ? 'enabled' : 'disabled');
    consentNotifier.value = granted;
    if (granted && Platform.isMacOS) {
      // macOS only captures other apps' windows after the user allows
      // Screen Recording; show the system prompt when sharing is enabled.
      try {
        await _nativeChannel.invokeMethod<bool>('requestPermission');
      } catch (_) {}
    }
    if (!granted) {
      await _activeInstance?.stop();
    }
  }

  /// Register an active WebSocket stream client.
  /// Automatically starts the real-time capture and push loop.
  void registerWebSocketClient({
    required WebSocket socket,
    required String viewerName,
    String initialQuality = 'ultra',
  }) {
    final clientId = 'ws_${DateTime.now().microsecondsSinceEpoch}';
    final client = _ScreenShareWsClient(
      socket: socket,
      id: clientId,
      viewerName: viewerName,
      quality: ScreenShareQualityPreset.fromString(initialQuality),
    );

    _wsClients.add(client);
    _viewerName = viewerName;
    _isCapturing = true;
    _publishStatus();

    socket.listen(
      (message) {
        if (message is String) {
          if (message == 'ack') {
            final rtt = client.acknowledgeFrame();
            if (rtt == null) return;
            client.lastRttMs = rtt;
            // Adaptive quality: sustained high RTT -> downgrade; sustained low RTT -> upgrade.
            // Slow threshold 220ms (~2x frame interval), fast threshold 60ms.
            if (rtt > 220) {
              client.consecutiveSlowAcks++;
              client.consecutiveFastAcks = 0;
              if (client.consecutiveSlowAcks >= 4 && client.canAdaptNow) {
                final next = client.quality.stepDown();
                if (next.name != client.quality.name) {
                  client.quality = next;
                  client.lastAdaptiveChangeAt = DateTime.now();
                  client.consecutiveSlowAcks = 0;
                  try {
                    socket.add('quality:${next.name}');
                  } catch (_) {}
                  debugPrint('ScreenShare: adaptive downgrade -> ${next.name} (RTT ${rtt}ms)');
                }
              }
            } else if (rtt < 60) {
              client.consecutiveFastAcks++;
              if (client.consecutiveFastAcks >= 12 && client.canAdaptNow) {
                // Only upgrade up to the user-selected cap
                final capIdx = ScreenShareQualityPreset.ordered.indexWhere((p) => p.name == client.requestedQuality.name);
                final next = client.quality.stepUp();
                final nextIdx = ScreenShareQualityPreset.ordered.indexWhere((p) => p.name == next.name);
                if (next.name != client.quality.name && nextIdx >= capIdx) {
                  client.quality = next;
                  client.lastAdaptiveChangeAt = DateTime.now();
                  client.consecutiveFastAcks = 0;
                  try {
                    socket.add('quality:${next.name}');
                  } catch (_) {}
                  debugPrint('ScreenShare: adaptive upgrade -> ${next.name} (RTT ${rtt}ms)');
                } else {
                  client.consecutiveFastAcks = 0;
                }
              }
              client.consecutiveSlowAcks = 0;
            } else {
              client.consecutiveSlowAcks = 0;
              client.consecutiveFastAcks = 0;
            }
          } else if (message.startsWith('quality:')) {
            final qName = message.substring('quality:'.length).trim();
            final q = ScreenShareQualityPreset.fromString(qName);
            client.requestedQuality = q;
            // Respect manual override immediately (clamped to requested)
            client.quality = q;
            client.consecutiveSlowAcks = 0;
            client.consecutiveFastAcks = 0;
            client.lastAdaptiveChangeAt = DateTime.now();
          } else if (message == 'ping') {
            try {
              socket.add('pong');
            } catch (_) {}
          }
        }
      },
      onError: (e) {
        _removeClient(client);
      },
      onDone: () {
        _removeClient(client);
      },
      cancelOnError: true,
    );

    _ensureCaptureLoopRunning();
  }

  void _removeClient(_ScreenShareWsClient client) {
    _wsClients.remove(client);
    try {
      client.socket.close();
    } catch (_) {}
    if (_wsClients.isEmpty) {
      if (_fallbackPollTimer == null) {
        _isCapturing = false;
      }
      _viewerName = null;
      _publishStatus();
    }
  }

  /// Starts the screen sharing capture engine (used for HTTP polling fallback or explicit start).
  Future<bool> start({required String viewerName}) async {
    if (!await isConsentGranted()) return false;
    _viewerName = viewerName;
    _isCapturing = true;
    _publishStatus();

    _lastViewerSeenAt = DateTime.now();
    _lastFramePollAt = null;

    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = Timer.periodic(
      const Duration(milliseconds: 100), // 10 FPS fallback
      (_) => _captureFallbackFrame(),
    );
    _ensureCaptureLoopRunning();
    return true;
  }

  Future<void> stop() async {
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = null;
    _isCapturing = false;
    _viewerName = null;

    // Close all connected WebSocket clients
    final clients = List<_ScreenShareWsClient>.from(_wsClients);
    _wsClients.clear();
    for (final client in clients) {
      try {
        client.socket.close(hostEndedCloseCode, 'Screen sharing ended by the PC');
      } catch (_) {}
    }

    _lastViewerSeenAt = null;
    _lastFramePollAt = null;
    _latestFrame = null;
    _lastFrameAt = null;
    _publishStatus();
  }

  Uint8List? takeLatestFrame() {
    _lastFramePollAt = DateTime.now();
    return _latestFrame;
  }

  void _ensureCaptureLoopRunning() {
    if (_loopRunning) return;
    _loopRunning = true;
    _runStreamingLoop();
  }

  /// Groups ready viewers by their current preset so each viewer gets the
  /// quality its own link sustains; one slow phone no longer degrades others.
  /// Ordered lowest quality first, so `_latestFrame` ends as the sharpest one.
  Map<ScreenShareQualityPreset, List<_ScreenShareWsClient>> _groupByPreset(
    List<_ScreenShareWsClient> clients,
  ) {
    final groups = <ScreenShareQualityPreset, List<_ScreenShareWsClient>>{};
    for (final preset in ScreenShareQualityPreset.ordered.reversed) {
      final members = clients.where((c) => c.quality.name == preset.name).toList();
      if (members.isNotEmpty) groups[preset] = members;
    }
    return groups;
  }

  /// High-performance screen capture: uses native Win32 GDI + GDI+ SIMD encoder
  /// when available (< 6ms, < 1% CPU, 100% color accurate), with isolate fallback.
  Future<Uint8List?> _captureFrame({
    required int maxWidth,
    required int quality,
  }) async {
    if (!_isCapturing || kIsWeb || !isDesktopHost) return null;

    // 1. Try Native Windows GDI + GDI+ SIMD hardware compression
    if ((Platform.isWindows || Platform.isMacOS) && _useNativeCapture) {
      try {
        final result = await _nativeChannel.invokeMethod<Uint8List>(
          'captureFrame',
          <String, dynamic>{'maxWidth': maxWidth, 'quality': quality},
        );
        if (result != null && result.isNotEmpty) {
          return result;
        }
      } on MissingPluginException catch (e) {
        debugPrint(
            'ScreenShareService: Native capture unavailable, falling back to isolate: $e');
        _useNativeCapture = false;
      } on PlatformException catch (e) {
        // A single failed frame (lock screen, UAC secure desktop, display
        // change) must not permanently downgrade to the slow Dart encoder.
        debugPrint('ScreenShareService: Native frame skipped: ${e.message}');
        return null;
      }
    }

    // 2. Isolate-based pure Dart fallback (for testing or non-native execution)
    try {
      final area = await ScreenCapture().captureEntireScreen();
      if (area == null || !_isCapturing) return null;

      final task = _FrameEncodeTask(
        buffer: area.buffer,
        width: area.width,
        height: area.height,
        bytesPerPixel: area.bytesPerPixel,
        maxWidth: maxWidth,
        quality: quality,
        // Both Windows and macOS capture in BGRA byte order!
        isBgra: Platform.isWindows || Platform.isMacOS,
      );
      return await compute(_encodeFrameWorker, task);
    } catch (e) {
      debugPrint('ScreenShareService fallback capture failed: $e');
      return null;
    }
  }

  /// Feeds the HTTP polling endpoint. It only captures while a phone is
  /// actually polling and no WebSocket viewer is connected (the streaming
  /// loop already refreshes `_latestFrame` then), and ends a session that
  /// nobody is watching any more.
  Future<void> _captureFallbackFrame() async {
    if (!_isCapturing || kIsWeb || !isDesktopHost) return;
    final now = DateTime.now();
    if (_wsClients.isNotEmpty) {
      _lastViewerSeenAt = now;
      return;
    }
    if (_fallbackCaptureInFlight) return;

    final seen = _lastViewerSeenAt ?? now;
    final polled = _lastFramePollAt;
    final lastActivity = polled != null && polled.isAfter(seen) ? polled : seen;
    if (now.difference(lastActivity) > _abandonedSessionTimeout) {
      debugPrint('ScreenShareService: No viewer for 30s, ending session');
      await stop();
      return;
    }
    final polledRecently = _lastFramePollAt != null &&
        now.difference(_lastFramePollAt!) < const Duration(seconds: 3);
    if (!polledRecently) return;

    _fallbackCaptureInFlight = true;
    try {
      final frame = await _captureFrame(maxWidth: 1920, quality: 85);
      if (frame != null && _isCapturing) {
        _latestFrame = frame;
        _lastFrameAt = DateTime.now();
        _publishStatus();
      }
    } finally {
      _fallbackCaptureInFlight = false;
    }
  }

  Future<void> _runStreamingLoop() async {
    while (_isCapturing && !kIsWeb && isDesktopHost) {
      if (_wsClients.isEmpty) {
        // No active WebSocket streams, yield
        await Future.delayed(const Duration(milliseconds: 100));
        if (_wsClients.isEmpty && _fallbackPollTimer == null) {
          break;
        }
        continue;
      }

      final readyClients =
          _wsClients.where((c) => c.isReadyOrTimedOut).toList();

      // If all active clients are still decoding/rendering the previous frame,
      // pause briefly instead of capturing redundant frames that would be dropped.
      if (readyClients.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 6));
        continue;
      }

      final stopwatch = Stopwatch()..start();
      final groups = _groupByPreset(readyClients);
      try {
        for (final entry in groups.entries) {
          final encoded = await _captureFrame(
            maxWidth: entry.key.maxWidth,
            quality: entry.key.jpegQuality,
          );
          if (encoded == null || !_isCapturing || _wsClients.isEmpty) continue;

          _latestFrame = encoded;
          _lastFrameAt = DateTime.now();
          final now = DateTime.now();
          for (final client in entry.value) {
            if (!_wsClients.contains(client)) continue;
            try {
              client.markFrameSent(now);
              client.socket.add(encoded);
            } catch (e) {
              _removeClient(client);
            }
          }
        }
        _publishStatus();
      } catch (e) {
        debugPrint('ScreenShareService stream capture error: $e');
      }

      stopwatch.stop();
      // Adaptive FPS pacing: pace for the fastest preset in use so low/eco
      // modes alone don't spin at 30fps wasting CPU/battery.
      final targetFps = groups.keys
          .map((p) => p.targetFps)
          .fold<int>(ScreenShareQualityPreset.eco.targetFps, max);
      final targetFrameTimeMs = (1000 / targetFps).round().clamp(20, 50);
      final elapsed = stopwatch.elapsedMilliseconds;
      final waitMs = (targetFrameTimeMs - elapsed).clamp(2, targetFrameTimeMs);
      // Dynamic pacing under network backpressure: if many clients not ready, add extra jitter delay
      final pendingClients = _wsClients.length - readyClients.length;
      final backpressureDelay = pendingClients > 0 ? 4 : 0;
      await Future.delayed(Duration(milliseconds: waitMs + backpressureDelay));
    }
    _loopRunning = false;
  }

  void _publishStatus() {
    if (!_statusController.isClosed) _statusController.add(status);
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}

class ScreenShareStatus {
  final bool isStreaming;
  final bool isAuthorized;
  final String? viewerName;
  final DateTime? lastFrameAt;
  final int clientCount;

  // Backward compatibility getter for existing UI referencing .enabled
  bool get enabled => isStreaming;

  const ScreenShareStatus({
    required this.isStreaming,
    required this.isAuthorized,
    required this.viewerName,
    required this.lastFrameAt,
    this.clientCount = 0,
  });
}
