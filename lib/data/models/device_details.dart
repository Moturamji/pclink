import 'dart:io';
import 'package:flutter/foundation.dart';

/// Represents a single network interface and its assigned IP address.
@immutable
class NetworkAddressInfo {
  final String interfaceName;
  final String address;
  final InternetAddressType type;
  final bool isLoopback;

  const NetworkAddressInfo({
    required this.interfaceName,
    required this.address,
    required this.type,
    required this.isLoopback,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkAddressInfo &&
          runtimeType == other.runtimeType &&
          interfaceName == other.interfaceName &&
          address == other.address &&
          type == other.type &&
          isLoopback == other.isLoopback;

  @override
  int get hashCode =>
      interfaceName.hashCode ^
      address.hashCode ^
      type.hashCode ^
      isLoopback.hashCode;
}

/// Immutable data model containing all detected hardware, platform, and network details.
@immutable
class DeviceDetails {
  final String platform;
  final String deviceId;
  final String deviceName;
  final String osVersion;
  final String primaryIp;
  final List<NetworkAddressInfo> interfaces;
  final Map<String, String> additionalDetails;

  const DeviceDetails({
    required this.platform,
    required this.deviceId,
    required this.deviceName,
    required this.osVersion,
    required this.primaryIp,
    required this.interfaces,
    required this.additionalDetails,
  });

  bool get isWindows => platform == 'Windows';
  bool get isAndroid => platform == 'Android';
  bool get isConnected => primaryIp != 'Not Connected' && primaryIp != '127.0.0.1';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceDetails &&
          runtimeType == other.runtimeType &&
          platform == other.platform &&
          deviceId == other.deviceId &&
          deviceName == other.deviceName &&
          osVersion == other.osVersion &&
          primaryIp == other.primaryIp &&
          listEquals(interfaces, other.interfaces) &&
          mapEquals(additionalDetails, other.additionalDetails);

  @override
  int get hashCode =>
      platform.hashCode ^
      deviceId.hashCode ^
      deviceName.hashCode ^
      osVersion.hashCode ^
      primaryIp.hashCode ^
      interfaces.hashCode ^
      additionalDetails.hashCode;
}
