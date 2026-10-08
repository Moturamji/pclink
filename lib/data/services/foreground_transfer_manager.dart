import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../features/clipboard/services/clipboard_service.dart';
import '../../features/file_share/models/transfer_progress.dart';

/// Coordinates Android Foreground Service lifecycle during active file transfers.
/// Keeps CPU and network awake when the app is minimized or the screen turns off.
class ForegroundTransferManager {
  ForegroundTransferManager._();
  static final ForegroundTransferManager instance =
      ForegroundTransferManager._();

  DateTime _lastNotificationUpdateTime =
      DateTime.fromMillisecondsSinceEpoch(0);
  bool _isTransferForegroundActive = false;
  Timer? _revertTimer;

  bool get isTransferForegroundActive => _isTransferForegroundActive;

  /// Ensures Android Foreground Service is active with WakeLock and WifiLock
  /// as soon as the user selects files and transfers begin.
  Future<void> ensureForegroundActive({String? initialFileName}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    _revertTimer?.cancel();
    _revertTimer = null;

    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      _isTransferForegroundActive = true;

      final title = initialFileName != null
          ? 'Transferring $initialFileName'
          : 'DeskPocket File Transfer';
      const text = 'Starting background transfer...';

      if (!isRunning) {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: title,
          notificationText: text,
          callback: startForegroundTaskCallback,
        );
      } else {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
      }
    } catch (e) {
      debugPrint('ForegroundTransferManager ensureForegroundActive error: $e');
    }
  }

  /// Updates foreground notification with real-time progress metrics.
  /// Throttled to at most once per 500ms to eliminate Android IPC overhead.
  void updateProgress(TransferProgress progress, {int activeCount = 1}) {
    if (kIsWeb || !Platform.isAndroid || !_isTransferForegroundActive) return;

    final now = DateTime.now();
    if (now.difference(_lastNotificationUpdateTime).inMilliseconds < 500) {
      return;
    }
    _lastNotificationUpdateTime = now;

    try {
      final countLabel = activeCount > 1 ? ' ($activeCount active)' : '';
      final title =
          '${progress.isUpload ? 'Sending' : 'Downloading'} ${progress.fileName}$countLabel';
      final text =
          '${progress.percentageLabel} • ${progress.speedLabel} • ${progress.transferredLabel}';

      FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (e) {
      debugPrint('ForegroundTransferManager updateProgress error: $e');
    }
  }

  /// Called when all active transfers are complete, failed, or cancelled.
  /// Displays a brief completion notification, then gracefully reverts to clipboard sync or stops.
  void onTransfersFinished({bool success = true}) {
    if (kIsWeb || !Platform.isAndroid || !_isTransferForegroundActive) return;

    _revertTimer?.cancel();
    try {
      FlutterForegroundTask.updateService(
        notificationTitle:
            success ? 'Transfer Complete' : 'Transfer Stopped',
        notificationText: success
            ? 'All files transferred successfully'
            : 'File transfer stopped or encountered an issue',
      );
    } catch (_) {}

    _revertTimer = Timer(const Duration(seconds: 4), () async {
      _isTransferForegroundActive = false;
      try {
        final isRunning = await FlutterForegroundTask.isRunningService;
        if (isRunning) {
          await FlutterForegroundTask.updateService(
            notificationTitle: 'DeskPocket Live Sync Active',
            notificationText:
                'Tap "Send to PC" to instantly transfer clipboard',
            notificationButtons: [
              const NotificationButton(id: 'sync_now', text: 'Send to PC'),
            ],
          );
        }
      } catch (e) {
        debugPrint('ForegroundTransferManager revert error: $e');
      }
    });
  }
}
