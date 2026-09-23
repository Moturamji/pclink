import 'package:flutter/foundation.dart';

enum TransferStatus {
  idle,
  queued,
  preparing,
  connecting,
  transferring,
  inProgress, // retained for backward compatibility (equivalent to transferring)
  finalizing,
  verifying,
  completed,
  failed,
  cancelled,
  paused,
  resuming,
}

/// Enforces valid state transitions and protects terminal transfer states.
class TransferStateMachine {
  static const Map<TransferStatus, Set<TransferStatus>> _validTransitions = {
    TransferStatus.idle: {
      TransferStatus.queued,
      TransferStatus.preparing,
      TransferStatus.connecting,
      TransferStatus.cancelled,
    },
    TransferStatus.queued: {
      TransferStatus.preparing,
      TransferStatus.connecting,
      TransferStatus.resuming,
      TransferStatus.transferring,
      TransferStatus.inProgress,
      TransferStatus.paused,
      TransferStatus.failed,
      TransferStatus.cancelled,
    },
    TransferStatus.preparing: {
      TransferStatus.connecting,
      TransferStatus.resuming,
      TransferStatus.transferring,
      TransferStatus.inProgress,
      TransferStatus.failed,
      TransferStatus.cancelled,
    },
    TransferStatus.connecting: {
      TransferStatus.resuming,
      TransferStatus.transferring,
      TransferStatus.inProgress,
      TransferStatus.failed,
      TransferStatus.cancelled,
    },
    TransferStatus.resuming: {
      TransferStatus.transferring,
      TransferStatus.inProgress,
      TransferStatus.verifying,
      TransferStatus.finalizing,
      TransferStatus.completed,
      TransferStatus.failed,
      TransferStatus.cancelled,
    },
    TransferStatus.transferring: {
      TransferStatus.inProgress,
      TransferStatus.verifying,
      TransferStatus.finalizing,
      TransferStatus.completed,
      TransferStatus.failed,
      TransferStatus.cancelled,
      TransferStatus.paused,
    },
    TransferStatus.inProgress: {
      TransferStatus.transferring,
      TransferStatus.verifying,
      TransferStatus.finalizing,
      TransferStatus.completed,
      TransferStatus.failed,
      TransferStatus.cancelled,
      TransferStatus.paused,
    },
    TransferStatus.paused: {
      TransferStatus.resuming,
      TransferStatus.transferring,
      TransferStatus.inProgress,
      TransferStatus.cancelled,
      TransferStatus.failed,
    },
    TransferStatus.verifying: {
      // A retry on another route restarts the byte stream after a lost
      // confirmation, so these are legal forward/restart transitions.
      TransferStatus.transferring,
      TransferStatus.inProgress,
      TransferStatus.resuming,
      TransferStatus.finalizing,
      TransferStatus.completed,
      TransferStatus.failed,
      TransferStatus.cancelled,
    },
    TransferStatus.finalizing: {
      TransferStatus.completed,
      TransferStatus.failed,
      TransferStatus.cancelled,
    },
    // Terminal states: once terminal, no further transitions
    TransferStatus.completed: {},
    TransferStatus.failed: {},
    TransferStatus.cancelled: {},
  };

  static bool isValidTransition(TransferStatus from, TransferStatus to) {
    if (from == to) return true;
    final allowed = _validTransitions[from];
    return allowed != null && allowed.contains(to);
  }

  final String? fileId;
  TransferStatus _status;

  TransferStateMachine([this.fileId, TransferStatus initialStatus = TransferStatus.preparing])
      : _status = initialStatus;

  TransferStatus get currentStatus => _status;

  bool canTransitionTo(TransferStatus target) => isValidTransition(_status, target);

  bool transition(TransferStatus target) {
    if (canTransitionTo(target)) {
      _status = target;
      return true;
    }
    return false;
  }
}

/// Reactive model representing real-time file transfer progress, throughput, and status.
@immutable
class TransferProgress {
  final String fileId;
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;
  final int senderBytes;
  final int receiverBytes;
  final double speedBytesPerSec;
  final bool isUpload;
  final TransferStatus status;
  final String? errorMessage;
  final DateTime timestamp;

  const TransferProgress({
    required this.fileId,
    required this.fileName,
    required this.bytesTransferred,
    required this.totalBytes,
    int? senderBytes,
    int? receiverBytes,
    this.speedBytesPerSec = 0.0,
    required this.isUpload,
    this.status = TransferStatus.inProgress,
    this.errorMessage,
    required this.timestamp,
  })  : senderBytes = senderBytes ?? bytesTransferred,
        receiverBytes = receiverBytes ?? bytesTransferred;

  /// True if the transfer is currently running (not terminal or paused).
  bool get isActive =>
      status == TransferStatus.queued ||
      status == TransferStatus.preparing ||
      status == TransferStatus.connecting ||
      status == TransferStatus.transferring ||
      status == TransferStatus.inProgress ||
      status == TransferStatus.finalizing ||
      status == TransferStatus.verifying ||
      status == TransferStatus.resuming;

  /// True if the transfer has reached a terminal state.
  bool get isTerminal =>
      status == TransferStatus.completed ||
      status == TransferStatus.failed ||
      status == TransferStatus.cancelled;

  /// Real-time progress fraction from 0.0 to 1.0.
  /// Strictly clamped to 0.99 prior to `completed` so 100% is never faked.
  double get fraction {
    if (totalBytes <= 0) return 0.0;
    if (status == TransferStatus.completed) return 1.0;
    final raw = bytesTransferred / totalBytes;
    return raw.clamp(0.0, 0.99);
  }

  /// Real-time sender progress fraction from 0.0 to 1.0.
  double get senderFraction {
    if (totalBytes <= 0) return 0.0;
    if (status == TransferStatus.completed) return 1.0;
    final raw = senderBytes / totalBytes;
    return raw.clamp(0.0, 0.99);
  }

  /// Real-time receiver progress fraction from 0.0 to 1.0.
  double get receiverFraction {
    if (totalBytes <= 0) return 0.0;
    if (status == TransferStatus.completed) return 1.0;
    final raw = receiverBytes / totalBytes;
    return raw.clamp(0.0, 0.99);
  }

  /// Percentage label for the sender's transmission progress.
  String get senderPercentageLabel {
    if (status == TransferStatus.completed) return '100%';
    final pct = (senderFraction * 100).clamp(0.0, 99.0);
    return '${pct.toStringAsFixed(1)}%';
  }

  /// Percentage label for the receiver's confirmed progress.
  String get receiverPercentageLabel {
    if (status == TransferStatus.completed) return '100%';
    final pct = (receiverFraction * 100).clamp(0.0, 99.0);
    return '${pct.toStringAsFixed(1)}%';
  }

  /// Percentage or status string. Displays 100% only when truly completed.
  String get percentageLabel {
    if (status == TransferStatus.completed) return '100%';
    if (status == TransferStatus.queued) return 'Queued';
    if (status == TransferStatus.verifying) return 'Verifying...';
    if (status == TransferStatus.finalizing) return 'Finalizing...';
    if (status == TransferStatus.connecting) return 'Connecting...';
    if (status == TransferStatus.preparing) return 'Preparing...';
    if (status == TransferStatus.resuming) return 'Resuming...';
    if (status == TransferStatus.paused) return 'Paused';
    if (status == TransferStatus.failed) return 'Failed';
    if (status == TransferStatus.cancelled) return 'Cancelled';
    final pct = (fraction * 100).clamp(0.0, 99.0);
    return '${pct.toStringAsFixed(1)}%';
  }

  /// Remaining bytes to transfer.
  int get remainingBytes {
    final rem = totalBytes - bytesTransferred;
    return rem < 0 ? 0 : rem;
  }

  /// Human-readable transferred / total size (e.g., "4.2 MB / 10.5 MB").
  String get transferredLabel {
    return '${formatBytes(bytesTransferred)} / ${formatBytes(totalBytes)}';
  }

  /// Human-readable transfer speed (e.g., "2.4 MB/s" or "320 KB/s").
  String get speedLabel {
    final active = status == TransferStatus.inProgress ||
        status == TransferStatus.transferring ||
        status == TransferStatus.resuming;
    if (speedBytesPerSec <= 0 || !active) {
      return '-- KB/s';
    }
    if (speedBytesPerSec >= 1024 * 1024) {
      return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    if (speedBytesPerSec >= 1024) {
      return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${speedBytesPerSec.toStringAsFixed(0)} B/s';
  }

  /// Estimated time remaining or remaining bytes label.
  String get remainingLabel {
    if (status == TransferStatus.completed) return 'Completed';
    if (status == TransferStatus.queued) return 'Queued...';
    if (status == TransferStatus.finalizing) return 'Finalizing file...';
    if (status == TransferStatus.verifying) return 'Verifying integrity...';
    if (status == TransferStatus.connecting) return 'Connecting...';
    if (status == TransferStatus.preparing) return 'Preparing...';
    if (status == TransferStatus.resuming) return 'Resuming...';
    if (status == TransferStatus.failed) return errorMessage ?? 'Failed';
    if (status == TransferStatus.cancelled) return 'Cancelled';
    if (status == TransferStatus.paused) return 'Paused';
    if (speedBytesPerSec > 0 && remainingBytes > 0) {
      final secondsLeft = (remainingBytes / speedBytesPerSec).round();
      if (secondsLeft < 60) {
        return '$secondsLeft sec remaining';
      }
      final mins = secondsLeft ~/ 60;
      final secs = secondsLeft % 60;
      return '$mins min ${secs > 0 ? '$secs sec ' : ''}remaining';
    }
    return '${formatBytes(remainingBytes)} left';
  }

  /// Formats byte count into human-readable representation.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  TransferProgress copyWith({
    String? fileId,
    String? fileName,
    int? bytesTransferred,
    int? totalBytes,
    int? senderBytes,
    int? receiverBytes,
    double? speedBytesPerSec,
    bool? isUpload,
    TransferStatus? status,
    String? errorMessage,
    DateTime? timestamp,
  }) {
    return TransferProgress(
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      senderBytes: senderBytes ?? this.senderBytes,
      receiverBytes: receiverBytes ?? this.receiverBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      isUpload: isUpload ?? this.isUpload,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Wire representation used by the authenticated PC progress feed.
  Map<String, Object?> toMap() => {
        'fileId': fileId,
        'fileName': fileName,
        'bytesTransferred': bytesTransferred,
        'totalBytes': totalBytes,
        'senderBytes': senderBytes,
        'receiverBytes': receiverBytes,
        'speedBytesPerSec': speedBytesPerSec,
        'isUpload': isUpload,
        'status': status.name,
        'errorMessage': errorMessage,
        'timestamp': timestamp.toIso8601String(),
      };

  static TransferProgress? tryFromMap(Map<dynamic, dynamic> map) {
    final statusName = map['status'];
    if (statusName is! String) return null;
    final status = TransferStatus.values.where((value) => value.name == statusName);
    if (status.isEmpty) return null;
    final fileId = map['fileId'];
    final fileName = map['fileName'];
    final bytesTransferred = map['bytesTransferred'];
    final totalBytes = map['totalBytes'];
    final timestamp = map['timestamp'];
    if (fileId is! String ||
        fileName is! String ||
        bytesTransferred is! num ||
        totalBytes is! num ||
        timestamp is! String) {
      return null;
    }
    final parsedTimestamp = DateTime.tryParse(timestamp);
    if (parsedTimestamp == null) return null;
    final transferred = bytesTransferred.toInt();
    return TransferProgress(
      fileId: fileId,
      fileName: fileName,
      bytesTransferred: transferred,
      totalBytes: totalBytes.toInt(),
      senderBytes: (map['senderBytes'] as num?)?.toInt() ?? transferred,
      receiverBytes: (map['receiverBytes'] as num?)?.toInt() ?? transferred,
      speedBytesPerSec: (map['speedBytesPerSec'] as num?)?.toDouble() ?? 0,
      isUpload: map['isUpload'] == true,
      status: status.first,
      errorMessage: map['errorMessage'] as String?,
      timestamp: parsedTimestamp,
    );
  }
}
