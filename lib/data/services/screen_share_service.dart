import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screen_capture/flutter_screen_capture.dart';
import 'package:image/image.dart' as image;
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
  final bpp = task.bytesPerPixel > 0 ? task.bytesPerPixel : 4;
  // CoreGraphics pads each row (bytesPerRow > width * bpp). Derive the real
  // stride from the buffer size, otherwise rows are skewed or fromBytes throws.
  final packedStride = task.width * bpp;
  final derivedStride =
      task.height > 0 ? task.buffer.lengthInBytes ~/ task.height : packedStride;
  final rowStride = derivedStride >= packedStride ? derivedStride : packedStride;
  final img = image.Image.fromBytes(
    width: task.width,
    height: task.height,
    bytes: task.buffer.buffer,
    bytesOffset: task.buffer.offsetInBytes,
    rowStride: rowStride,
    numChannels: bpp,
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
  /// Frames sent but not yet acknowledged. The phone acks a frame only once
  /// it has been decoded and shown (or dropped as stale), so this is real
  /// end-to-end backpressure.
  final List<DateTime> inFlightSentAt = [];
  DateTime lastSentAt = DateTime.now();
  DateTime connectedAt = DateTime.now();

  /// Capture sequence of the last frame sent (macOS only; null on Windows).
  /// Lets the loop skip re-sending an unchanged screen.
  int? lastSentSeq;
  DateTime lastRttReportAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Max unacknowledged frames. 1 would cap FPS at 1/RTT on a slow tunnel;
  /// unlimited (the old 160 ms timeout) let frames queue up so the picture
  /// lagged seconds behind. 2 keeps both throughput and freshness.
  static const int maxInFlight = 2;

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

  /// Ready when fewer than [maxInFlight] frames are unacknowledged. If the
  /// oldest has waited > 1.5 s the acks are presumed lost and the window resets
  /// (prevents a permanent 0 FPS stall).
  bool get isReadyOrTimedOut {
    if (inFlightSentAt.length < maxInFlight) return true;
    if (DateTime.now().difference(inFlightSentAt.first).inMilliseconds > 1500) {
      inFlightSentAt.clear();
      return true;
    }
    return false;
  }

  bool get canAdaptNow =>
      DateTime.now().difference(lastAdaptiveChangeAt).inMilliseconds > 2500;
}

/// Windows-only, view-only real-time screen sharing service.
/// Uses native Win32 GDI + GDI+ SIMD hardware compression with isolate fallback,
/// WebSocket push delivery, and ACK backpressure with timeout watchdog.
class ScreenShareService {
  static const String _preferenceFileName = 'pclink_screen_share_consent.txt';
  static const MethodChannel _nativeChannel =
      MethodChannel('pclink/native_screen_share');

  static ScreenShareService? _activeInstance;
  static final ValueNotifier<bool> consentNotifier = ValueNotifier<bool>(false);

  /// OS-level screen capture permission (macOS Screen Recording).
  /// `null` = not checked yet / not applicable (Windows needs no permission),
  /// `true` = granted, `false` = missing. Drives the permission banner/dialog.
  static final ValueNotifier<bool?> osPermissionNotifier =
      ValueNotifier<bool?>(null);

  /// Name of the app macOS holds responsible for DeskPocket's permissions when
  /// it is not DeskPocket itself (e.g. "Antigravity IDE" or "Visual Studio
  /// Code" when started via `flutter run` from an IDE). `null` = DeskPocket.
  static final ValueNotifier<String?> osPermissionResponsibleApp =
      ValueNotifier<String?>(null);

  /// Text message sent to viewers when frames cannot be captured because the
  /// host is missing OS screen-recording permission.
  static const String permissionErrorMessage = 'error:screen_permission';

  /// True on hosts where screen capture needs an OS permission (macOS).
  static bool get requiresOsPermission => !kIsWeb && Platform.isMacOS;

  /// Checks the OS screen-recording permission without prompting.
  static Future<bool> checkOsPermission() async {
    if (!requiresOsPermission) return true;
    try {
      final info = await _nativeChannel
          .invokeMapMethod<String, dynamic>('permissionInfo');
      final granted = info?['granted'] == true;
      final isSelf = info?['responsibleIsSelf'] != false;
      osPermissionResponsibleApp.value =
          isSelf ? null : (info?['responsibleApp'] as String? ?? 'another app');
      osPermissionNotifier.value = granted;
      return granted;
    } catch (_) {
      return osPermissionNotifier.value ?? true;
    }
  }

  /// Shows the macOS Screen Recording prompt (macOS only shows it once per
  /// app; after a denial use [openOsPermissionSettings]).
  static Future<bool> requestOsPermission() async {
    if (!requiresOsPermission) return true;
    try {
      final granted =
          await _nativeChannel.invokeMethod<bool>('requestPermission') ?? false;
      osPermissionNotifier.value = granted;
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Opens System Settings > Privacy & Security > Screen Recording.
  static Future<bool> openOsPermissionSettings() async {
    if (!requiresOsPermission) return false;
    try {
      return await _nativeChannel.invokeMethod<bool>('openPermissionSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Relaunches the app; macOS applies a new Screen Recording grant only to a
  /// freshly started process.
  static Future<void> relaunchApp() async {
    if (!requiresOsPermission) return;
    try {
      await _nativeChannel.invokeMethod<bool>('relaunchApp');
    } catch (_) {}
  }

  final List<_ScreenShareWsClient> _wsClients = [];
  Timer? _fallbackPollTimer;
  Uint8List? _latestFrame;
  DateTime? _lastFrameAt;
  String? _viewerName;
  bool _isCapturing = false;
  bool _loopRunning = false;
  bool _useNativeCapture = true;
  DateTime? _lastPermissionWarningAt;
  DateTime? _lastPermissionNoticeSentAt;

  /// Sequence number of the last captured frame (macOS). Unchanged sequence =
  /// unchanged screen content.
  int? _lastCaptureSeq;

  /// Last capture error that the viewer should know about (e.g. macOS Screen
  /// Recording permission missing). Null when frames are flowing.
  String? lastCaptureError;

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
        permissionMissing: osPermissionNotifier.value == false,
      );

  static String get _appDataDir {
    if (isFlutterTest) return testSandboxDir.path;
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
    if (!granted) {
      await _activeInstance?.stop();
    } else if (requiresOsPermission && !await checkOsPermission()) {
      // Ask for Screen Recording right when the user turns sharing on, while
      // they are looking at the Mac, instead of when the phone first connects.
      await requestOsPermission();
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
            final now = DateTime.now();
            final sentAt = client.inFlightSentAt.isNotEmpty
                ? client.inFlightSentAt.removeAt(0)
                : client.lastSentAt;
            // Round trip: send -> phone decodes & shows -> ack received.
            final rtt = now.difference(sentAt).inMilliseconds;
            client.lastRttMs = rtt;
            if (now.difference(client.lastRttReportAt).inMilliseconds >= 1000) {
              client.lastRttReportAt = now;
              try {
                socket.add('rtt:$rtt');
              } catch (_) {}
            }
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
                // Only upgrade if below requested cap
                final capIdx = ScreenShareQualityPreset.ordered.indexWhere((p) => p.name == client.requestedQuality.name);
                final curIdx = ScreenShareQualityPreset.ordered.indexWhere((p) => p.name == client.quality.name);
                if (curIdx > capIdx) {
                  // already below cap; allow step up but not beyond cap
                }
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
        client.socket.close();
      } catch (_) {}
    }

    _latestFrame = null;
    _lastFrameAt = null;
    _publishStatus();
    _stopNativeCapture();
  }

  /// macOS: stop ScreenCaptureKit right away (it also auto-stops when idle).
  void _stopNativeCapture() {
    if (!requiresOsPermission) return;
    _nativeChannel.invokeMethod<bool>('stopCapture').catchError((_) => false);
  }

  Uint8List? takeLatestFrame() => _latestFrame;

  void _ensureCaptureLoopRunning() {
    if (_loopRunning) return;
    _loopRunning = true;
    _runStreamingLoop();
  }

  ScreenShareQualityPreset _getActivePreset(List<_ScreenShareWsClient> clients) {
    if (clients.isEmpty) return ScreenShareQualityPreset.ultra;
    // Pick the most demanding (highest) quality among ready clients; ensures
    // adaptive downgrades only affect slow clients when that client is the sole bottleneck.
    // We choose the *minimum* index (highest quality) across clients.
    var bestIdx = ScreenShareQualityPreset.ordered.length;
    for (final c in clients) {
      final idx = ScreenShareQualityPreset.ordered.indexWhere((p) => p.name == c.quality.name);
      if (idx != -1 && idx < bestIdx) bestIdx = idx;
    }
    if (bestIdx >= ScreenShareQualityPreset.ordered.length) return ScreenShareQualityPreset.ultra;
    // If multiple clients, serve the lowest-common denominator to avoid starving slow link
    // Actually take the *worst* (max idx) among ready clients to protect low-bandwidth clients.
    var worstIdx = -1;
    for (final c in clients) {
      final idx = ScreenShareQualityPreset.ordered.indexWhere((p) => p.name == c.quality.name);
      if (idx > worstIdx) worstIdx = idx;
    }
    // Use majority-safe: weighted toward worst but bounded — if one ultra and one eco, serve high as compromise
    // Simple: if any eco/low, cap at fast to keep eco viewable without killing ultra viewer's experience entirely
    // For now, respect worst client (prevents buffer bloat on slow link)
    return ScreenShareQualityPreset.ordered[worstIdx];
  }

  /// High-performance screen capture: uses native Win32 GDI + GDI+ SIMD encoder
  /// when available (< 6ms, < 1% CPU, 100% color accurate), with isolate fallback.
  Future<Uint8List?> _captureFrame({
    required int maxWidth,
    required int quality,
  }) async {
    if (!_isCapturing || kIsWeb || !isDesktopHost) return null;

    // 1. Native capture: Windows GDI + GDI+ (native_screen_share.cpp) or
    //    macOS CoreGraphics + ImageIO (MainFlutterWindow.swift).
    if ((Platform.isWindows || Platform.isMacOS) && _useNativeCapture) {
      try {
        final raw = await _nativeChannel.invokeMethod<Object>(
          'captureFrame',
          <String, dynamic>{'maxWidth': maxWidth, 'quality': quality},
        );
        Uint8List? result;
        if (raw is Uint8List) {
          result = raw; // Windows
          _lastCaptureSeq = null;
        } else if (raw is Map) {
          result = raw['jpeg'] as Uint8List?; // macOS: {jpeg, seq}
          _lastCaptureSeq = (raw['seq'] as num?)?.toInt();
        }
        if (result != null && result.isNotEmpty) {
          lastCaptureError = null;
          if (requiresOsPermission && osPermissionNotifier.value != true) {
            osPermissionNotifier.value = true;
            _publishStatus();
          }
          return result;
        }
      } on PlatformException catch (e) {
        if (e.code == 'PERMISSION_DENIED') {
          // macOS Screen Recording permission missing. The plugin fallback
          // would only capture the wallpaper, so don't fall back: keep
          // retrying natively so streaming starts once access is granted.
          lastCaptureError = e.message;
          final details = e.details;
          if (details is Map && details['responsibleIsSelf'] == false) {
            osPermissionResponsibleApp.value =
                details['responsibleApp'] as String? ?? 'another app';
          }
          if (osPermissionNotifier.value != false) {
            osPermissionNotifier.value = false;
            _publishStatus();
          }
          _notifyViewersPermissionMissing();
          final now = DateTime.now();
          if (_lastPermissionWarningAt == null ||
              now.difference(_lastPermissionWarningAt!).inSeconds > 10) {
            _lastPermissionWarningAt = now;
            debugPrint('ScreenShareService: ${e.message}');
          }
          await Future.delayed(const Duration(milliseconds: 500));
          return null;
        }
        if (Platform.isMacOS && e.code == 'NO_FRAME') {
          // ScreenCaptureKit is starting up; first frame arrives shortly.
          await Future.delayed(const Duration(milliseconds: 30));
          return null;
        }
        if (Platform.isMacOS && e.code == 'CAPTURE_FAILED') {
          // Transient (e.g. display asleep / switching). Try again shortly.
          debugPrint('ScreenShareService: native capture failed: ${e.message}');
          await Future.delayed(const Duration(milliseconds: 250));
          return null;
        }
        if (Platform.isMacOS) {
          // Never fall back to flutter_screen_capture on macOS: it uses the
          // obsolete full-resolution CGWindowListCreateImage path (~5 fps on a
          // Retina iMac) and silently returns only the wallpaper and this
          // app's own window when permission is missing.
          debugPrint('ScreenShareService: native capture error: $e');
          await Future.delayed(const Duration(milliseconds: 250));
          return null;
        }
        debugPrint(
            'ScreenShareService: Native capture unavailable, falling back to isolate: $e');
        _useNativeCapture = false;
      } on MissingPluginException catch (e) {
        debugPrint(
            'ScreenShareService: Native capture unavailable, falling back to isolate: $e');
        _useNativeCapture = false;
      } catch (e) {
        debugPrint(
            'ScreenShareService: Native capture unavailable, falling back to isolate: $e');
        _useNativeCapture = false;
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

  bool _fallbackCaptureInFlight = false;

  /// Feeds the HTTP polling endpoint (/frame) for phones without WebSocket.
  ///
  /// Previously this ran every 100 ms with no in-flight guard and kept running
  /// after the phone switched to the WebSocket stream. Fast on Windows GDI
  /// (~6 ms), but on macOS each capture took ~170 ms, so calls piled up behind
  /// each other and competed with the WebSocket loop: frames stalled to 0 fps
  /// and arrived in bursts of 2-4 fps.
  Future<void> _captureFallbackFrame() async {
    if (!_isCapturing || kIsWeb || !isDesktopHost) return;
    // The WebSocket loop already refreshes _latestFrame for /frame.
    if (_wsClients.isNotEmpty) return;
    if (_fallbackCaptureInFlight) return;
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
      try {
        final preset = _getActivePreset(readyClients);
        final encoded = await _captureFrame(
          maxWidth: preset.maxWidth,
          quality: preset.jpegQuality,
        );

        if (encoded != null && _isCapturing && _wsClients.isNotEmpty) {
          _latestFrame = encoded;
          _lastFrameAt = DateTime.now();

          final now = DateTime.now();
          final seq = _lastCaptureSeq;
          for (final client in readyClients) {
            // Unchanged screen (macOS): don't resend the identical ~200 KB
            // frame every 33 ms - that flooded the link and delayed real
            // updates. Send a refresh once per second instead.
            if (seq != null &&
                seq == client.lastSentSeq &&
                now.difference(client.lastSentAt).inMilliseconds < 1000) {
              continue;
            }
            try {
              client.inFlightSentAt.add(now);
              client.lastSentAt = now;
              client.lastSentSeq = seq;
              client.socket.add(encoded);
            } catch (e) {
              _removeClient(client);
            }
          }

          _publishStatus();
        }
      } catch (e) {
        debugPrint('ScreenShareService stream capture error: $e');
      }

      stopwatch.stop();
      // Adaptive FPS pacing: use preset targetFps so low/eco modes don't spin at 30fps wasting CPU/battery
      final targetFps = _getActivePreset(readyClients).targetFps;
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

  /// Tells connected phones why no frames arrive, so they can show a
  /// permission message instead of spinning on "Connecting" forever.
  void _notifyViewersPermissionMissing() {
    final now = DateTime.now();
    if (_lastPermissionNoticeSentAt != null &&
        now.difference(_lastPermissionNoticeSentAt!).inSeconds < 2) {
      return;
    }
    _lastPermissionNoticeSentAt = now;
    for (final client in List<_ScreenShareWsClient>.from(_wsClients)) {
      try {
        client.socket.add(permissionErrorMessage);
      } catch (_) {}
    }
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

  /// The host is connected to a viewer but cannot capture frames because the
  /// OS screen-recording permission is missing (macOS).
  final bool permissionMissing;

  // Backward compatibility getter for existing UI referencing .enabled
  bool get enabled => isStreaming;

  const ScreenShareStatus({
    required this.isStreaming,
    required this.isAuthorized,
    required this.viewerName,
    required this.lastFrameAt,
    this.clientCount = 0,
    this.permissionMissing = false,
  });
}
