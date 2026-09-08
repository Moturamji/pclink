import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/device_details.dart';

/// Service responsible for querying device hardware specifications and network interfaces.
class DeviceService {
  final DeviceInfoPlugin _deviceInfoPlugin;
  final http.Client _httpClient;

  DeviceService({
    DeviceInfoPlugin? deviceInfoPlugin,
    http.Client? httpClient,
  })  : _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin(),
        _httpClient = httpClient ?? http.Client();

  /// Queries all platform specs, network addresses, and public WAN IP asynchronously.
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
    final String? publicIp = await getPublicIpAddress();

    return DeviceDetails(
      platform: platform,
      deviceId: deviceId,
      deviceName: deviceName,
      osVersion: osVersion,
      primaryIp: primaryIp,
      publicIp: publicIp,
      interfaces: interfaces,
      additionalDetails: additionalDetails,
    );
  }

  /// Resolves the device's public WAN IP address over the Internet.
  Future<String?> getPublicIpAddress() async {
    try {
      final response = await _httpClient
          .get(Uri.parse('https://api.ipify.org?format=json'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map && data['ip'] != null) {
          return data['ip'].toString().trim();
        }
      }
    } catch (_) {
      try {
        final fallback = await _httpClient
            .get(Uri.parse('https://icanhazip.com'))
            .timeout(const Duration(seconds: 3));
        if (fallback.statusCode == 200 && fallback.body.trim().isNotEmpty) {
          return fallback.body.trim();
        }
      } catch (_) {}
    }
    return null;
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

