import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_screen_capture/flutter_screen_capture.dart';
import 'package:image/image.dart' as image;

/// Task payload passed to background worker isolate for JPEG encoding.
class _FrameEncodeTask {
  final Uint8List buffer;
  final int width;
  final int height;
  final int bytesPerPixel;
  final int maxWidth;
  final int quality;
  final bool isMacOS;

  const _FrameEncodeTask({
    required this.buffer,
    required this.width,
    required this.height,
    required this.bytesPerPixel,
    required this.maxWidth,
    required this.quality,
    required this.isMacOS,
  });
}

/// Standalone top-level worker for background isolate processing.
/// Never blocks the main Flutter UI thread.
Uint8List _encodeFrameWorker(_FrameEncodeTask task) {
  final img = image.Image.fromBytes(
    width: task.width,
    height: task.height,
    bytes: task.buffer.buffer,
    order: task.isMacOS ? image.ChannelOrder.bgra : image.ChannelOrder.rgba,
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
class ScreenShareQualityPreset {
  final String name;
  final int maxWidth;
  final int jpegQuality;

  const ScreenShareQualityPreset({
    required this.name,
    required this.maxWidth,
    required this.jpegQuality,
  });

  /// Ultra Sharp: 1080p / Native up to 1920px with 85% JPEG quality.
  /// Razor-sharp text, terminal code, and fine desktop UI.
  static const ultra = ScreenShareQualityPreset(
    name: 'ultra',
    maxWidth: 1920,
    jpegQuality: 85,
  );

  /// High / Balanced: 1440px with 78% quality.
  /// High quality with balanced Wi-Fi bandwidth.
  static const high = ScreenShareQualityPreset(
    name: 'high',
    maxWidth: 1440,
    jpegQuality: 78,
  );

  /// Fast / Smooth: 1080px with 70% quality.
  /// Prioritizes maximum framerate on slower networks.
  static const fast = ScreenShareQualityPreset(
    name: 'fast',
    maxWidth: 1080,
    jpegQuality: 70,
  );

  static ScreenShareQualityPreset fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'fast':
        return fast;
      case 'high':
        return high;
      case 'ultra':
      default:
        return ultra;
    }
  }
}

/// Active WebSocket client connection tracking for backpressure and flow control.
class _ScreenShareWsClient {
  final WebSocket socket;
  final String id;
  final String viewerName;
  ScreenShareQualityPreset quality;
  bool isReady = true;
  DateTime connectedAt = DateTime.now();

  _ScreenShareWsClient({
    required this.socket,
    required this.id,
    required this.viewerName,
    required this.quality,
  });
}

/// Windows-only, view-only real-time screen sharing service.
/// Uses background isolate encoding, WebSocket push delivery, and ACK backpressure.
class ScreenShareService {
  static const String _preferenceFileName = 'pclink_screen_share_consent.txt';

  final List<_ScreenShareWsClient> _wsClients = [];
  Timer? _fallbackPollTimer;
  Uint8List? _latestFrame;
  DateTime? _lastFrameAt;
  String? _viewerName;
  bool _isCapturing = false;
  bool _loopRunning = false;

  final StreamController<ScreenShareStatus> _statusController =
      StreamController<ScreenShareStatus>.broadcast();

  Stream<ScreenShareStatus> get statusStream => _statusController.stream;
  ScreenShareStatus get status => ScreenShareStatus(
        enabled: _isCapturing || _wsClients.isNotEmpty,
        viewerName: _viewerName,
        lastFrameAt: _lastFrameAt,
        clientCount: _wsClients.length,
      );

  static String get _appDataDir {
    final appData = Platform.environment['APPDATA'];
    return appData == null || appData.isEmpty ? '.' : '$appData\\pclink';
  }

  static File get _preferenceFile =>
      File('$_appDataDir\\$_preferenceFileName');

  static Future<bool> isConsentGranted() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      return await _preferenceFile.exists() &&
          (await _preferenceFile.readAsString()).trim() == 'enabled';
    } catch (_) {
      return false;
    }
  }

  static Future<void> setConsentGranted(bool granted) async {
    if (kIsWeb || !Platform.isWindows) return;
    final dir = Directory(_appDataDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    await _preferenceFile.writeAsString(granted ? 'enabled' : 'disabled');
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
            client.isReady = true;
          } else if (message.startsWith('quality:')) {
            final qName = message.substring('quality:'.length).trim();
            client.quality = ScreenShareQualityPreset.fromString(qName);
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
  }

  Uint8List? takeLatestFrame() => _latestFrame;

  void _ensureCaptureLoopRunning() {
    if (_loopRunning) return;
    _loopRunning = true;
    _runStreamingLoop();
  }

  ScreenShareQualityPreset _getActivePreset(List<_ScreenShareWsClient> clients) {
    if (clients.isEmpty) return ScreenShareQualityPreset.ultra;
    // If any client asks for ultra, deliver ultra
    if (clients.any((c) => c.quality.name == 'ultra')) {
      return ScreenShareQualityPreset.ultra;
    }
    if (clients.any((c) => c.quality.name == 'high')) {
      return ScreenShareQualityPreset.high;
    }
    return ScreenShareQualityPreset.fast;
  }

  Future<void> _captureFallbackFrame() async {
    if (!_isCapturing || kIsWeb || !Platform.isWindows) return;
    try {
      final area = await ScreenCapture().captureEntireScreen();
      if (area == null || !_isCapturing) return;

      final task = _FrameEncodeTask(
        buffer: area.buffer,
        width: area.width,
        height: area.height,
        bytesPerPixel: area.bytesPerPixel,
        maxWidth: 1920,
        quality: 85,
        isMacOS: Platform.isMacOS,
      );
      _latestFrame = await compute(_encodeFrameWorker, task);
      _lastFrameAt = DateTime.now();
      _publishStatus();
    } catch (e) {
      debugPrint('ScreenShareService fallback capture failed: $e');
    }
  }

  Future<void> _runStreamingLoop() async {
    while (_isCapturing && !kIsWeb && Platform.isWindows) {
      if (_wsClients.isEmpty) {
        // No active WebSocket streams, yield
        await Future.delayed(const Duration(milliseconds: 100));
        if (_wsClients.isEmpty && _fallbackPollTimer == null) {
          break;
        }
        continue;
      }

      final readyClients = _wsClients.where((c) => c.isReady).toList();

      // If all active clients are still decoding/rendering the previous frame,
      // pause briefly instead of capturing redundant frames that would be dropped.
      if (readyClients.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 8));
        continue;
      }

      final stopwatch = Stopwatch()..start();
      try {
        final area = await ScreenCapture().captureEntireScreen();
        if (area != null && _isCapturing && _wsClients.isNotEmpty) {
          final preset = _getActivePreset(readyClients);
          final task = _FrameEncodeTask(
            buffer: area.buffer,
            width: area.width,
            height: area.height,
            bytesPerPixel: area.bytesPerPixel,
            maxWidth: preset.maxWidth,
            quality: preset.jpegQuality,
            isMacOS: Platform.isMacOS,
          );

          final encoded = await compute(_encodeFrameWorker, task);
          _latestFrame = encoded;
          _lastFrameAt = DateTime.now();

          // Push directly down the open WebSocket connection
          for (final client in readyClients) {
            try {
              client.isReady = false; // Mark awaiting ACK from mobile
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
      // Target ~20-25 FPS (45ms per frame)
      final elapsed = stopwatch.elapsedMilliseconds;
      const targetFrameTimeMs = 45;
      final waitMs = (targetFrameTimeMs - elapsed).clamp(5, targetFrameTimeMs);
      await Future.delayed(Duration(milliseconds: waitMs));
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
  final bool enabled;
  final String? viewerName;
  final DateTime? lastFrameAt;
  final int clientCount;

  const ScreenShareStatus({
    required this.enabled,
    required this.viewerName,
    required this.lastFrameAt,
    this.clientCount = 0,
  });
}
