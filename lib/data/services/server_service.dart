import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/server_constants.dart';
import '../models/server_info.dart';

/// Manages the local lightweight HTTP server on Windows and client-side handshake on Android.
class ServerService {
  HttpServer? _server;
  String? _authorizedAndroidDeviceId;
  String? _connectedClientId;
  ServerInfo _currentInfo = const ServerInfo(
    isLive: false,
    ipAddress: '127.0.0.1',
    port: ServerConstants.defaultPort,
    url: 'http://127.0.0.1:${ServerConstants.defaultPort}',
  );

  final StreamController<ServerInfo> _stateController =
      StreamController<ServerInfo>.broadcast();

  Stream<ServerInfo> get serverStateStream => _stateController.stream;
  ServerInfo get currentServerInfo => _currentInfo;
  bool get isRunning => _server != null;

  /// Sets the authorized Android Device ID allowed to connect.
  void setAuthorizedAndroidDeviceId(String? deviceId) {
    _authorizedAndroidDeviceId = deviceId;
  }

  /// Starts the lightweight HTTP server on Windows.
  Future<ServerInfo?> startServer({
    required String hostIp,
    int port = ServerConstants.defaultPort,
    String? authorizedAndroidDeviceId,
  }) async {
    if (kIsWeb || !Platform.isWindows) {
      debugPrint('ServerService: Server is only supported on Windows.');
      return null;
    }

    if (_server != null) {
      return _currentInfo;
    }

    _authorizedAndroidDeviceId = authorizedAndroidDeviceId;

    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );

      final serverUrl = 'http://$hostIp:$port';
      _currentInfo = ServerInfo(
        isLive: true,
        ipAddress: hostIp,
        port: port,
        url: serverUrl,
        startedAt: DateTime.now(),
        lastHeartbeat: DateTime.now(),
        connectedClientId: _connectedClientId,
      );

      _stateController.add(_currentInfo);
      _listenToRequests();

      debugPrint('ServerService: Windows server listening on $serverUrl');
      return _currentInfo;
    } catch (e) {
      debugPrint('ServerService: Failed to start server: $e');
      _currentInfo = ServerInfo(
        isLive: false,
        ipAddress: hostIp,
        port: port,
        url: 'http://$hostIp:$port',
      );
      _stateController.add(_currentInfo);
      return null;
    }
  }

  void _listenToRequests() {
    _server?.listen((HttpRequest request) async {
      _addCorsHeaders(request.response);

      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      final path = request.uri.path;

      try {
        switch (path) {
          case ServerConstants.healthEndpoint:
            _handleHealth(request);
            break;

          case ServerConstants.authEndpoint:
            await _handleAuth(request);
            break;

          case ServerConstants.pingEndpoint:
            _handlePing(request);
            break;

          case ServerConstants.statusEndpoint:
            _handleStatus(request);
            break;

          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(jsonEncode({'error': 'Endpoint not found'}));
            await request.response.close();
        }
      } catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({'error': e.toString()}));
        await request.response.close();
      }
    });
  }

  void _handleHealth(HttpRequest request) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'status': 'ok',
      'message': ServerConstants.msgServerRunning,
      'serverPlatform': 'Windows',
      'hostName': Platform.localHostname,
      'timestamp': DateTime.now().toIso8601String(),
    }));
    request.response.close();
  }

  Future<void> _handleAuth(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.close();
      return;
    }

    String? candidateDeviceId = request.headers.value(ServerConstants.authHeader);

    if (candidateDeviceId == null || candidateDeviceId.isEmpty) {
      final bodyStr = await utf8.decoder.bind(request).join();
      if (bodyStr.isNotEmpty) {
        try {
          final dynamic data = jsonDecode(bodyStr);
          if (data is Map && data['deviceId'] != null) {
            candidateDeviceId = data['deviceId'].toString();
          }
        } catch (_) {}
      }
    }

    request.response.headers.contentType = ContentType.json;

    // Check device ID password
    final isAuthorized = _verifyDeviceId(candidateDeviceId);

    if (isAuthorized) {
      _connectedClientId = candidateDeviceId;
      _currentInfo = ServerInfo(
        isLive: true,
        ipAddress: _currentInfo.ipAddress,
        port: _currentInfo.port,
        url: _currentInfo.url,
        startedAt: _currentInfo.startedAt,
        lastHeartbeat: DateTime.now(),
        connectedClientId: _connectedClientId,
      );
      _stateController.add(_currentInfo);

      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({
        'success': true,
        'message': ServerConstants.msgAuthSuccess,
        'windowsHost': Platform.localHostname,
        'serverUrl': _currentInfo.url,
      }));
    } else {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write(jsonEncode({
        'success': false,
        'error': ServerConstants.msgAuthFailed,
      }));
    }

    await request.response.close();
  }

  void _handlePing(HttpRequest request) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'pong': true,
      'timestamp': DateTime.now().toIso8601String(),
    }));
    request.response.close();
  }

  void _handleStatus(HttpRequest request) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_currentInfo.toMap()));
    request.response.close();
  }

  bool _verifyDeviceId(String? candidate) {
    if (candidate == null || candidate.trim().isEmpty) return false;

    // If authorized device ID is set, check match
    if (_authorizedAndroidDeviceId != null &&
        _authorizedAndroidDeviceId!.isNotEmpty) {
      return candidate.trim() == _authorizedAndroidDeviceId!.trim();
    }

    // If not set yet, accept and latch the first Android client ID as pre-shared key
    _authorizedAndroidDeviceId = candidate.trim();
    return true;
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Origin, X-Requested-With, Content-Type, Accept, ${ServerConstants.authHeader}',
    );
  }

  /// Stops the local Windows server.
  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }

    _connectedClientId = null;
    _currentInfo = ServerInfo(
      isLive: false,
      ipAddress: _currentInfo.ipAddress,
      port: _currentInfo.port,
      url: _currentInfo.url,
      startedAt: null,
      lastHeartbeat: null,
      connectedClientId: null,
    );
    _stateController.add(_currentInfo);
  }

  // -------------------------------------------------------------
  // Android Client Connection Methods
  // -------------------------------------------------------------

  /// Performs the password-protected handshake from Android to the Windows server.
  static Future<Map<String, dynamic>> authenticateClientWithServer({
    required String serverUrl,
    required String androidDeviceId,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final sanitizedUrl = serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl;
      final uri = Uri.parse('$sanitizedUrl${ServerConstants.authEndpoint}');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              ServerConstants.authHeader: androidDeviceId,
            },
            body: jsonEncode({
              'deviceId': androidDeviceId,
              'clientPlatform': 'Android',
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        return {
          'success': true,
          'message': data is Map && data['message'] != null
              ? data['message']
              : ServerConstants.msgAuthSuccess,
          'windowsHost': data is Map ? data['windowsHost'] : 'Windows PC',
        };
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'error': 'Authentication failed: Android Device ID was rejected by the PC.',
        };
      } else {
        return {
          'success': false,
          'error': 'Server responded with status ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to reach PC server. Make sure PC and phone are on the same Wi-Fi network ($e)',
      };
    }
  }

  void dispose() {
    stopServer();
    _stateController.close();
  }
}
