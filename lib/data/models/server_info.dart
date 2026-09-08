import 'package:flutter/foundation.dart';

/// Immutable model representing the status, address, and public WAN/relay connectivity of the Windows server.
@immutable
class ServerInfo {
  final bool isLive;
  final String ipAddress;
  final int port;
  final String url;
  final String? publicIp;
  final String? publicUrl;
  final String connectionMode;
  final DateTime? startedAt;
  final DateTime? lastHeartbeat;
  final String? connectedClientId;

  const ServerInfo({
    required this.isLive,
    required this.ipAddress,
    required this.port,
    required this.url,
    this.publicIp,
    this.publicUrl,
    this.connectionMode = 'cloud_relay',
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
      publicIp: map['publicIp'] as String?,
      publicUrl: map['publicUrl'] as String?,
      connectionMode: (map['connectionMode'] as String?) ?? 'cloud_relay',
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
      'publicIp': publicIp,
      'publicUrl': publicUrl ?? (publicIp != null ? 'http://$publicIp:$port' : null),
      'connectionMode': connectionMode,
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
          publicIp == other.publicIp &&
          publicUrl == other.publicUrl &&
          connectionMode == other.connectionMode &&
          connectedClientId == other.connectedClientId;

  @override
  int get hashCode =>
      isLive.hashCode ^
      ipAddress.hashCode ^
      port.hashCode ^
      url.hashCode ^
      publicIp.hashCode ^
      publicUrl.hashCode ^
      connectionMode.hashCode ^
      connectedClientId.hashCode;
}

