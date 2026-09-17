import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_screen_capture/flutter_screen_capture.dart';
import 'package:image/image.dart' as image;

/// Windows-only, view-only screen sharing. Frames stay in memory and are
/// captured only while an authenticated phone has an active session.
class ScreenShareService {
  static const String _preferenceFileName = 'pclink_screen_share_consent.txt';

  Timer? _captureTimer;
  Uint8List? _latestFrame;
  DateTime? _lastFrameAt;
  String? _viewerName;
  bool _isCapturing = false;
  bool _captureInFlight = false;

  final StreamController<ScreenShareStatus> _statusController =
      StreamController<ScreenShareStatus>.broadcast();

  Stream<ScreenShareStatus> get statusStream => _statusController.stream;
  ScreenShareStatus get status => ScreenShareStatus(
        enabled: _isCapturing,
        viewerName: _viewerName,
        lastFrameAt: _lastFrameAt,
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

  Future<bool> start({required String viewerName}) async {
    if (!await isConsentGranted()) return false;
    _viewerName = viewerName;
    if (_isCapturing) {
      _publishStatus();
      return true;
    }
    _isCapturing = true;
    _publishStatus();
    await _captureFrame();
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _captureFrame(),
    );
    return true;
  }

  Future<void> stop() async {
    _captureTimer?.cancel();
    _captureTimer = null;
    _isCapturing = false;
    _viewerName = null;
    _latestFrame = null;
    _lastFrameAt = null;
    _publishStatus();
  }

  Uint8List? takeLatestFrame() => _latestFrame;

  Future<void> _captureFrame() async {
    if (!_isCapturing || _captureInFlight || kIsWeb || !Platform.isWindows) {
      return;
    }
    _captureInFlight = true;
    try {
      final area = await ScreenCapture().captureEntireScreen();
      if (area == null || !_isCapturing) return;
      final source = area.toImage();
      // 960px JPEG frames balance readable remote viewing with safe CPU and
      // network use. The service deliberately does not write frames to disk.
      final resized = source.width > 960
          ? image.copyResize(source, width: 960)
          : source;
      _latestFrame = Uint8List.fromList(image.encodeJpg(resized, quality: 60));
      _lastFrameAt = DateTime.now();
      _publishStatus();
    } catch (e) {
      debugPrint('ScreenShareService: capture failed: $e');
    } finally {
      _captureInFlight = false;
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
  final bool enabled;
  final String? viewerName;
  final DateTime? lastFrameAt;

  const ScreenShareStatus({
    required this.enabled,
    required this.viewerName,
    required this.lastFrameAt,
  });
}
