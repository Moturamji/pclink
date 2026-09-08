import 'package:flutter/foundation.dart';

/// Represents a synchronized clipboard text snippet across Android and Windows.
@immutable
class ClipboardItem {
  final String id;
  final String text;
  final String sourcePlatform; // 'windows' or 'android'
  final String sourceDeviceName;
  final DateTime timestamp;

  const ClipboardItem({
    required this.id,
    required this.text,
    required this.sourcePlatform,
    required this.sourceDeviceName,
    required this.timestamp,
  });

  bool get isFromWindows => sourcePlatform.toLowerCase() == 'windows';
  bool get isFromAndroid => sourcePlatform.toLowerCase() == 'android';

  int get charCount => text.length;
  int get lineCount => '\n'.allMatches(text).length + 1;

  String get previewText {
    final singleLine = text.replaceAll('\n', ' ').trim();
    if (singleLine.length > 80) {
      return '${singleLine.substring(0, 80)}...';
    }
    return singleLine;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'sourcePlatform': sourcePlatform,
      'sourceDeviceName': sourceDeviceName,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ClipboardItem.fromMap(Map<dynamic, dynamic> map) {
    return ClipboardItem(
      id: map['id']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      sourcePlatform: map['sourcePlatform']?.toString() ?? 'unknown',
      sourceDeviceName: map['sourceDeviceName']?.toString() ?? 'Device',
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipboardItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          sourcePlatform == other.sourcePlatform &&
          sourceDeviceName == other.sourceDeviceName;

  @override
  int get hashCode =>
      id.hashCode ^
      text.hashCode ^
      sourcePlatform.hashCode ^
      sourceDeviceName.hashCode;
}
