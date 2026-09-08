import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/device_details.dart';
import '../models/linked_device.dart';
import '../models/server_info.dart';

/// Service managing user, device, and local server synchronization with Firebase Realtime Database via REST API.
class DatabaseService {
  static const String _dbBaseUrl =
      'https://pclink-34bfa-default-rtdb.asia-southeast1.firebasedatabase.app';

  final http.Client _client;

  DatabaseService({http.Client? client}) : _client = client ?? http.Client();

  /// Synchronizes the user profile and current platform device identity.
  Future<void> syncUserAndDevice({
    required User user,
    required DeviceDetails details,
  }) async {
    try {
      final token = await user.getIdToken();
      final nowIso = DateTime.now().toIso8601String();
      final authQuery = token != null ? '?auth=$token' : '';

      // 1. Verify user profile exists
      final userUri = Uri.parse('$_dbBaseUrl/users/${user.uid}.json$authQuery');
      final userResponse = await _client.get(userUri);

      if (userResponse.statusCode == 200 &&
          (userResponse.body == 'null' || userResponse.body.isEmpty)) {
        // Create user profile
        final putResp = await _client.put(
          userUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': user.uid,
            'email': user.email ?? '',
            'createdAt': nowIso,
            'lastActive': nowIso,
          }),
        );
        debugPrint('DatabaseService: Created user profile with status ${putResp.statusCode}');
      } else if (userResponse.statusCode == 200) {
        // Update lastActive
        final lastActiveUri =
            Uri.parse('$_dbBaseUrl/users/${user.uid}/lastActive.json$authQuery');
        await _client.put(
          lastActiveUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(nowIso),
        );
      } else {
        debugPrint(
            'DatabaseService sync warning: user get returned [${userResponse.statusCode}] ${userResponse.body}');
      }

      // 2. Store or update platform device node
      final platformKey = details.isWindows ? 'windows' : 'android';
      final deviceUri = Uri.parse(
          '$_dbBaseUrl/users/${user.uid}/devices/$platformKey.json$authQuery');

      final devResp = await _client.put(
        deviceUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId': details.deviceId,
          'deviceName': details.deviceName,
          'osVersion': details.osVersion,
          'ipAddress': details.primaryIp,
          'lastSeen': nowIso,
          'isOnline': true,
        }),
      );
      debugPrint(
          'DatabaseService: Synced $platformKey device node with status ${devResp.statusCode}');
    } catch (e) {
      debugPrint('DatabaseService sync exception: $e');
    }
  }

  /// Updates the local Windows server information in Firebase RTDB.
  Future<void> updateServerInfo({
    required User user,
    required ServerInfo serverInfo,
  }) async {
    try {
      final token = await user.getIdToken();
      final authQuery = token != null ? '?auth=$token' : '';
      final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/server.json$authQuery');

      final resp = await _client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(serverInfo.toMap()),
      );
      debugPrint('DatabaseService: Updated server info with status ${resp.statusCode}');
    } catch (e) {
      debugPrint('DatabaseService updateServerInfo error: $e');
    }
  }

  /// Marks the local Windows server as offline in Firebase RTDB.
  Future<void> setServerOffline({
    required User user,
  }) async {
    try {
      final token = await user.getIdToken();
      final authQuery = token != null ? '?auth=$token' : '';
      final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/server.json$authQuery');

      final resp = await _client.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'isLive': false,
          'lastHeartbeat': DateTime.now().toIso8601String(),
          'connectedClientId': null,
        }),
      );
      debugPrint('DatabaseService: Marked server offline with status ${resp.statusCode}');
    } catch (e) {
      debugPrint('DatabaseService setServerOffline error: $e');
    }
  }

  /// Streams real-time device updates for the given [user].
  Stream<List<LinkedDevice>> watchUserDevices(User user) {
    late final StreamController<List<LinkedDevice>> controller;
    Timer? timer;

    Future<void> fetchDevices() async {
      try {
        final token = await user.getIdToken();
        final authQuery = token != null ? '?auth=$token' : '';
        final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/devices.json$authQuery');
        final response = await _client.get(uri);

        if (response.statusCode == 200 &&
            response.body.isNotEmpty &&
            response.body != 'null') {
          final dynamic data = jsonDecode(response.body);
          if (data is Map) {
            final List<LinkedDevice> list = [];
            data.forEach((key, value) {
              if (value is Map) {
                list.add(LinkedDevice.fromMap(key.toString(), value));
              }
            });
            if (!controller.isClosed) {
              controller.add(list);
            }
            return;
          }
        }
        if (!controller.isClosed) {
          controller.add(<LinkedDevice>[]);
        }
      } catch (e) {
        debugPrint('DatabaseService watchUserDevices error: $e');
        if (!controller.isClosed) {
          controller.add(<LinkedDevice>[]);
        }
      }
    }

    controller = StreamController<List<LinkedDevice>>.broadcast(
      onListen: () {
        fetchDevices();
        timer = Timer.periodic(const Duration(seconds: 4), (_) => fetchDevices());
      },
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  /// Streams real-time Windows server status for the given [user].
  Stream<ServerInfo?> watchUserServer(User user) {
    late final StreamController<ServerInfo?> controller;
    Timer? timer;

    Future<void> fetchServer() async {
      try {
        final token = await user.getIdToken();
        final authQuery = token != null ? '?auth=$token' : '';
        final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/server.json$authQuery');
        final response = await _client.get(uri);

        if (response.statusCode == 200 &&
            response.body.isNotEmpty &&
            response.body != 'null') {
          final dynamic data = jsonDecode(response.body);
          if (data is Map) {
            final server = ServerInfo.fromMap(data);
            if (!controller.isClosed) {
              controller.add(server);
            }
            return;
          }
        }
        if (!controller.isClosed) {
          controller.add(null);
        }
      } catch (e) {
        debugPrint('DatabaseService watchUserServer error: $e');
        if (!controller.isClosed) {
          controller.add(null);
        }
      }
    }

    controller = StreamController<ServerInfo?>.broadcast(
      onListen: () {
        fetchServer();
        timer = Timer.periodic(const Duration(seconds: 3), (_) => fetchServer());
      },
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  // -------------------------------------------------------------
  // Public Network / Cloud Relay Channel Methods
  // -------------------------------------------------------------

  /// Sends a cross-network handshake request from Android to Windows via Firebase RTDB channel.
  Future<bool> sendCloudHandshakeRequest({
    required User user,
    required String androidDeviceId,
    required String requestId,
  }) async {
    try {
      final token = await user.getIdToken();
      final authQuery = token != null ? '?auth=$token' : '';
      final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/channel/handshake_request.json$authQuery');

      final response = await _client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requestId': requestId,
          'deviceId': androidDeviceId,
          'timestamp': DateTime.now().toIso8601String(),
          'clientPlatform': 'Android',
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('DatabaseService sendCloudHandshakeRequest error: $e');
      return false;
    }
  }

  /// Listens on Windows for incoming cloud handshake requests.
  Stream<Map<String, dynamic>?> listenCloudHandshakeRequests(User user) {
    late final StreamController<Map<String, dynamic>?> controller;
    Timer? timer;
    String? lastProcessedRequestId;

    Future<void> fetchRequest() async {
      try {
        final token = await user.getIdToken();
        final authQuery = token != null ? '?auth=$token' : '';
        final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/channel/handshake_request.json$authQuery');
        final response = await _client.get(uri);

        if (response.statusCode == 200 &&
            response.body.isNotEmpty &&
            response.body != 'null') {
          final dynamic data = jsonDecode(response.body);
          if (data is Map) {
            final requestId = data['requestId']?.toString();
            if (requestId != null && requestId != lastProcessedRequestId) {
              lastProcessedRequestId = requestId;
              if (!controller.isClosed) {
                controller.add(Map<String, dynamic>.from(data));
              }
            }
          }
        }
      } catch (e) {
        debugPrint('DatabaseService listenCloudHandshakeRequests error: $e');
      }
    }

    controller = StreamController<Map<String, dynamic>?>.broadcast(
      onListen: () {
        fetchRequest();
        timer = Timer.periodic(const Duration(seconds: 2), (_) => fetchRequest());
      },
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  /// Sends a handshake response from Windows to Android via Firebase RTDB channel.
  Future<void> sendCloudHandshakeResponse({
    required User user,
    required String requestId,
    required bool success,
    required String message,
    required String windowsHost,
  }) async {
    try {
      final token = await user.getIdToken();
      final authQuery = token != null ? '?auth=$token' : '';
      final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/channel/handshake_response.json$authQuery');

      await _client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requestId': requestId,
          'success': success,
          'message': message,
          'windowsHost': windowsHost,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('DatabaseService sendCloudHandshakeResponse error: $e');
    }
  }

  /// Waits on Android for the Windows server response for a given [requestId].
  Future<Map<String, dynamic>> waitForCloudHandshakeResponse({
    required User user,
    required String requestId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      try {
        final token = await user.getIdToken();
        final authQuery = token != null ? '?auth=$token' : '';
        final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/channel/handshake_response.json$authQuery');
        final response = await _client.get(uri);

        if (response.statusCode == 200 &&
            response.body.isNotEmpty &&
            response.body != 'null') {
          final dynamic data = jsonDecode(response.body);
          if (data is Map && data['requestId'] == requestId) {
            return Map<String, dynamic>.from(data);
          }
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 600));
    }

    return {
      'success': false,
      'error': 'Connection timed out. Ensure the Windows PC is running PCLink.',
    };
  }

  /// Sets the connected client ID in Firebase RTDB.
  Future<void> setConnectedClientId({
    required User user,
    required String? clientId,
  }) async {
    try {
      final token = await user.getIdToken();
      final authQuery = token != null ? '?auth=$token' : '';
      final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/server/connectedClientId.json$authQuery');

      await _client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(clientId),
      );
    } catch (e) {
      debugPrint('DatabaseService setConnectedClientId error: $e');
    }
  }

  /// Clears the connected client ID when Android disconnects.
  Future<void> disconnectClient({required User user}) async {
    try {
      final token = await user.getIdToken();
      final authQuery = token != null ? '?auth=$token' : '';
      final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/server/connectedClientId.json$authQuery');

      await _client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(null),
      );
      // Clean up channel request & response
      final chanUri = Uri.parse('$_dbBaseUrl/users/${user.uid}/channel.json$authQuery');
      await _client.delete(chanUri);
    } catch (e) {
      debugPrint('DatabaseService disconnectClient error: $e');
    }
  }

  /// Updates the FCM device push token for the user's Android device.
  Future<void> updateFcmToken({
    required User user,
    required String fcmToken,
  }) async {
    try {
      final token = await user.getIdToken();
      final authQuery = token != null ? '?auth=$token' : '';
      final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/devices/android/fcmToken.json$authQuery');

      final resp = await _client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(fcmToken),
      );
      debugPrint('DatabaseService: Updated Android FCM Token with status ${resp.statusCode}');
    } catch (e) {
      debugPrint('DatabaseService updateFcmToken error: $e');
    }
  }

  /// Retrieves the registered Android FCM token for the given [user].
  Future<String?> getAndroidFcmToken({required User user}) async {
    try {
      final token = await user.getIdToken();
      final authQuery = token != null ? '?auth=$token' : '';
      final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/devices/android/fcmToken.json$authQuery');
      final response = await _client.get(uri);

      if (response.statusCode == 200 &&
          response.body.isNotEmpty &&
          response.body != 'null') {
        final decoded = jsonDecode(response.body);
        if (decoded is String && decoded.isNotEmpty) {
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('DatabaseService getAndroidFcmToken error: $e');
    }
    return null;
  }

  /// Queues a server-is-live notification event in RTDB to alert mobile devices.
  Future<void> queueServerLiveNotification({
    required User user,
    required String pcHostName,
  }) async {
    try {
      final token = await user.getIdToken();
      final authQuery = token != null ? '?auth=$token' : '';
      final uri = Uri.parse('$_dbBaseUrl/users/${user.uid}/notifications/latest.json$authQuery');

      await _client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': 'notif_${DateTime.now().millisecondsSinceEpoch}',
          'title': 'Windows PC is Live',
          'body': '$pcHostName is running PCLink and ready for secure connection.',
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'server_live',
          'hostName': pcHostName,
        }),
      );
      debugPrint('DatabaseService: Queued server live notification alert');
    } catch (e) {
      debugPrint('DatabaseService queueServerLiveNotification error: $e');
    }
  }
}



