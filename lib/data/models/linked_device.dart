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

  const LinkedDevice({
    required this.platformKey,
    required this.deviceId,
    required this.deviceName,
    required this.osVersion,
    required this.ipAddress,
    this.lastSeen,
    this.isOnline = false,
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'osVersion': osVersion,
      'ipAddress': ipAddress,
      'lastSeen': DateTime.now().toIso8601String(),
      'isOnline': isOnline,
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
          isOnline == other.isOnline;

  @override
  int get hashCode =>
      platformKey.hashCode ^
      deviceId.hashCode ^
      deviceName.hashCode ^
      osVersion.hashCode ^
      ipAddress.hashCode ^
      isOnline.hashCode;
}
