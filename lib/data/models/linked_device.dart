import 'package:flutter/foundation.dart';

/// Represents a linked device (Android phone or Windows PC) stored in Realtime Database.
@immutable
class LinkedDevice {
  final String platformKey; // 'android' or 'windows'
  final String deviceId;
  final String deviceName;
  final String osVersion;
  final String ipAddress;
  final DateTime? lastSeen;
  final bool isOnline;

  final String? sessionId;

  const LinkedDevice({
    required this.platformKey,
    required this.deviceId,
    required this.deviceName,
    required this.osVersion,
    required this.ipAddress,
    this.lastSeen,
    this.isOnline = false,
    this.sessionId,
  });

  bool get isWindows => platformKey.toLowerCase() == 'windows';
  bool get isAndroid => platformKey.toLowerCase() == 'android';

  factory LinkedDevice.fromMap(String key, Map<dynamic, dynamic> map) {
    DateTime? parsedLastSeen;
    final lastSeenRaw = map['lastSeen'];
    if (lastSeenRaw is String) {
      parsedLastSeen = DateTime.tryParse(lastSeenRaw);
    } else if (lastSeenRaw is int) {
      parsedLastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenRaw);
    }

    return LinkedDevice(
      platformKey: key,
      deviceId: (map['deviceId'] as String?) ?? 'Unknown ID',
      deviceName: (map['deviceName'] as String?) ?? 'Unnamed Device',
      osVersion: (map['osVersion'] as String?) ?? 'Unknown OS',
      ipAddress: (map['ipAddress'] as String?) ?? 'Unknown IP',
      lastSeen: parsedLastSeen,
      isOnline: (map['isOnline'] as bool?) ?? false,
      sessionId: map['sessionId'] as String?,
    );
  }

  /// Determines if the device is marked online AND has sent a recent heartbeat (default within 25s).
  bool isFreshlyOnline({
    DateTime? referenceTime,
    Duration maxStaleness = const Duration(seconds: 25),
  }) {
    if (!isOnline) return false;
    if (lastSeen == null) return isOnline;
    final now = referenceTime ?? DateTime.now();
    final diff = now.toUtc().difference(lastSeen!.toUtc()).abs();
    return diff <= maxStaleness;
  }

  LinkedDevice copyWith({
    String? platformKey,
    String? deviceId,
    String? deviceName,
    String? osVersion,
    String? ipAddress,
    DateTime? lastSeen,
    bool? isOnline,
    String? sessionId,
  }) {
    return LinkedDevice(
      platformKey: platformKey ?? this.platformKey,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      osVersion: osVersion ?? this.osVersion,
      ipAddress: ipAddress ?? this.ipAddress,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'osVersion': osVersion,
      'ipAddress': ipAddress,
      'lastSeen': lastSeen?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'isOnline': isOnline,
      if (sessionId != null) 'sessionId': sessionId,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkedDevice &&
          runtimeType == other.runtimeType &&
          platformKey == other.platformKey &&
          deviceId == other.deviceId &&
          deviceName == other.deviceName &&
          osVersion == other.osVersion &&
          ipAddress == other.ipAddress &&
          isOnline == other.isOnline &&
          sessionId == other.sessionId;

  @override
  int get hashCode =>
      platformKey.hashCode ^
      deviceId.hashCode ^
      deviceName.hashCode ^
      osVersion.hashCode ^
      ipAddress.hashCode ^
      isOnline.hashCode ^
      sessionId.hashCode;
}
