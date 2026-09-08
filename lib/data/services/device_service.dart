import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/device_details.dart';

/// Service responsible for querying device hardware specifications and network interfaces.
class DeviceService {
  final DeviceInfoPlugin _deviceInfoPlugin;

  DeviceService({DeviceInfoPlugin? deviceInfoPlugin})
      : _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  /// Queries all platform specs and network addresses asynchronously.
  Future<DeviceDetails> getDeviceDetails() async {
    String platform = 'Unknown';
    String deviceId = 'Unknown ID';
    String deviceName = 'Unknown Device';
    String osVersion = 'Unknown OS';
    final Map<String, String> additionalDetails = {};

    try {
      if (kIsWeb) {
        platform = 'Web';
        deviceId = 'Web-Browser';
      } else if (Platform.isAndroid) {
        platform = 'Android';
        final AndroidDeviceInfo androidInfo = await _deviceInfoPlugin.androidInfo;

        deviceId = androidInfo.id.isNotEmpty
            ? androidInfo.id
            : (androidInfo.fingerprint.isNotEmpty
                ? androidInfo.fingerprint
                : 'Android-${androidInfo.model}');

        deviceName = '${androidInfo.brand.toUpperCase()} ${androidInfo.model}';
        osVersion = 'Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})';

        additionalDetails['Manufacturer'] = androidInfo.manufacturer;
        additionalDetails['Model'] = androidInfo.model;
        additionalDetails['Brand'] = androidInfo.brand;
        additionalDetails['Hardware'] = androidInfo.hardware;
        additionalDetails['Product'] = androidInfo.product;
        additionalDetails['Device'] = androidInfo.device;
        additionalDetails['Is Physical Device'] = androidInfo.isPhysicalDevice.toString();
      } else if (Platform.isWindows) {
        platform = 'Windows';
        final WindowsDeviceInfo windowsInfo = await _deviceInfoPlugin.windowsInfo;

        deviceId = windowsInfo.deviceId.isNotEmpty
            ? windowsInfo.deviceId
            : windowsInfo.computerName;

        deviceName = windowsInfo.computerName;
        osVersion =
            '${windowsInfo.productName} (${windowsInfo.displayVersion.isNotEmpty ? windowsInfo.displayVersion : windowsInfo.releaseId})';

        additionalDetails['Computer Name'] = windowsInfo.computerName;
        additionalDetails['Registered Owner'] = windowsInfo.registeredOwner;
        additionalDetails['CPU Cores'] = windowsInfo.numberOfCores.toString();
        additionalDetails['RAM (MB)'] = windowsInfo.systemMemoryInMegabytes.toString();
        additionalDetails['Build Number'] = windowsInfo.buildNumber.toString();
        additionalDetails['Major Version'] = windowsInfo.majorVersion.toString();
      } else {
        platform = Platform.operatingSystem;
        deviceId = 'Unsupported Platform';
        deviceName = Platform.localHostname;
        osVersion = Platform.operatingSystemVersion;
      }
    } catch (e) {
      deviceId = 'Error: $e';
    }

    final List<NetworkAddressInfo> interfaces = await _getNetworkInterfaces();
    final String primaryIp = _determinePrimaryIp(interfaces);

    return DeviceDetails(
      platform: platform,
      deviceId: deviceId,
      deviceName: deviceName,
      osVersion: osVersion,
      primaryIp: primaryIp,
      interfaces: interfaces,
      additionalDetails: additionalDetails,
    );
  }

  Future<List<NetworkAddressInfo>> _getNetworkInterfaces() async {
    final List<NetworkAddressInfo> interfaces = [];
    try {
      final List<NetworkInterface> rawInterfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in rawInterfaces) {
        for (final addr in interface.addresses) {
          interfaces.add(
            NetworkAddressInfo(
              interfaceName: interface.name,
              address: addr.address,
              type: addr.type,
              isLoopback: addr.isLoopback,
            ),
          );
        }
      }

      if (interfaces.isEmpty) {
        final List<NetworkInterface> allInterfaces = await NetworkInterface.list(
          includeLoopback: true,
          type: InternetAddressType.any,
        );
        for (final interface in allInterfaces) {
          for (final addr in interface.addresses) {
            interfaces.add(
              NetworkAddressInfo(
                interfaceName: interface.name,
                address: addr.address,
                type: addr.type,
                isLoopback: addr.isLoopback,
              ),
            );
          }
        }
      }
    } catch (_) {
      // Fallback handled gracefully
    }
    return interfaces;
  }

  String _determinePrimaryIp(List<NetworkAddressInfo> interfaces) {
    if (interfaces.isEmpty) return 'Not Connected';

    final nonLoopbackIpv4 = interfaces.firstWhere(
      (info) => !info.isLoopback && info.type == InternetAddressType.IPv4,
      orElse: () => interfaces.first,
    );

    return nonLoopbackIpv4.address;
  }
}
