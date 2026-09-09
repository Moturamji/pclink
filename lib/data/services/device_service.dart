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

  /// Resolves the PC's public address used for the "Public Direct" connection.
  ///
  /// Priority:
  ///  1. `tunnel_url.txt` next to the app -- a stable override that works with
  ///     ANY tunnel tool (ngrok, cloudflared quick tunnels, localhost.run...).
  ///  2. ngrok's local control API (`http://127.0.0.1:4040/api/tunnels`) when
  ///     the ngrok client is running.
  ///  3. `null` -- caller falls back to the raw public WAN IP.
  Future<String?> getTunnelUrl() async {
    // 1. Explicit override file (tool-agnostic).
    try {
      final file = File('tunnel_url.txt');
      if (await file.exists()) {
        final contents = (await file.readAsString()).trim();
        if (contents.isNotEmpty) {
          final url = _normalizeTunnelUrl(contents);
          debugPrint('DeviceService: Using tunnel URL from tunnel_url.txt: $url');
          return url;
        }
      }
    } catch (e) {
      debugPrint('DeviceService read tunnel_url.txt error: $e');
    }

    // 2. Auto-detect ngrok local control API.
    try {
      final response = await _httpClient
          .get(Uri.parse('http://127.0.0.1:4040/api/tunnels'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map && data['tunnels'] is List) {
          final tunnels = data['tunnels'] as List;
          String? httpsUrl;
          for (final tunnel in tunnels) {
            if (tunnel is Map && tunnel['public_url'] != null) {
              final url = tunnel['public_url'].toString().trim();
              if (url.startsWith('https://')) return _normalizeTunnelUrl(url);
              httpsUrl ??= _normalizeTunnelUrl(url);
            }
          }
          if (httpsUrl != null) return httpsUrl;
        }
      }
    } catch (_) {
      // ngrok client is not running.
    }

    return null;
  }

  /// Normalizes a tunnel address into a clean base URL.
  String _normalizeTunnelUrl(String raw) {
    var url = raw.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
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

    final nonLoopbackIpv4 = interfaces
        .where(
          (info) => !info.isLoopback && info.type == InternetAddressType.IPv4,
        )
        .toList();

    if (nonLoopbackIpv4.isEmpty) {
      return interfaces.first.address;
    }

    // Prefer a typical site-local LAN address (192.168.x, 10.x, 172.16-31.x)
    // and skip virtual-adapter / link-local ranges so we don't advertise a
    // Docker/Hyper-V/VPN NIC that the phone can never reach.
    for (final info in nonLoopbackIpv4) {
      if (_isUsableSiteLocalAddress(info.address)) {
        return info.address;
      }
    }

    return nonLoopbackIpv4.first.address;
  }

  /// Returns true for private-site addresses the phone can actually route to.
  bool _isUsableSiteLocalAddress(String ip) {
    // Skip Automatic Private IP (link-local) and common virtual-adapter ranges.
    if (ip.startsWith('169.254.')) return false;
    if (ip.startsWith('192.0.0.') || ip.startsWith('198.18.') ||
        ip.startsWith('198.51.100.')) {
      return false;
    }
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final secondOctet = int.tryParse(parts[1]);
        if (secondOctet != null &&
            secondOctet >= 16 &&
            secondOctet <= 31 &&
            secondOctet != 17 &&
            secondOctet != 18) {
          // Skip Docker's default 172.17/172.18 bridge ranges.
          return true;
        }
      }
    }
    return false;
  }
}

