import 'package:flutter/foundation.dart';

/// Metadata for a single file shared through the temporary PCLink server.
///
/// Files travel directly between the Windows PC and the Android phone over the
/// existing temp server (port 8088 / cloudflared tunnel) - they never pass
/// through Firebase. [filePath] is the local path on the Windows shared folder
/// and is intentionally excluded from the metadata sent over the network.
@immutable
class SharedFile {
  final String id;
  final String name;
  final int size;
  final String sourcePlatform; // 'windows' or 'android'
  final String sourceDeviceName;
  final DateTime timestamp;
  final String? filePath;

  const SharedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.sourcePlatform,
    required this.sourceDeviceName,
    required this.timestamp,
    this.filePath,
  });

  bool get isFromWindows => sourcePlatform.toLowerCase() == 'windows';
  bool get isFromAndroid => sourcePlatform.toLowerCase() == 'android';

  /// Human friendly size string, e.g. "1.4 MB".
  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Serialized for the wire / phone. Local server paths are never exposed.
  Map<String, dynamic> toMap({bool includePath = false}) {
    return {
      'id': id,
      'name': name,
      'size': size,
      'sourcePlatform': sourcePlatform,
      'sourceDeviceName': sourceDeviceName,
      'timestamp': timestamp.toIso8601String(),
      if (includePath && filePath != null) 'filePath': filePath,
    };
  }

  factory SharedFile.fromMap(Map<dynamic, dynamic> map) {
    return SharedFile(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'unnamed',
      size: (map['size'] as num?)?.toInt() ?? 0,
      sourcePlatform: map['sourcePlatform']?.toString() ?? 'unknown',
      sourceDeviceName: map['sourceDeviceName']?.toString() ?? 'Device',
      timestamp:
          DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      filePath: map['filePath']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SharedFile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          size == other.size &&
          sourcePlatform == other.sourcePlatform &&
          sourceDeviceName == other.sourceDeviceName;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      size.hashCode ^
      sourcePlatform.hashCode ^
      sourceDeviceName.hashCode;
}
