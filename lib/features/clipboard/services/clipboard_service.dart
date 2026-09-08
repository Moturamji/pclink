import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../data/services/database_service.dart';
import '../models/clipboard_item.dart';

/// Manages continuous background system clipboard monitoring and bidirectional synchronization.
class ClipboardService {
  Timer? _clipboardPollTimer;
  StreamSubscription<List<ClipboardItem>>? _remoteSub;

  String? _lastLocalText;
  String? _lastReceivedRemoteText;
  bool isAutoSyncEnabled = true;

  bool get isListening => _clipboardPollTimer != null;

  /// Starts background clipboard polling and remote stream listening.
  void startListening({
    required User user,
    required String deviceName,
    required bool isWindows,
    required DatabaseService databaseService,
    Function(ClipboardItem)? onNewRemoteClipReceived,
  }) {
    if (_clipboardPollTimer != null) return;

    final platformName = isWindows ? 'windows' : 'android';

    // 1. Poll local system clipboard
    _clipboardPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      await _checkLocalClipboard(
        user: user,
        deviceName: deviceName,
        platformName: platformName,
        databaseService: databaseService,
      );
    });

    // 2. Listen to incoming remote clips
    _remoteSub = databaseService.watchClipboardItems(user).listen((items) async {
      if (items.isEmpty) return;
      final latest = items.first;

      // Only process clips from the other platform
      if (latest.sourcePlatform != platformName && latest.text != _lastReceivedRemoteText) {
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

    debugPrint('ClipboardService: Started clipboard listener for $platformName ($deviceName)');
  }

  Future<void> _checkLocalClipboard({
    required User user,
    required String deviceName,
    required String platformName,
    required DatabaseService databaseService,
  }) async {
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
        sourcePlatform: platformName,
        sourceDeviceName: deviceName,
        timestamp: DateTime.now(),
      );

      await databaseService.pushClipboardItem(
        user: user,
        item: item,
      );

      debugPrint('ClipboardService: Uploaded new local clip to RTDB (${item.charCount} chars)');
    } catch (e) {
      debugPrint('ClipboardService check error: $e');
    }
  }

  /// Stops clipboard listener.
  void stopListening() {
    _clipboardPollTimer?.cancel();
    _clipboardPollTimer = null;
    _remoteSub?.cancel();
    _remoteSub = null;
  }

  void dispose() {
    stopListening();
  }
}
