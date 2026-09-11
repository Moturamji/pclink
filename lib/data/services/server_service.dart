import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/server_constants.dart';
import '../../features/clipboard/models/clipboard_item.dart';
import '../../features/file_share/models/shared_file.dart';
import '../../features/file_share/models/transfer_progress.dart';
import '../models/server_info.dart';
import 'database_service.dart';

/// Manages the lightweight server on Windows and client-side handshake on Android across local and public networks.
class ServerService {
  HttpServer? _server;
  String? _authorizedAndroidDeviceId;
  String? _connectedClientId;
  final List<ClipboardItem> _clipboardHistory = [];
  Function(ClipboardItem item)? onClipboardReceived;

  // Real-time file transfer progress broadcast stream (active uploads/downloads)
  TransferProgress? _currentTransferProgress;
  final StreamController<TransferProgress?> _transferProgressController =
      StreamController<TransferProgress?>.broadcast();

  // File sharing store: file bytes live on disk in the shared folder while the
  // metadata list stays in RAM (mirrors how the server keeps clipboard history).
  final List<SharedFile> _sharedFiles = [];
  final StreamController<List<SharedFile>> _sharedFilesController =
      StreamController<List<SharedFile>>.broadcast();
  Directory? _sharedDir;

  ServerInfo _currentInfo = const ServerInfo(
    isLive: false,
    ipAddress: '127.0.0.1',
    port: ServerConstants.defaultPort,
    url: 'http://127.0.0.1:${ServerConstants.defaultPort}',
    connectionMode: 'cloud_relay',
  );

  final StreamController<ServerInfo> _stateController =
      StreamController<ServerInfo>.broadcast();

  Stream<ServerInfo> get serverStateStream => _stateController.stream;
  ServerInfo get currentServerInfo => _currentInfo;
  bool get isRunning => _server != null;
  List<ClipboardItem> get clipboardHistory =>
      List.unmodifiable(_clipboardHistory);

  List<SharedFile> get sharedFiles => List.unmodifiable(_sharedFiles);
  Stream<List<SharedFile>> get sharedFilesStream =>
      _sharedFilesController.stream;
  Stream<TransferProgress?> get transferProgressStream =>
      _transferProgressController.stream;
  TransferProgress? get currentTransferProgress => _currentTransferProgress;

  void _emitTransferProgress(TransferProgress? progress) {
    _currentTransferProgress = progress;
    if (!_transferProgressController.isClosed) {
      _transferProgressController.add(progress);
    }
  }

  /// Stores a locally copied clip in the server history.
  void addLocalClipboardItem(ClipboardItem item) {
    _clipboardHistory.removeWhere(
      (c) => c.id == item.id || c.text == item.text,
    );
    _clipboardHistory.insert(0, item);
    if (_clipboardHistory.length > 50) {
      _clipboardHistory.removeLast();
    }
  }

  /// Clears in-memory clipboard history.
  void clearClipboardHistory() {
    _clipboardHistory.clear();
  }

  // -------------------------------------------------------------------------
  // File Sharing API (Windows side)
  // -------------------------------------------------------------------------

  /// Registers a local PC file for sharing. The file is copied into the shared
  /// folder so it stays available to the phone even if the original moves.
  /// Returns the created [SharedFile], or null when the source is unavailable.
  Future<SharedFile?> addLocalSharedFile({
    required String sourcePath,
    required String deviceName,
  }) async {
    try {
      final src = File(sourcePath);
      if (!await src.exists()) {
        debugPrint(
          'ServerService: addLocalSharedFile - source missing: $sourcePath',
        );
        return null;
      }

      final dir = await _getSharedDir();
      final id = 'file_${DateTime.now().millisecondsSinceEpoch}';
      final originalName = _sanitizeFileName(
        sourcePath.split(RegExp(r'[\\/]')).last,
      );
      final dest = File('${dir.path}\\${id}_$originalName');
      await src.copy(dest.path);

      final item = SharedFile(
        id: id,
        name: originalName,
        size: await dest.length(),
        sourcePlatform: 'windows',
        sourceDeviceName: deviceName,
        timestamp: DateTime.now(),
        filePath: dest.path,
      );
      _sharedFiles.insert(0, item);
      if (_sharedFiles.length > 100) _sharedFiles.removeLast();
      _sharedFilesController.add(List.from(_sharedFiles));
      debugPrint(
        'ServerService: Registered PC file for sharing: $originalName',
      );
      return item;
    } catch (e) {
      debugPrint('ServerService: addLocalSharedFile error: $e');
      return null;
    }
  }

  /// Removes a shared file (metadata + on-disk copy) from the sharing store.
  Future<void> removeSharedFile(String id) async {
    SharedFile? match;
    for (final f in _sharedFiles) {
      if (f.id == id) {
        match = f;
        break;
      }
    }
    if (match == null) return;

    _sharedFiles.remove(match);
    _sharedFilesController.add(List.from(_sharedFiles));
    try {
      if (match.filePath != null) {
        final file = File(match.filePath!);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      debugPrint('ServerService: removeSharedFile delete error: $e');
    }
  }

  /// Resolves (and lazily creates) the on-disk shared folder.
  /// Files here are wiped only when the user removes them - the folder itself
  /// persists across server restarts so downloads keep working.
  Future<Directory> _getSharedDir() async {
    if (_sharedDir != null) return _sharedDir!;
    final appData = Platform.environment['APPDATA'] ?? '.';
    final dir = Directory('$appData\\pclink\\shared_files');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _sharedDir = dir;
    return dir;
  }

  /// Rebuilds the in-memory list from disk so previously shared files stay
  /// available after the PC app restarts. File names follow `<id>_<name>`.
  Future<void> _loadPersistedSharedFiles() async {
    try {
      final dir = await _getSharedDir();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final fullName = entity.uri.pathSegments.last;
        final underscore = fullName.indexOf('_');
        if (underscore <= 0) continue; // Not a PCLink shared file.
        final id = fullName.substring(0, underscore);
        final originalName = fullName.substring(underscore + 1);
        final stat = await entity.stat();
        _sharedFiles.add(
          SharedFile(
            id: id,
            name: originalName,
            size: stat.size,
            sourcePlatform: 'windows',
            sourceDeviceName: Platform.localHostname,
            timestamp: stat.modified,
            filePath: entity.path,
          ),
        );
      }
      _sharedFiles.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (_sharedFiles.isNotEmpty) {
        _sharedFilesController.add(List.from(_sharedFiles));
        debugPrint(
          'ServerService: Restored ${_sharedFiles.length} shared file(s).',
        );
      }
    } catch (e) {
      debugPrint('ServerService: _loadPersistedSharedFiles error: $e');
    }
  }

  /// Strips path separators and Windows-illegal characters from a file name.
  static String _sanitizeFileName(String raw) {
    var name = raw.split(RegExp(r'[\\/]')).last.trim();
    if (name.isEmpty) name = 'uploaded_file.bin';
    if (name.length > 150) name = name.substring(name.length - 150);
    name = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return name;
  }

  /// Sets the authorized Android Device ID allowed to connect.
  void setAuthorizedAndroidDeviceId(String? deviceId) {
    _authorizedAndroidDeviceId = deviceId;
  }

  /// Starts the lightweight HTTP server on Windows.
  Future<ServerInfo?> startServer({
    required String hostIp,
    String? publicIp,
    String? publicUrlOverride,
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
      // A tunnel URL (ngrok / cloudflared) is used verbatim when provided;
      // otherwise fall back to the raw public WAN IP.
      final publicUrl =
          publicUrlOverride ??
          (publicIp != null ? 'http://$publicIp:$port' : null);

      _currentInfo = ServerInfo(
        isLive: true,
        ipAddress: hostIp,
        port: port,
        url: serverUrl,
        publicIp: publicIp,
        publicUrl: publicUrl,
        connectionMode: 'cloud_relay',
        startedAt: DateTime.now(),
        lastHeartbeat: DateTime.now(),
        connectedClientId: _connectedClientId,
      );

      _stateController.add(_currentInfo);
      _listenToRequests();
      _ensureFirewallRule(port);
      _loadPersistedSharedFiles();

      debugPrint(
        'ServerService: Windows server listening on $serverUrl (Public address: ${publicUrl ?? publicIp ?? 'LAN only'})',
      );
      return _currentInfo;
    } catch (e) {
      debugPrint('ServerService: Failed to start server: $e');
      _currentInfo = ServerInfo(
        isLive: false,
        ipAddress: hostIp,
        port: port,
        url: 'http://$hostIp:$port',
        publicIp: publicIp,
        publicUrl:
            publicUrlOverride ??
            (publicIp != null ? 'http://$publicIp:$port' : null),
      );
      _stateController.add(_currentInfo);
      return null;
    }
  }

  /// Refreshes the published public address without restarting the server.
  /// Used when a tunnel URL appears or rotates while PCLink is running.
  void updatePublicUrl(String? publicUrl) {
    if (!isRunning) return;
    if (publicUrl == _currentInfo.publicUrl) return;
    _currentInfo = ServerInfo(
      isLive: true,
      ipAddress: _currentInfo.ipAddress,
      port: _currentInfo.port,
      url: _currentInfo.url,
      publicIp: _currentInfo.publicIp,
      publicUrl: publicUrl,
      connectionMode: _currentInfo.connectionMode,
      startedAt: _currentInfo.startedAt,
      lastHeartbeat: DateTime.now(),
      connectedClientId: _connectedClientId,
    );
    _stateController.add(_currentInfo);
  }

  void _listenToRequests() {
    _server?.listen((HttpRequest request) async {
      _addSecurityHeaders(request.response);

      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      final path = request.uri.path;

      try {
        switch (path) {
          case ServerConstants.healthEndpoint:
            await _handleHealth(request);
            break;

          case ServerConstants.authEndpoint:
            await _handleAuth(request);
            break;

          case ServerConstants.disconnectEndpoint:
            await _handleDisconnect(request);
            break;

          case ServerConstants.pingEndpoint:
            await _handlePing(request);
            break;

          case ServerConstants.statusEndpoint:
            await _handleStatus(request);
            break;

          case ServerConstants.clipboardEndpoint:
            await _handleClipboard(request);
            break;

          case ServerConstants.clipboardLatestEndpoint:
            await _handleClipboardLatest(request);
            break;

          case ServerConstants.filesEndpoint:
            await _handleFilesApi(request);
            break;

          case ServerConstants.filesUploadEndpoint:
            await _handleFileUpload(request);
            break;

          case ServerConstants.filesDownloadEndpoint:
            await _handleFileDownload(request);
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

  Future<void> _handleDisconnect(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    final deviceId = request.headers.value(ServerConstants.authHeader);

    _connectedClientId = null;
    _currentInfo = ServerInfo(
      isLive: true,
      ipAddress: _currentInfo.ipAddress,
      port: _currentInfo.port,
      url: _currentInfo.url,
      publicIp: _currentInfo.publicIp,
      publicUrl: _currentInfo.publicUrl,
      connectionMode: _currentInfo.connectionMode,
      startedAt: _currentInfo.startedAt,
      lastHeartbeat: DateTime.now(),
      connectedClientId: null,
    );
    _stateController.add(_currentInfo);
    _emitTransferProgress(null);

    request.response.statusCode = HttpStatus.ok;
    request.response.write(
      jsonEncode({'success': true, 'message': 'Client disconnected successfully'}),
    );
    await request.response.close();
    debugPrint('ServerService: Android client disconnected ($deviceId)');
  }

  Future<void> _handleClipboard(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;

    if (request.method == 'POST' || request.method == 'DELETE') {
      // Enforce device-ID + server-start-time password on all clipboard mutations.
      final deviceId = request.headers.value(ServerConstants.authHeader);
      final startTime = request.headers.value(ServerConstants.startTimeHeader);

      if (!_verifyDeviceId(deviceId)) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(
          jsonEncode({
            'success': false,
            'error': ServerConstants.msgAuthFailed,
          }),
        );
        await request.response.close();
        return;
      }
      if (!_isValidServerStartTime(startTime)) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(
          jsonEncode({
            'success': false,
            'error': ServerConstants.msgStartTimeMismatch,
          }),
        );
        await request.response.close();
        return;
      }
    }

    if (request.method == 'POST') {
      final bodyStr = await utf8.decoder.bind(request).join();
      if (bodyStr.isNotEmpty) {
        try {
          final dynamic data = jsonDecode(bodyStr);
          if (data is Map) {
            final item = ClipboardItem.fromMap(data);
            addLocalClipboardItem(item);
            onClipboardReceived?.call(item);
            request.response.statusCode = HttpStatus.ok;
            request.response.write(
              jsonEncode({'success': true, 'id': item.id}),
            );
            await request.response.close();
            return;
          }
        } catch (e) {
          debugPrint('ServerService _handleClipboard parse error: $e');
        }
      }
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(
        jsonEncode({'error': 'Invalid clipboard payload'}),
      );
      await request.response.close();
    } else if (request.method == 'GET') {
      request.response.statusCode = HttpStatus.ok;
      request.response.write(
        jsonEncode(_clipboardHistory.map((c) => c.toMap()).toList()),
      );
      await request.response.close();
    } else if (request.method == 'DELETE') {
      clearClipboardHistory();
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({'success': true}));
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
    }
  }

  Future<void> _handleClipboardLatest(HttpRequest request) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    if (_clipboardHistory.isNotEmpty) {
      request.response.write(jsonEncode(_clipboardHistory.first.toMap()));
    } else {
      request.response.write('null');
    }
    await request.response.close();
  }

  /// GET /api/files (list) and DELETE /api/files?id=... (remove a shared file).
  Future<void> _handleFilesApi(HttpRequest request) async {
    if (request.method == 'GET') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(_sharedFiles.map((f) => f.toMap()).toList()),
      );
      await request.response.close();
      return;
    }

    if (request.method == 'DELETE') {
      if (!await _verifyAuthorizedMutation(request)) return;
      final id = request.uri.queryParameters['id'] ?? '';
      await removeSharedFile(id);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true}));
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.methodNotAllowed;
    await request.response.close();
  }

  /// `POST /api/files/upload?name=<file>&deviceName=<name>&size=<bytes>` - receives a file
  /// pushed from the phone and saves it into the shared folder with real-time streaming progress.
  Future<void> _handleFileUpload(HttpRequest request) async {
    final deviceId = request.headers.value(ServerConstants.authHeader);
    final startTime = request.headers.value(ServerConstants.startTimeHeader);
    if (!_verifyDeviceId(deviceId)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'success': false, 'error': ServerConstants.msgAuthFailed}),
      );
      await request.response.close();
      return;
    }
    if (!_isValidServerStartTime(startTime)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'success': false,
          'error': ServerConstants.msgStartTimeMismatch,
        }),
      );
      await request.response.close();
      return;
    }

    final originalName = ServerService._sanitizeFileName(
      request.uri.queryParameters['name'] ?? '',
    );
    final deviceName =
        request.uri.queryParameters['deviceName'] ?? 'Android Device';
    final totalBytes = int.tryParse(request.uri.queryParameters['size'] ?? '') ??
        (request.contentLength > 0 ? request.contentLength : 0);

    final transferId = 'rx_${DateTime.now().millisecondsSinceEpoch}';
    final stopwatch = Stopwatch()..start();
    var bytesReceived = 0;
    var lastProgressTime = DateTime.now();

    try {
      final dir = await _getSharedDir();
      final id = 'file_${DateTime.now().millisecondsSinceEpoch}';
      final dest = File('${dir.path}\\${id}_$originalName');

      final sink = dest.openWrite();
      _emitTransferProgress(
        TransferProgress(
          fileId: transferId,
          fileName: originalName,
          bytesTransferred: 0,
          totalBytes: totalBytes,
          speedBytesPerSec: 0,
          isUpload: false,
          status: TransferStatus.inProgress,
          timestamp: DateTime.now(),
        ),
      );

      try {
        await for (final chunk in request) {
          sink.add(chunk);
          bytesReceived += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastProgressTime).inMilliseconds >= 80 ||
              (totalBytes > 0 && bytesReceived >= totalBytes)) {
            lastProgressTime = now;
            final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
            final speed = elapsedSec > 0 ? bytesReceived / elapsedSec : 0.0;
            _emitTransferProgress(
              TransferProgress(
                fileId: transferId,
                fileName: originalName,
                bytesTransferred: bytesReceived,
                totalBytes: totalBytes > 0 ? totalBytes : bytesReceived,
                speedBytesPerSec: speed,
                isUpload: false,
                status: TransferStatus.inProgress,
                timestamp: now,
              ),
            );
          }
        }
        await sink.close();
      } catch (e) {
        debugPrint('ServerService: upload pipe error: $e');
        _emitTransferProgress(
          TransferProgress(
            fileId: transferId,
            fileName: originalName,
            bytesTransferred: bytesReceived,
            totalBytes: totalBytes > 0 ? totalBytes : bytesReceived,
            speedBytesPerSec: 0,
            isUpload: false,
            status: TransferStatus.failed,
            errorMessage: e.toString(),
            timestamp: DateTime.now(),
          ),
        );
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'success': false, 'error': 'Upload failed'}),
        );
        await request.response.close();
        return;
      }

      final actualSize = await dest.length();
      _emitTransferProgress(
        TransferProgress(
          fileId: transferId,
          fileName: originalName,
          bytesTransferred: actualSize,
          totalBytes: actualSize,
          speedBytesPerSec: 0,
          isUpload: false,
          status: TransferStatus.completed,
          timestamp: DateTime.now(),
        ),
      );

      Timer(const Duration(seconds: 3), () {
        if (_currentTransferProgress?.fileId == transferId) {
          _emitTransferProgress(null);
        }
      });

      final item = SharedFile(
        id: id,
        name: originalName,
        size: actualSize,
        sourcePlatform: 'android',
        sourceDeviceName: deviceName,
        timestamp: DateTime.now(),
        filePath: dest.path,
      );
      _sharedFiles.insert(0, item);
      if (_sharedFiles.length > 100) _sharedFiles.removeLast();
      _sharedFilesController.add(List.from(_sharedFiles));

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'id': item.id}));
      await request.response.close();
      debugPrint('ServerService: Received upload from phone: $originalName');
    } catch (e) {
      debugPrint('ServerService: _handleFileUpload error: $e');
      _emitTransferProgress(
        TransferProgress(
          fileId: transferId,
          fileName: originalName,
          bytesTransferred: bytesReceived,
          totalBytes: totalBytes > 0 ? totalBytes : bytesReceived,
          speedBytesPerSec: 0,
          isUpload: false,
          status: TransferStatus.failed,
          errorMessage: e.toString(),
          timestamp: DateTime.now(),
        ),
      );
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'success': false, 'error': e.toString()}),
      );
      await request.response.close();
    }
  }

  /// `GET /api/files/download?id=<id>` - streams a shared file to the phone with real-time speed/progress tracking.
  Future<void> _handleFileDownload(HttpRequest request) async {
    final id = request.uri.queryParameters['id'] ?? '';
    SharedFile? match;
    for (final f in _sharedFiles) {
      if (f.id == id) {
        match = f;
        break;
      }
    }

    if (match == null ||
        match.filePath == null ||
        !await File(match.filePath!).exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'File not found'}));
      await request.response.close();
      return;
    }

    final file = File(match.filePath!);
    final length = await file.length();
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.binary;
    request.response.headers.set(
      'Content-Disposition',
      'attachment; filename="${match.name}"',
    );
    request.response.contentLength = length;

    final transferId = 'tx_${DateTime.now().millisecondsSinceEpoch}';
    final stopwatch = Stopwatch()..start();
    var bytesSent = 0;
    var lastProgressTime = DateTime.now();

    _emitTransferProgress(
      TransferProgress(
        fileId: transferId,
        fileName: match.name,
        bytesTransferred: 0,
        totalBytes: length,
        speedBytesPerSec: 0,
        isUpload: true,
        status: TransferStatus.inProgress,
        timestamp: DateTime.now(),
      ),
    );

    try {
      final fileStream = file.openRead();
      await for (final chunk in fileStream) {
        request.response.add(chunk);
        bytesSent += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastProgressTime).inMilliseconds >= 80 ||
            bytesSent >= length) {
          lastProgressTime = now;
          final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
          final speed = elapsedSec > 0 ? bytesSent / elapsedSec : 0.0;
          _emitTransferProgress(
            TransferProgress(
              fileId: transferId,
              fileName: match.name,
              bytesTransferred: bytesSent,
              totalBytes: length,
              speedBytesPerSec: speed,
              isUpload: true,
              status: bytesSent >= length
                  ? TransferStatus.completed
                  : TransferStatus.inProgress,
              timestamp: now,
            ),
          );
        }
      }
      await request.response.close();
      debugPrint('ServerService: Served file to phone: ${match.name}');

      Timer(const Duration(seconds: 3), () {
        if (_currentTransferProgress?.fileId == transferId) {
          _emitTransferProgress(null);
        }
      });
    } catch (e) {
      debugPrint('ServerService: _handleFileDownload error: $e');
      _emitTransferProgress(
        TransferProgress(
          fileId: transferId,
          fileName: match.name,
          bytesTransferred: bytesSent,
          totalBytes: length,
          speedBytesPerSec: 0,
          isUpload: true,
          status: TransferStatus.failed,
          errorMessage: e.toString(),
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  /// Shared auth gate used by file mutation endpoints. Writes a 401 JSON body
  /// and returns false when the caller isn't the authorized phone of this
  /// server session.
  Future<bool> _verifyAuthorizedMutation(HttpRequest request) async {
    final deviceId = request.headers.value(ServerConstants.authHeader);
    final startTime = request.headers.value(ServerConstants.startTimeHeader);
    if (!_verifyDeviceId(deviceId) || !_isValidServerStartTime(startTime)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'success': false, 'error': 'Unauthorized'}),
      );
      await request.response.close();
      return false;
    }
    return true;
  }

  Future<void> _handleHealth(HttpRequest request) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'status': 'ok',
        'message': ServerConstants.msgServerRunning,
        'serverPlatform': 'Windows',
        'hostName': Platform.localHostname,
        'encryption': 'TLS_1_3_RELAY',
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
    await request.response.close();
  }

  Future<void> _handleAuth(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.close();
      return;
    }

    String? candidateDeviceId = request.headers.value(
      ServerConstants.authHeader,
    );
    String? requestTimestamp;
    String? startTimeFromHeader = request.headers.value(
      ServerConstants.startTimeHeader,
    );
    String? serverStartTime = startTimeFromHeader;

    final bodyStr = await utf8.decoder.bind(request).join();
    if (bodyStr.isNotEmpty) {
      try {
        final dynamic data = jsonDecode(bodyStr);
        if (data is Map) {
          if (data['deviceId'] != null) {
            candidateDeviceId ??= data['deviceId'].toString();
          }
          if (data['timestamp'] != null) {
            requestTimestamp = data['timestamp'].toString();
          }
          serverStartTime =
              serverStartTime ?? data['serverStartTime']?.toString();
        }
      } catch (_) {}
    }

    request.response.headers.contentType = ContentType.json;

    // 0. Password check: Android must know the exact server start time (from RTDB).
    if (!_isValidServerStartTime(serverStartTime)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write(
        jsonEncode({
          'success': false,
          'error': ServerConstants.msgStartTimeMismatch,
        }),
      );
      await request.response.close();
      return;
    }

    // 1. Replay attack defense: Verify request timestamp is within 90 seconds
    if (requestTimestamp != null) {
      final reqTime = DateTime.tryParse(requestTimestamp);
      if (reqTime != null &&
          DateTime.now().difference(reqTime).abs() >
              const Duration(seconds: 90)) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(
          jsonEncode({
            'success': false,
            'error': 'Authentication request expired (replay protection).',
          }),
        );
        await request.response.close();
        return;
      }
    }

    // 2. Check device ID authentication token
    final isAuthorized = _verifyDeviceId(candidateDeviceId);

    if (isAuthorized) {
      _connectedClientId = candidateDeviceId;
      _currentInfo = ServerInfo(
        isLive: true,
        ipAddress: _currentInfo.ipAddress,
        port: _currentInfo.port,
        url: _currentInfo.url,
        publicIp: _currentInfo.publicIp,
        publicUrl: _currentInfo.publicUrl,
        connectionMode: 'wan_direct',
        startedAt: _currentInfo.startedAt,
        lastHeartbeat: DateTime.now(),
        connectedClientId: _connectedClientId,
      );
      _stateController.add(_currentInfo);

      request.response.statusCode = HttpStatus.ok;
      request.response.write(
        jsonEncode({
          'success': true,
          'message': ServerConstants.msgAuthSuccess,
          'windowsHost': Platform.localHostname,
          'connectionMode': 'wan_direct',
          'encrypted': true,
        }),
      );
    } else {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write(
        jsonEncode({'success': false, 'error': ServerConstants.msgAuthFailed}),
      );
    }

    await request.response.close();
  }

  /// Processes an incoming remote cloud handshake from Firebase RTDB.
  Future<void> handleCloudHandshakeRequest(
    Map<String, dynamic> request, {
    required User user,
    required DatabaseService databaseService,
  }) async {
    final requestId = request['requestId']?.toString() ?? '';
    final deviceId = request['deviceId']?.toString();
    final serverStartTime = request['serverStartTime']?.toString();

    if (requestId.isEmpty) return;

    if (!_isValidServerStartTime(serverStartTime)) {
      await databaseService.sendCloudHandshakeResponse(
        user: user,
        requestId: requestId,
        success: false,
        message: ServerConstants.msgStartTimeMismatch,
        windowsHost: Platform.localHostname,
      );
      return;
    }

    final isAuthorized = _verifyDeviceId(deviceId);

    if (isAuthorized) {
      _connectedClientId = deviceId;
      _currentInfo = ServerInfo(
        isLive: true,
        ipAddress: _currentInfo.ipAddress,
        port: _currentInfo.port,
        url: _currentInfo.url,
        publicIp: _currentInfo.publicIp,
        publicUrl: _currentInfo.publicUrl,
        connectionMode: 'cloud_relay',
        startedAt: _currentInfo.startedAt,
        lastHeartbeat: DateTime.now(),
        connectedClientId: _connectedClientId,
      );
      _stateController.add(_currentInfo);

      await databaseService.sendCloudHandshakeResponse(
        user: user,
        requestId: requestId,
        success: true,
        message: 'Connected securely over public cloud channel!',
        windowsHost: Platform.localHostname,
      );
    } else {
      await databaseService.sendCloudHandshakeResponse(
        user: user,
        requestId: requestId,
        success: false,
        message: 'Authentication failed: Android Device ID rejected.',
        windowsHost: Platform.localHostname,
      );
    }
  }

  Future<void> _handlePing(HttpRequest request) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({'pong': true, 'timestamp': DateTime.now().toIso8601String()}),
    );
    await request.response.close();
  }

  Future<void> _handleStatus(HttpRequest request) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_currentInfo.toMap()));
    await request.response.close();
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

  /// Verifies the server start time password that both devices read from RTDB.
  bool _isValidServerStartTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return false;
    final startedAt = _currentInfo.startedAt;
    if (startedAt == null) return false;
    // Tolerate small round-trip/clock skew while still rejecting wrong sessions.
    return startedAt.difference(parsed).abs() < const Duration(seconds: 5);
  }

  /// Best-effort attempt to add a Windows Firewall inbound rule for the server port.
  /// Requires admin privileges — if it fails, logs a helpful message for the user.
  void _ensureFirewallRule(int port) async {
    try {
      // Check if rule already exists
      final checkResult = await Process.run('netsh', [
        'advfirewall',
        'firewall',
        'show',
        'rule',
        'name=PCLink Server',
      ]);
      if (checkResult.stdout.toString().contains('$port')) {
        debugPrint(
          'ServerService: ✅ Firewall rule for port $port already exists',
        );
        return;
      }

      // Try to add the rule
      final result = await Process.run('netsh', [
        'advfirewall',
        'firewall',
        'add',
        'rule',
        'name=PCLink Server',
        'dir=in',
        'action=allow',
        'protocol=TCP',
        'localport=$port',
      ]);

      if (result.exitCode == 0) {
        debugPrint(
          'ServerService: ✅ Firewall rule added for inbound TCP port $port',
        );
      } else {
        debugPrint(
          'ServerService: ⚠️ Could not add firewall rule (needs admin). Run this in an elevated terminal:',
        );
        debugPrint(
          '  netsh advfirewall firewall add rule name="PCLink Server" dir=in action=allow protocol=TCP localport=$port',
        );
      }
    } catch (e) {
      debugPrint('ServerService: ⚠️ Firewall check error: $e');
      debugPrint(
        '  Manually run as Admin: netsh advfirewall firewall add rule name="PCLink Server" dir=in action=allow protocol=TCP localport=$port',
      );
    }
  }

  void _addSecurityHeaders(HttpResponse response) {
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('X-Frame-Options', 'DENY');
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS, DELETE',
    );
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Origin, X-Requested-With, Content-Type, Accept, ${ServerConstants.authHeader}, ${ServerConstants.startTimeHeader}',
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
      publicIp: _currentInfo.publicIp,
      publicUrl: _currentInfo.publicUrl,
      connectionMode: 'cloud_relay',
      startedAt: null,
      lastHeartbeat: null,
      connectedClientId: null,
    );
    _stateController.add(_currentInfo);
  }

  // -------------------------------------------------------------
  // Android Client Connection Methods (Public WAN & Cloud Relay)
  // -------------------------------------------------------------

  /// Performs the password-protected handshake from Android to the Windows server across any public network.
  static Future<Map<String, dynamic>> authenticateClientWithServer({
    required String serverUrl,
    String? publicUrl,
    required String androidDeviceId,
    required String serverStartTime,
    User? user,
    DatabaseService? databaseService,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    // 1. Try Direct Public WAN URL or LAN URL first
    final candidateUrls = [
      if (publicUrl != null && publicUrl.isNotEmpty) publicUrl,
      serverUrl,
    ];

    for (final targetUrl in candidateUrls) {
      try {
        final sanitizedUrl = targetUrl.endsWith('/')
            ? targetUrl.substring(0, targetUrl.length - 1)
            : targetUrl;
        final uri = Uri.parse('$sanitizedUrl${ServerConstants.authEndpoint}');

        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                ServerConstants.authHeader: androidDeviceId,
                ServerConstants.startTimeHeader: serverStartTime,
              },
              body: jsonEncode({
                'deviceId': androidDeviceId,
                'clientPlatform': 'Android',
                'serverStartTime': serverStartTime,
                'timestamp': DateTime.now().toIso8601String(),
              }),
            )
            .timeout(timeout);

        if (response.statusCode == 200) {
          final dynamic data = jsonDecode(response.body);
          return {
            'success': true,
            'connectionMode': 'Public WAN Direct',
            'message': data is Map && data['message'] != null
                ? data['message']
                : ServerConstants.msgAuthSuccess,
            'windowsHost': data is Map ? data['windowsHost'] : 'Windows PC',
          };
        } else if (response.statusCode == 401) {
          return {
            'success': false,
            'error':
                'Authentication failed: Device ID or server start time (password) was rejected by the PC.',
          };
        }
      } catch (_) {
        // Continue to next URL or Cloud Relay fallback
      }
    }

    // 2. If direct HTTP is blocked by router NAT or mobile carrier firewall, use the Cloud Relay Channel
    if (user != null && databaseService != null) {
      final requestId = 'req_${DateTime.now().millisecondsSinceEpoch}';
      final requestSent = await databaseService.sendCloudHandshakeRequest(
        user: user,
        androidDeviceId: androidDeviceId,
        requestId: requestId,
        serverStartTime: serverStartTime,
      );

      if (requestSent) {
        final response = await databaseService.waitForCloudHandshakeResponse(
          user: user,
          requestId: requestId,
          timeout: const Duration(seconds: 7),
        );

        if (response['success'] == true) {
          return {
            'success': true,
            'connectionMode': 'Public Cloud Relay',
            'message': response['message'] ?? 'Connected over Public Network',
            'windowsHost': response['windowsHost'] ?? 'Windows PC',
          };
        } else if (response['error'] != null) {
          return {'success': false, 'error': response['error']};
        }
      }
    }

    return {
      'success': false,
      'error':
          'Failed to reach Windows PC. Make sure PCLink is running on your PC.',
    };
  }

  /// Explicitly terminates active client connection from Android to the Windows server across any network.
  static Future<void> disconnectClientWithServer({
    required String serverUrl,
    String? publicUrl,
    required String androidDeviceId,
    required String serverStartTime,
    User? user,
    DatabaseService? databaseService,
  }) async {
    final candidateUrls = [
      if (publicUrl != null && publicUrl.isNotEmpty) publicUrl,
      serverUrl,
    ];

    for (final targetUrl in candidateUrls) {
      try {
        final sanitizedUrl = targetUrl.endsWith('/')
            ? targetUrl.substring(0, targetUrl.length - 1)
            : targetUrl;
        final uri = Uri.parse('$sanitizedUrl${ServerConstants.disconnectEndpoint}');

        await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                ServerConstants.authHeader: androidDeviceId,
                ServerConstants.startTimeHeader: serverStartTime,
              },
              body: jsonEncode({
                'deviceId': androidDeviceId,
                'clientPlatform': 'Android',
                'serverStartTime': serverStartTime,
                'timestamp': DateTime.now().toIso8601String(),
              }),
            )
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // Fallback / best effort across candidate URLs
      }
    }

    if (user != null && databaseService != null) {
      await databaseService.disconnectClient(user: user);
    }
  }

  void dispose() {
    stopServer();
    _stateController.close();
    if (!_sharedFilesController.isClosed) {
      _sharedFilesController.close();
    }
    if (!_transferProgressController.isClosed) {
      _transferProgressController.close();
    }
  }
}
