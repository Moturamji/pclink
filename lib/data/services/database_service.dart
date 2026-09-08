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
      'https://pclink-34bfa-default-rtdb.firebaseio.com';

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
        await _client.put(
          userUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': user.uid,
            'email': user.email ?? '',
            'createdAt': nowIso,
            'lastActive': nowIso,
          }),
        );
      } else {
        // Update lastActive
        final lastActiveUri =
            Uri.parse('$_dbBaseUrl/users/${user.uid}/lastActive.json$authQuery');
        await _client.put(
          lastActiveUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(nowIso),
        );
      }

      // 2. Store or update platform device node
      final platformKey = details.isWindows ? 'windows' : 'android';
      final deviceUri = Uri.parse(
          '$_dbBaseUrl/users/${user.uid}/devices/$platformKey.json$authQuery');

      await _client.put(
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
    } catch (e) {
      debugPrint('DatabaseService sync warning: $e');
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

      await _client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(serverInfo.toMap()),
      );
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

      await _client.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'isLive': false,
          'lastHeartbeat': DateTime.now().toIso8601String(),
          'connectedClientId': null,
        }),
      );
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
      } catch (_) {
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
      } catch (_) {
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
}

