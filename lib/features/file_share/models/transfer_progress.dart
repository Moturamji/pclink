import 'package:flutter/foundation.dart';

enum TransferStatus {
  idle,
  preparing,
  inProgress,
  completed,
  failed,
  cancelled,
}

/// Reactive model representing real-time file transfer progress, throughput, and status.
@immutable
class TransferProgress {
  final String fileId;
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;
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
    this.speedBytesPerSec = 0.0,
    required this.isUpload,
    this.status = TransferStatus.inProgress,
    this.errorMessage,
    required this.timestamp,
  });

  /// Real-time progress fraction from 0.0 to 1.0.
  double get fraction {
    if (totalBytes <= 0) return 0.0;
    return (bytesTransferred / totalBytes).clamp(0.0, 1.0);
  }

  /// Percentage string (e.g., "45.2%").
  String get percentageLabel {
    return '${(fraction * 100).toStringAsFixed(1)}%';
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
    if (speedBytesPerSec <= 0 || status != TransferStatus.inProgress) {
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
    if (status == TransferStatus.failed) return 'Failed';
    if (status == TransferStatus.cancelled) return 'Cancelled';
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
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      isUpload: isUpload ?? this.isUpload,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
