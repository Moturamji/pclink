import 'package:flutter/foundation.dart';

/// Immutable model representing the status and address of the local Windows server.
@immutable
class ServerInfo {
  final bool isLive;
  final String ipAddress;
  final int port;
  final String url;
  final DateTime? startedAt;
  final DateTime? lastHeartbeat;
  final String? connectedClientId;

  const ServerInfo({
    required this.isLive,
    required this.ipAddress,
    required this.port,
    required this.url,
    this.startedAt,
    this.lastHeartbeat,
    this.connectedClientId,
  });

  factory ServerInfo.fromMap(Map<dynamic, dynamic> map) {
    DateTime? parseDate(dynamic val) {
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return ServerInfo(
      isLive: (map['isLive'] as bool?) ?? false,
      ipAddress: (map['ipAddress'] as String?) ?? '127.0.0.1',
      port: (map['port'] as int?) ?? 8088,
      url: (map['url'] as String?) ?? 'http://127.0.0.1:8088',
      startedAt: parseDate(map['startedAt']),
      lastHeartbeat: parseDate(map['lastHeartbeat']),
      connectedClientId: map['connectedClientId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isLive': isLive,
      'ipAddress': ipAddress,
      'port': port,
      'url': url,
      'startedAt': startedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'lastHeartbeat': DateTime.now().toIso8601String(),
      'connectedClientId': connectedClientId,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerInfo &&
          runtimeType == other.runtimeType &&
          isLive == other.isLive &&
          ipAddress == other.ipAddress &&
          port == other.port &&
          url == other.url &&
          connectedClientId == other.connectedClientId;

  @override
  int get hashCode =>
      isLive.hashCode ^
      ipAddress.hashCode ^
      port.hashCode ^
      url.hashCode ^
      connectedClientId.hashCode;
}
