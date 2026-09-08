import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

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
}

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
}

class DeviceInfoService {
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

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
        
        // Android ID / hardware ID
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
        
        // Windows Device ID / Machine ID
        deviceId = windowsInfo.deviceId.isNotEmpty
            ? windowsInfo.deviceId
            : windowsInfo.computerName;
            
        deviceName = windowsInfo.computerName;
        osVersion = '${windowsInfo.productName} (${windowsInfo.displayVersion.isNotEmpty ? windowsInfo.displayVersion : windowsInfo.releaseId})';
        
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

    // Network IP extraction
    final List<NetworkAddressInfo> interfaces = [];
    String primaryIp = 'Not Connected';

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

      // If no non-loopback found, check with loopbacks
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

      // Determine primary IP: first non-loopback IPv4
      final nonLoopbackIpv4 = interfaces.firstWhere(
        (info) => !info.isLoopback && info.type == InternetAddressType.IPv4,
        orElse: () => interfaces.isNotEmpty
            ? interfaces.first
            : const NetworkAddressInfo(
                interfaceName: 'None',
                address: '127.0.0.1',
                type: InternetAddressType.IPv4,
                isLoopback: true,
              ),
      );

      primaryIp = nonLoopbackIpv4.address;
    } catch (e) {
      primaryIp = 'Error: $e';
    }

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
}
