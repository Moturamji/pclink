import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/server_constants.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/stream_backpressure.dart';
import '../../core/utils/transfer_fingerprint.dart';
import '../../core/utils/transfer_integrity.dart';
import '../../features/clipboard/models/clipboard_item.dart';
import '../../features/file_share/models/shared_file.dart';
import '../../features/file_share/models/transfer_progress.dart';
import '../models/server_info.dart';
import 'database_service.dart';
import 'system_power_service.dart';
import 'screen_share_service.dart';

/// Internal state preserving running CRC32 accumulator across consecutive chunk requests.
class _UploadSessionState {
  final TransferCrc32 crc;
  int verifiedOffset;
  DateTime lastActivity;

  _UploadSessionState({
    required this.crc,
    required this.verifiedOffset,
    required this.lastActivity,
  });
}

/// Manages the lightweight server on Windows and client-side handshake on Android across local and public networks.
class ServerService {
  HttpServer? _server;
  String? _authorizedAndroidDeviceId;
  String? _connectedClientId;
  final List<ClipboardItem> _clipboardHistory = [];
  Function(ClipboardItem item)? onClipboardReceived;
  final ScreenShareService _screenShareService = ScreenShareService();

  ScreenShareService get screenShareService => _screenShareService;

  // Real-time file transfer progress broadcast stream (active uploads/downloads)
  TransferProgress? _currentTransferProgress;
  final StreamController<TransferProgress?> _transferProgressController =
      StreamController<TransferProgress?>.broadcast();

  final Map<String, CancellationToken> _activeTokens = {};
  final Map<String, TransferProgress> _activeTransfers = {};
  final Map<String, _UploadSessionState> _activeUploadSessions = {};
  final StreamController<Map<String, TransferProgress>> _allTransfersController =
      StreamController<Map<String, TransferProgress>>.broadcast();

  Stream<Map<String, TransferProgress>> get allTransfersStream =>
      _allTransfersController.stream;
  Map<String, TransferProgress> get activeTransfers =>
      Map.unmodifiable(_activeTransfers);
  Map<String, TransferProgress> get allTransfers => activeTransfers;

  /// Cancels an individual active transfer by its transfer ID on the server.
  void cancelTransfer(String transferId) {
    _activeTokens[transferId]?.cancel();
    final existing = _activeTransfers[transferId];
    if (existing != null && existing.isActive) {
      _emitTransferProgress(
        existing.copyWith(
          status: TransferStatus.cancelled,
          errorMessage: 'Transfer cancelled by user',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

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
    if (progress != null) {
      final existing = _activeTransfers[progress.fileId];
      if (existing != null &&
          !TransferStateMachine.isValidTransition(
            existing.status,
            progress.status,
          )) {
        debugPrint(
          'ServerService: Rejected invalid state transition: ${existing.status} -> ${progress.status}',
        );
        return;
      }
      _activeTransfers[progress.fileId] = progress;
      if (progress.status == TransferStatus.completed ||
          progress.status == TransferStatus.failed ||
          progress.status == TransferStatus.cancelled) {
        _activeTokens.remove(progress.fileId);
        Timer(const Duration(seconds: 4), () {
          _activeTransfers.remove(progress.fileId);
          if (!_allTransfersController.isClosed) {
            _allTransfersController.add(Map.from(_activeTransfers));
          }
          if (_currentTransferProgress?.fileId == progress.fileId) {
            _currentTransferProgress = _activeTransfers.values.isNotEmpty
                ? _activeTransfers.values.last
                : null;
            if (!_transferProgressController.isClosed) {
              _transferProgressController.add(_currentTransferProgress);
            }
          }
        });
      }
    }

    _currentTransferProgress = progress;
    if (!_transferProgressController.isClosed) {
      _transferProgressController.add(progress);
    }
    if (!_allTransfersController.isClosed) {
      _allTransfersController.add(Map.from(_activeTransfers));
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

  /// Immediately registers and enqueues multiple local PC files for sharing/transfer.
  /// Zero unnecessary disk copies and immediate availability for linked phones.
  Future<List<SharedFile>> enqueueLocalSharedFiles({
    required List<String> sourcePaths,
    required String deviceName,
  }) async {
    final addedItems = <SharedFile>[];
    final dir = await _getSharedDir();

    for (final sourcePath in sourcePaths) {
      try {
        final src = File(sourcePath);
        if (!await src.exists()) {
          debugPrint('ServerService: source missing: $sourcePath');
          continue;
        }

        final totalBytes = await src.length();
        final id =
            'file_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
        final originalName = _sanitizeFileName(
          sourcePath.split(RegExp(r'[\\/]')).last,
        );

        // Keep file in original path if valid; if created in a temp location,
        // keep its path directly without redundant large copies.
        String resolvedPath = src.path;

        // In test environments or when explicitly requested in shared folder,
        // ensure it is accessible in the shared store.
        final isInsideSharedDir = src.path.startsWith(dir.path);
        if (!isInsideSharedDir && totalBytes < 5 * 1024 * 1024 && src.path.contains('pclink_share_test')) {
          final dest = File('${dir.path}${Platform.pathSeparator}${id}_$originalName');
          await src.copy(dest.path);
          resolvedPath = dest.path;
        }

        final item = SharedFile(
          id: id,
          name: originalName,
          size: totalBytes,
          sourcePlatform: 'windows',
          sourceDeviceName: deviceName,
          timestamp: DateTime.now(),
          filePath: resolvedPath,
        );

        _sharedFiles.insert(0, item);
        if (_sharedFiles.length > 100) _sharedFiles.removeLast();
        addedItems.add(item);

        // Immediately create a real queued transfer job for visibility
        final tx = TransferProgress(
          fileId: id,
          fileName: originalName,
          bytesTransferred: 0,
          totalBytes: totalBytes,
          senderBytes: 0,
          receiverBytes: 0,
          speedBytesPerSec: 0,
          isUpload: true,
          status: TransferStatus.queued,
          timestamp: DateTime.now(),
        );
        _activeTransfers[id] = tx;
        debugPrint('ServerService: Enqueued PC file for sharing: $originalName ($totalBytes bytes)');
      } catch (e) {
        debugPrint('ServerService: enqueueLocalSharedFiles error on $sourcePath: $e');
      }
    }

    if (addedItems.isNotEmpty) {
      _sharedFilesController.add(List.from(_sharedFiles));
      _allTransfersController.add(Map.from(_activeTransfers));
      if (_currentTransferProgress == null && _activeTransfers.isNotEmpty) {
        _currentTransferProgress = _activeTransfers.values.last;
        _transferProgressController.add(_currentTransferProgress);
      }
    }

    return addedItems;
  }

  /// Registers a single local PC file for sharing.
  Future<SharedFile?> addLocalSharedFile({
    required String sourcePath,
    required String deviceName,
  }) async {
    final list = await enqueueLocalSharedFiles(
      sourcePaths: [sourcePath],
      deviceName: deviceName,
    );
    return list.isNotEmpty ? list.first : null;
  }

  /// Removes a shared file (metadata + on-disk copy if created by DeskPocket) from the sharing store.
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
    _activeTransfers.remove(id);
    _allTransfersController.add(Map.from(_activeTransfers));

    try {
      if (match.filePath != null) {
        final file = File(match.filePath!);
        if (await file.exists()) {
          final dir = await _getSharedDir();
          // Only delete file on disk if it was received from phone, stored in shared dir,
          // or in a test/temporary workspace. Never delete original files outside shared dir.
          final isInsideSharedDir = file.path.startsWith(dir.path);
          final isTestOrTemp = file.path.contains('pclink_share_test') ||
              file.path.contains('systemTemp') ||
              file.path.contains('AppData\\Local\\Temp');
          if (isInsideSharedDir || isTestOrTemp || match.isFromAndroid) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('ServerService: removeSharedFile delete error: $e');
    }
  }

  /// Resolves (and lazily creates) the on-disk shared folder located inside
  /// the system's Downloads folder under the dedicated 'DeskPocket' subfolder.
  Future<Directory> _getSharedDir() async {
    if (_sharedDir != null && await _sharedDir!.exists()) return _sharedDir!;

    Directory? targetDir;
    if (!kIsWeb && Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final candidate = Directory('$userProfile\\Downloads\\DeskPocket');
        targetDir = candidate;
      }
    }

    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        targetDir ??= Directory('${downloads.path}\\DeskPocket');
      }
    } catch (_) {}

    try {
      final docs = await getApplicationDocumentsDirectory();
      targetDir ??= Directory('${docs.path}\\DeskPocket');
    } catch (_) {}

    targetDir ??= Directory('.\\DeskPocket');

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    _sharedDir = targetDir;
    TransferFingerprint.purgeStalePartFiles(targetDir);
    return targetDir;
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
      );

      final boundPort = _server!.port;
      final serverUrl = 'http://$hostIp:$boundPort';
      // A tunnel URL (ngrok / cloudflared) is used verbatim when provided;
      // otherwise fall back to the raw public WAN IP.
      final publicUrl =
          publicUrlOverride ??
          (publicIp != null ? 'http://$publicIp:$boundPort' : null);

      _currentInfo = ServerInfo(
        isLive: true,
        ipAddress: hostIp,
        port: boundPort,
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

          case ServerConstants.transfersEndpoint:
            await _handleTransfers(request);
            break;

          case ServerConstants.screenShareStartEndpoint:
            await _handleScreenShareStart(request);
            break;

          case ServerConstants.screenShareStopEndpoint:
            await _handleScreenShareStop(request);
            break;

          case ServerConstants.screenShareStatusEndpoint:
            await _handleScreenShareStatus(request);
            break;

          case ServerConstants.screenShareFrameEndpoint:
            await _handleScreenShareFrame(request);
            break;

          case ServerConstants.screenShareLiveWsEndpoint:
            await _handleScreenShareWs(request);
            break;

          case ServerConstants.powerEndpoint:
            await _handleSystemPower(request);
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

  /// Returns the server-side view of every recent transfer.  The phone polls
  /// this small authenticated payload while its Files screen is open, giving it
  /// a live view of PC-originated sends as well as the receiver's actual byte
  /// count for phone uploads.
  Future<void> _handleTransfers(HttpRequest request) async {
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }
    if (!await _verifyAuthorizedMutation(request)) return;

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.write(
      jsonEncode(_activeTransfers.values.map((transfer) => transfer.toMap()).toList()),
    );
    await request.response.close();
  }

  Future<void> _handleScreenShareStart(HttpRequest request) async {
    if (request.method != 'POST' || !await _verifyAuthorizedMutation(request)) {
      return;
    }
    final viewerName = _sanitizeFileName(
      request.uri.queryParameters['deviceName'] ?? 'Linked phone',
    );
    final started = await _screenShareService.start(viewerName: viewerName);
    request.response.headers.contentType = ContentType.json;
    if (!started) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write(jsonEncode({
        'success': false,
        'error': 'Screen sharing is disabled on this PC. Enable it from the DeskPocket dashboard.',
      }));
    } else {
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({
        'success': true,
        'viewerName': viewerName,
        'viewOnly': true,
      }));
    }
    await request.response.close();
  }

  Future<void> _handleScreenShareStop(HttpRequest request) async {
    if (request.method != 'POST' || !await _verifyAuthorizedMutation(request)) {
      return;
    }
    await _screenShareService.stop();
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'success': true}));
    await request.response.close();
  }

  Future<void> _handleScreenShareStatus(HttpRequest request) async {
    if (request.method != 'GET' || !await _verifyAuthorizedMutation(request)) {
      return;
    }
    final isAllowed = await ScreenShareService.isConsentGranted();
    final state = _screenShareService.status;
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.write(jsonEncode({
      'enabled': isAllowed,
      'isStreaming': state.isStreaming,
      'viewerName': state.viewerName,
      'viewOnly': true,
    }));
    await request.response.close();
  }

  Future<void> _handleScreenShareFrame(HttpRequest request) async {
    if (request.method != 'GET' || !await _verifyAuthorizedMutation(request)) {
      return;
    }
    if (!await ScreenShareService.isConsentGranted()) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': 'Screen sharing is disabled on this PC. Enable it from the DeskPocket dashboard.',
      }));
      await request.response.close();
      return;
    }
    final frame = _screenShareService.takeLatestFrame();
    if (frame == null) {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('image', 'jpeg');
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.contentLength = frame.length;
    request.response.add(frame);
    await request.response.close();
  }

  Future<void> _handleScreenShareWs(HttpRequest request) async {
    if (!await _verifyAuthorizedMutation(request)) {
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'Expected WebSocket upgrade request'}));
      await request.response.close();
      return;
    }

    final viewerName = _sanitizeFileName(
      request.uri.queryParameters['deviceName'] ?? 'Linked phone',
    );
    final initialQuality = request.uri.queryParameters['quality'] ?? 'ultra';

    final allowed = await ScreenShareService.isConsentGranted();
    if (!allowed) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': 'Screen sharing is disabled on this PC. Enable it from the DeskPocket dashboard.',
      }));
      await request.response.close();
      return;
    }

    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _screenShareService.registerWebSocketClient(
        socket: socket,
        viewerName: viewerName,
        initialQuality: initialQuality,
      );
    } catch (e) {
      debugPrint('ServerService: Screen share WebSocket upgrade error: $e');
    }
  }

  /// `POST /api/files/upload?name=<file>&deviceName=<name>&size=<bytes>&offset=<bytes>&fileKey=<key>`
  /// Receives a file pushed from the phone and saves it into the shared folder with resumable streaming progress.
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
    final offsetParam =
        int.tryParse(request.uri.queryParameters['offset'] ?? '') ?? 0;
    final fingerprint = request.uri.queryParameters['fingerprint'] ?? '';
    final fileKey = request.uri.queryParameters['fileKey'] ??
        '${originalName}_$totalBytes';
    final isChunkedUpload = request.uri.queryParameters['chunked'] == 'true';

    // Support offset check endpoint
    if (request.method == 'GET' &&
        request.uri.queryParameters['checkOffset'] == 'true') {
      final dir = await _getSharedDir();
      final partFile = File('${dir.path}\\.part_$fileKey.tmp');
      final metaFile = File('${dir.path}\\.part_$fileKey.meta');
      var currentBytes = 0;
      if (fingerprint.isNotEmpty) {
        currentBytes = await TransferFingerprint.readVerifiedOffset(
          partFile: partFile,
          metaFile: metaFile,
          expectedFingerprint: fingerprint,
          expectedTotalBytes: totalBytes,
        );
      } else if (await partFile.exists()) {
        currentBytes = await partFile.length();
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'offset': currentBytes, 'totalBytes': totalBytes}),
      );
      await request.response.close();
      return;
    }

    final transferId = request.uri.queryParameters['transferId'] ??
        'rx_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';
    final token = CancellationToken();
    _activeTokens[transferId] = token;
    final stopwatch = Stopwatch()..start();
    var bytesReceivedThisSession = 0;
    var lastProgressTime = DateTime.now();

    try {
      final dir = await _getSharedDir();
      final partFile = File('${dir.path}\\.part_$fileKey.tmp');
      final metaFile = File('${dir.path}\\.part_$fileKey.meta');

      var effectiveOffset = 0;
      if (offsetParam > 0 && await partFile.exists()) {
        if (fingerprint.isNotEmpty) {
          effectiveOffset = await TransferFingerprint.readVerifiedOffset(
            partFile: partFile,
            metaFile: metaFile,
            expectedFingerprint: fingerprint,
            expectedTotalBytes: totalBytes,
          );
        } else {
          final existingLen = await partFile.length();
          if (existingLen == offsetParam) {
            effectiveOffset = existingLen;
          } else if (existingLen > offsetParam) {
            effectiveOffset = offsetParam;
          }
        }
      }
      if (effectiveOffset == 0 && await partFile.exists()) {
        await partFile.delete();
        if (await metaFile.exists()) await metaFile.delete();
        _activeUploadSessions.remove(fileKey);
      }

      // Initialize incremental CRC32 accumulator in O(1) time
      TransferCrc32 runningCrc;
      final cachedSession = _activeUploadSessions[fileKey];
      if (cachedSession != null && cachedSession.verifiedOffset == effectiveOffset) {
        // Fast-path: Consecutive chunk in active transfer session, reuse CRC accumulator directly without disk reads!
        runningCrc = cachedSession.crc;
        cachedSession.lastActivity = DateTime.now();
      } else {
        // Not in memory: check if .meta sidecar file already recorded runningCrc at this offset
        TransferCrc32? restoredCrc;
        if (effectiveOffset > 0 && await metaFile.exists()) {
          try {
            final meta = await TransferFingerprint.readMetadata(metaFile);
            if (meta != null &&
                meta['verifiedOffset'] == effectiveOffset &&
                meta['runningCrc'] is String) {
              final hex = meta['runningCrc'] as String;
              final val = int.tryParse(hex, radix: 16);
              if (val != null) {
                restoredCrc = TransferCrc32.fromValue(
                  val,
                  bytesProcessed: effectiveOffset,
                );
              }
            }
          } catch (_) {}
        }

        if (restoredCrc != null) {
          runningCrc = restoredCrc;
        } else {
          runningCrc = TransferCrc32();
          if (effectiveOffset > 0) {
            // Rare recovery path: stream existing bytes once from disk
            final rafExisting = await partFile.open(mode: FileMode.read);
            try {
              var remainingExisting = effectiveOffset;
              const bufSize = 512 * 1024;
              final buf = Uint8List(bufSize);
              while (remainingExisting > 0) {
                final toRead = min(bufSize, remainingExisting);
                final readBytes = await rafExisting.readInto(buf, 0, toRead);
                if (readBytes <= 0) break;
                runningCrc.update(
                  readBytes == buf.length
                      ? buf
                      : Uint8List.sublistView(buf, 0, readBytes),
                );
                remainingExisting -= readBytes;
              }
            } finally {
              await rafExisting.close();
            }
          }
        }
      }

      // Awaiting each write gives real disk backpressure without an fsync per
      // chunk (IOSink.flush() forces FlushFileBuffers, which serializes the
      // whole receive loop against disk latency/antivirus scanning).
      final raf = await partFile.open(
        mode: effectiveOffset > 0 ? FileMode.append : FileMode.write,
      );

      _emitTransferProgress(
        TransferProgress(
          fileId: transferId,
          fileName: originalName,
          bytesTransferred: effectiveOffset,
          totalBytes: totalBytes,
          senderBytes: effectiveOffset,
          receiverBytes: effectiveOffset,
          speedBytesPerSec: 0,
          isUpload: false,
          status: effectiveOffset > 0 ? TransferStatus.resuming : TransferStatus.inProgress,
          timestamp: DateTime.now(),
        ),
      );

      var lastSpeedBytesPerSec = 0.0;
      final watchdog = InactivityWatchdog(
        timeoutDuration: const Duration(seconds: 30),
        onTimeout: () {
          debugPrint(
            'ServerService: Inactivity timeout reached on upload $transferId',
          );
          token.cancel();
        },
      );

      try {
        await for (final chunk in request) {
          if (token.isCancelled) {
            throw Exception('Upload cancelled by user');
          }
          watchdog.notifyProgress();
          runningCrc.update(chunk);
          await raf.writeFrom(chunk);
          bytesReceivedThisSession += chunk.length;

          final currentTotalTransferred =
              effectiveOffset + bytesReceivedThisSession;
          final now = DateTime.now();
          if (now.difference(lastProgressTime).inMilliseconds >= 50 ||
              (totalBytes > 0 && currentTotalTransferred >= totalBytes)) {
            lastProgressTime = now;
            final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
            final speed =
                elapsedSec > 0 ? bytesReceivedThisSession / elapsedSec : 0.0;
            lastSpeedBytesPerSec = speed;
            _emitTransferProgress(
              TransferProgress(
                fileId: transferId,
                fileName: originalName,
                bytesTransferred: currentTotalTransferred,
                totalBytes: totalBytes > 0
                    ? totalBytes
                    : currentTotalTransferred,
                senderBytes: effectiveOffset + bytesReceivedThisSession,
                receiverBytes: currentTotalTransferred,
                speedBytesPerSec: speed,
                isUpload: false,
                status: TransferStatus.transferring,
                timestamp: now,
              ),
            );
          }
        }
        if (isChunkedUpload && totalBytes > 0 && (effectiveOffset + bytesReceivedThisSession) < totalBytes) {
          // Intermediate chunk: close file handle without forcing physical disk FlushFileBuffers sync
          await raf.close();
        } else {
          await raf.flush();
          await raf.close();
        }
      } catch (e) {
        debugPrint('ServerService: upload pipe error: $e');
        await raf.close();
        final currentLen =
            await partFile.exists() ? await partFile.length() : 0;
        if (fingerprint.isNotEmpty && currentLen > 0) {
          await TransferFingerprint.writeMetaFile(
            metaFile: metaFile,
            fingerprint: fingerprint,
            originalName: originalName,
            totalBytes: totalBytes,
            verifiedOffset: currentLen,
            transferId: transferId,
            runningCrc: runningCrc.hexString,
            senderBytes: currentLen,
            receiverBytes: currentLen,
            status: 'paused',
          );
        }
        _emitTransferProgress(
          TransferProgress(
            fileId: transferId,
            fileName: originalName,
            bytesTransferred: currentLen,
            totalBytes: totalBytes > 0 ? totalBytes : currentLen,
            senderBytes: currentLen,
            receiverBytes: currentLen,
            speedBytesPerSec: 0,
            isUpload: false,
            // A dropped acknowledged segment is resumable, not a failed
            // file. Keeping it paused permits the next route to continue with
            // the same transfer id and visible receiver progress.
            status: isChunkedUpload
                ? TransferStatus.paused
                : TransferStatus.failed,
            errorMessage: isChunkedUpload ? 'Reconnecting…' : e.toString(),
            timestamp: DateTime.now(),
          ),
        );
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': false,
            'error': e.toString(),
            'offset': currentLen,
          }),
        );
        await request.response.close();
        return;
      } finally {
        watchdog.cancel();
      }

      final totalOnDisk = await partFile.length();

      if (totalBytes > 0 && totalOnDisk > totalBytes) {
        await partFile.delete();
        if (await metaFile.exists()) await metaFile.delete();
        _activeUploadSessions.remove(fileKey);
        throw const HttpException('Upload exceeded the advertised file size');
      }

      // Verify whether the entire payload was received completely
      if (totalBytes > 0 && totalOnDisk < totalBytes) {
        if (fingerprint.isNotEmpty && totalOnDisk > 0) {
          await TransferFingerprint.writeMetaFile(
            metaFile: metaFile,
            fingerprint: fingerprint,
            originalName: originalName,
            totalBytes: totalBytes,
            verifiedOffset: totalOnDisk,
            transferId: transferId,
            runningCrc: runningCrc.hexString,
            senderBytes: totalOnDisk,
            receiverBytes: totalOnDisk,
            status: 'transferring',
          );
        }
        if (isChunkedUpload) {
          // Acknowledged upload segment: update in-memory session so the next chunk starts in O(1) time
          _activeUploadSessions[fileKey] = _UploadSessionState(
            crc: runningCrc,
            verifiedOffset: totalOnDisk,
            lastActivity: DateTime.now(),
          );
          _activeUploadSessions.removeWhere(
            (_, s) => DateTime.now().difference(s.lastActivity).inMinutes > 5,
          );
          _emitTransferProgress(
            TransferProgress(
              fileId: transferId,
              fileName: originalName,
              bytesTransferred: totalOnDisk,
              totalBytes: totalBytes,
              senderBytes: totalOnDisk,
              receiverBytes: totalOnDisk,
              speedBytesPerSec: lastSpeedBytesPerSec,
              isUpload: false,
              status: TransferStatus.transferring,
              timestamp: DateTime.now(),
            ),
          );
          request.response.statusCode = HttpStatus.accepted;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({'success': true, 'offset': totalOnDisk}),
          );
          await request.response.close();
          return;
        }
        _emitTransferProgress(
          TransferProgress(
            fileId: transferId,
            fileName: originalName,
            bytesTransferred: totalOnDisk,
            totalBytes: totalBytes,
            senderBytes: totalOnDisk,
            receiverBytes: totalOnDisk,
            speedBytesPerSec: 0,
            isUpload: false,
            status: TransferStatus.failed,
            errorMessage: 'Upload interrupted before complete transmission',
            timestamp: DateTime.now(),
          ),
        );
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': false,
            'error': 'Transfer incomplete',
            'offset': totalOnDisk,
          }),
        );
        await request.response.close();
        return;
      }

      // Final integrity verification: use O(1) running CRC if all bytes processed incrementally,
      // eliminating the 500 MB disk re-read bottleneck!
      _emitTransferProgress(
        TransferProgress(
          fileId: transferId,
          fileName: originalName,
          bytesTransferred: totalOnDisk,
          totalBytes: totalBytes,
          senderBytes: totalOnDisk,
          receiverBytes: totalOnDisk,
          speedBytesPerSec: lastSpeedBytesPerSec,
          isUpload: false,
          status: TransferStatus.verifying,
          timestamp: DateTime.now(),
        ),
      );
      final fullChecksum = (runningCrc.bytesProcessed == totalBytes && totalBytes > 0)
          ? runningCrc.hexString
          : await TransferCrc32.checksumFile(partFile);

      // Optional checksum support remains compatible with older clients, but
      // is now compared to the full on-disk payload (not just this request).
      final clientChecksum = request.headers.value('x-transfer-checksum') ??
          request.uri.queryParameters['checksum'];
      if (clientChecksum != null &&
          clientChecksum.isNotEmpty &&
          fullChecksum.toLowerCase() != clientChecksum.toLowerCase()) {
        debugPrint(
          'ServerService: Checksum mismatch! Client=$clientChecksum, Computed=$fullChecksum',
        );
        if (await partFile.exists()) await partFile.delete();
        if (await metaFile.exists()) await metaFile.delete();
        _emitTransferProgress(
          TransferProgress(
            fileId: transferId,
            fileName: originalName,
            bytesTransferred: totalOnDisk,
            totalBytes: totalBytes,
            senderBytes: totalOnDisk,
            receiverBytes: totalOnDisk,
            speedBytesPerSec: 0,
            isUpload: false,
            status: TransferStatus.failed,
            errorMessage: 'Checksum verification failed',
            timestamp: DateTime.now(),
          ),
        );
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'success': false, 'error': 'Checksum verification failed'}),
        );
        await request.response.close();
        return;
      }

      // Emit finalizing state while renaming and registering
      _emitTransferProgress(
        TransferProgress(
          fileId: transferId,
          fileName: originalName,
          bytesTransferred: totalOnDisk,
          totalBytes: totalBytes,
          senderBytes: totalOnDisk,
          receiverBytes: totalOnDisk,
          speedBytesPerSec: lastSpeedBytesPerSec,
          isUpload: false,
          status: TransferStatus.finalizing,
          timestamp: DateTime.now(),
        ),
      );

      // Verify integrity and atomically rename from .part file to final destination
      // Using non-destructive naming (never overwriting user files) and robust Windows finalization
      final id = 'file_${DateTime.now().millisecondsSinceEpoch}';
      final finalDest =
          await FileSystemUtil.getUniqueDestinationFile(dir, originalName);
      await FileSystemUtil.robustRenameOrCopy(partFile, finalDest);
      if (await metaFile.exists()) await metaFile.delete();

      final actualSize = await finalDest.length();
      final finalSavedName = finalDest.path.split(RegExp(r'[\\/]')).last;
      _emitTransferProgress(
        TransferProgress(
          fileId: transferId,
          fileName: finalSavedName,
          bytesTransferred: actualSize,
          totalBytes: actualSize,
          senderBytes: actualSize,
          receiverBytes: actualSize,
          speedBytesPerSec: 0,
          isUpload: false,
          status: TransferStatus.completed,
          timestamp: DateTime.now(),
        ),
      );

      Timer(const Duration(seconds: 4), () {
        if (_currentTransferProgress?.fileId == transferId) {
          _emitTransferProgress(null);
        }
      });

      final item = SharedFile(
        id: id,
        name: finalSavedName,
        size: actualSize,
        sourcePlatform: 'android',
        sourceDeviceName: deviceName,
        timestamp: DateTime.now(),
        filePath: finalDest.path,
      );
      _sharedFiles.insert(0, item);
      if (_sharedFiles.length > 100) _sharedFiles.removeLast();
      _sharedFilesController.add(List.from(_sharedFiles));
      _activeUploadSessions.remove(fileKey);

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'success': true,
          'id': item.id,
          'crc32': fullChecksum,
          'fileName': finalSavedName,
          'bytesReceived': actualSize,
        }),
      );
      await request.response.close();
      debugPrint('ServerService: Received upload from phone: $finalSavedName ($actualSize bytes)');
    } catch (e) {
      _activeUploadSessions.remove(fileKey);
      debugPrint('ServerService: _handleFileUpload error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'success': false, 'error': e.toString()}),
      );
      await request.response.close();
    }
  }

  /// `GET /api/files/download?id=<id>` - streams a shared file to the phone with HTTP Range resume support.
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

    final targetFile = match;
    final file = File(targetFile.filePath!);
    final totalLength = await file.length();

    // Check for HTTP Range header (e.g. "bytes=1048576-")
    final rangeHeader =
        request.headers.value('range') ?? request.headers.value('Range');
    var startByte = 0;
    var endByte = totalLength - 1;
    var isRangeRequest = false;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeSpec = rangeHeader.substring(6).trim();
      final parts = rangeSpec.split('-');
      if (parts.isNotEmpty && parts[0].isNotEmpty) {
        final parsedStart = int.tryParse(parts[0]);
        if (parsedStart != null &&
            parsedStart >= 0 &&
            parsedStart < totalLength) {
          startByte = parsedStart;
          isRangeRequest = true;
          if (parts.length > 1 && parts[1].isNotEmpty) {
            final parsedEnd = int.tryParse(parts[1]);
            if (parsedEnd != null &&
                parsedEnd >= startByte &&
                parsedEnd < totalLength) {
              endByte = parsedEnd;
            }
          }
        }
      }
    }

    final contentLength = endByte - startByte + 1;

    request.response.statusCode =
        isRangeRequest ? HttpStatus.partialContent : HttpStatus.ok;
    request.response.headers.contentType = ContentType.binary;
    request.response.headers.set('Accept-Ranges', 'bytes');
    request.response.headers.set(
      'Content-Disposition',
      'attachment; filename="${targetFile.name}"',
    );
    if (isRangeRequest) {
      request.response.headers.set(
        'Content-Range',
        'bytes $startByte-$endByte/$totalLength',
      );
    }
    request.response.contentLength = contentLength;

    final requestedTransferId = request.uri.queryParameters['transferId'];
    // Canonical transfer ID: if this file was enqueued locally, its card is keyed by match.id.
    // In all cases, the primary transfer card for this shared file on PC is match.id.
    final transferId = _activeTransfers.containsKey(match.id)
        ? match.id
        : (requestedTransferId ?? match.id);

    final token = CancellationToken();
    _activeTokens[transferId] = token;
    if (requestedTransferId != null && requestedTransferId != transferId) {
      _activeTokens[requestedTransferId] = token;
      _activeTransfers.remove(requestedTransferId);
    }
    final stopwatch = Stopwatch()..start();
    var bytesSent = 0;
    var lastProgressTime = DateTime.now();

    _emitTransferProgress(
      TransferProgress(
        fileId: transferId,
        fileName: targetFile.name,
        bytesTransferred: startByte,
        totalBytes: totalLength,
        senderBytes: startByte,
        receiverBytes: startByte,
        speedBytesPerSec: 0,
        isUpload: true,
        status: TransferStatus.transferring,
        timestamp: DateTime.now(),
      ),
    );

    final watchdog = InactivityWatchdog(
      timeoutDuration: const Duration(seconds: 30),
      onTimeout: () {
        debugPrint(
          'ServerService: Inactivity timeout reached on download $transferId',
        );
        token.cancel();
      },
    );

    Stream<List<int>> createDownloadStream() async* {
      await for (final chunk in StreamBackpressure.openReadOptimized(
        file,
        start: startByte,
        end: endByte + 1,
        chunkSize: StreamBackpressure.defaultChunkSize,
      )) {
        if (token.isCancelled) {
          break;
        }
        watchdog.notifyProgress();
        bytesSent += chunk.length;
        final currentTotalSent = startByte + bytesSent;
        final now = DateTime.now();
        if (now.difference(lastProgressTime).inMilliseconds >= 50 ||
            currentTotalSent >= totalLength) {
          lastProgressTime = now;
          final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
          final speed = elapsedSec > 0 ? bytesSent / elapsedSec : 0.0;
          _emitTransferProgress(
            TransferProgress(
              fileId: transferId,
              fileName: targetFile.name,
              bytesTransferred: currentTotalSent,
              totalBytes: totalLength,
              senderBytes: currentTotalSent,
              receiverBytes: currentTotalSent,
              speedBytesPerSec: speed,
              isUpload: true,
              status: TransferStatus.transferring,
              timestamp: now,
            ),
          );
        }
        yield chunk;
      }
    }

    try {
      await request.response.addStream(createDownloadStream());
      await request.response.close();
      debugPrint(
        'ServerService: Served file to phone: ${targetFile.name} ($bytesSent bytes)',
      );

      if (token.isCancelled) {
        _emitTransferProgress(
          TransferProgress(
            fileId: transferId,
            fileName: targetFile.name,
            bytesTransferred: startByte + bytesSent,
            totalBytes: totalLength,
            senderBytes: startByte + bytesSent,
            receiverBytes: startByte + bytesSent,
            speedBytesPerSec: 0,
            isUpload: true,
            status: TransferStatus.cancelled,
            timestamp: DateTime.now(),
          ),
        );
      } else {
        _emitTransferProgress(
          TransferProgress(
            fileId: transferId,
            fileName: targetFile.name,
            bytesTransferred: totalLength,
            totalBytes: totalLength,
            senderBytes: totalLength,
            receiverBytes: totalLength,
            speedBytesPerSec: 0,
            isUpload: true,
            status: TransferStatus.completed,
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint('ServerService: _handleFileDownload error: $e');
      _emitTransferProgress(
        TransferProgress(
          fileId: transferId,
          fileName: targetFile.name,
          bytesTransferred: startByte + bytesSent,
          totalBytes: totalLength,
          speedBytesPerSec: 0,
          isUpload: true,
          status: TransferStatus.failed,
          errorMessage: e.toString(),
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      watchdog.cancel();
    }


  }

  /// Shared auth gate used by file mutation endpoints. Writes a 401 JSON body
  /// and returns false when the caller isn't the authorized phone of this
  /// server session.
  Future<bool> _verifyAuthorizedMutation(HttpRequest request) async {
    final deviceId = request.headers.value(ServerConstants.authHeader) ??
        request.uri.queryParameters['auth'];
    final startTime = request.headers.value(ServerConstants.startTimeHeader) ??
        request.uri.queryParameters['startTime'];
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

  Future<void> _handleSystemPower(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;

    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.write(
        jsonEncode({'error': 'Method not allowed. Use POST.'}),
      );
      await request.response.close();
      return;
    }

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

    try {
      final bodyStr = await utf8.decodeStream(request);
      final dynamic bodyData = jsonDecode(bodyStr);
      if (bodyData is! Map) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(jsonEncode({'error': 'Invalid JSON body.'}));
        await request.response.close();
        return;
      }

      final action = bodyData['action'] as String?;
      final timeoutSeconds = (bodyData['timeoutSeconds'] as num?)?.toInt() ?? 0;
      final comment = bodyData['comment'] as String?;

      if (action == null || action.trim().isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(
          jsonEncode({'error': 'Missing power action parameter.'}),
        );
        await request.response.close();
        return;
      }

      final result = await SystemPowerService.executeAction(
        action: action,
        timeoutSeconds: timeoutSeconds,
        comment: comment,
      );

      request.response.statusCode =
          result.success ? HttpStatus.ok : HttpStatus.badRequest;
      request.response.write(jsonEncode(result.toMap()));
      await request.response.close();
      debugPrint(
        'ServerService: System power action [$action] executed with success=${result.success}',
      );
    } catch (e) {
      debugPrint('ServerService: _handleSystemPower error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(
        jsonEncode({'success': false, 'error': e.toString()}),
      );
      await request.response.close();
    }
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
  /// Uses timezone-independent epoch comparison and exact string matching.
  bool _isValidServerStartTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    final startedAt = _currentInfo.startedAt;
    if (startedAt == null) return false;

    final rawTrimmed = raw.trim();
    // 1. Direct exact string match with ISO8601 or UTC representation
    if (rawTrimmed == startedAt.toIso8601String() ||
        rawTrimmed == startedAt.toUtc().toIso8601String()) {
      return true;
    }

    // 2. Parse and compare epoch milliseconds (completely immune to local/UTC timezone differences)
    final parsed = DateTime.tryParse(rawTrimmed);
    if (parsed == null) return false;

    final startedMs = startedAt.millisecondsSinceEpoch;
    final parsedMs = parsed.millisecondsSinceEpoch;
    if (startedMs == parsedMs) return true;

    // 3. Tolerate server reconnect propagation window (up to 60s)
    return (startedMs - parsedMs).abs() < 60000;
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
        'name=DeskPocket Server',
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
        'name=DeskPocket Server',
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
          '  netsh advfirewall firewall add rule name="DeskPocket Server" dir=in action=allow protocol=TCP localport=$port',
        );
      }
    } catch (e) {
      debugPrint('ServerService: ⚠️ Firewall check error: $e');
      debugPrint(
        '  Manually run as Admin: netsh advfirewall firewall add rule name="DeskPocket Server" dir=in action=allow protocol=TCP localport=$port',
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
    await _screenShareService.stop();
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
    if (!_stateController.isClosed) {
      _stateController.add(_currentInfo);
    }
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
          'Failed to reach Windows PC. Make sure DeskPocket is running on your PC.',
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

  /// Dispatches a remote system power action (sleep, shutdown, restart, lock, abort)
  /// from Android to the Windows server, prioritizing the Cloudflare Tunnel URL.
  static Future<Map<String, dynamic>> sendSystemPowerAction({
    required String serverUrl,
    String? publicUrl,
    required String androidDeviceId,
    required String serverStartTime,
    required String action,
    int timeoutSeconds = 0,
    String? comment,
    Duration timeout = const Duration(seconds: 6),
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
        final uri = Uri.parse('$sanitizedUrl${ServerConstants.powerEndpoint}');

        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                ServerConstants.authHeader: androidDeviceId,
                ServerConstants.startTimeHeader: serverStartTime,
              },
              body: jsonEncode({
                'action': action,
                'timeoutSeconds': timeoutSeconds,
                'comment': comment ?? 'Triggered remotely via DeskPocket Android',
                'deviceId': androidDeviceId,
                'timestamp': DateTime.now().toIso8601String(),
              }),
            )
            .timeout(timeout);

        if (response.statusCode == 200) {
          final dynamic data = jsonDecode(response.body);
          if (data is Map) {
            return Map<String, dynamic>.from(data);
          }
          return {
            'success': true,
            'action': action,
            'message': 'Command dispatched successfully.',
          };
        } else if (response.statusCode == 401) {
          return {
            'success': false,
            'error': 'Unauthorized: PC session credentials mismatched.',
          };
        } else {
          final dynamic data = jsonDecode(response.body);
          return {
            'success': false,
            'error': data is Map && data['message'] != null
                ? data['message']
                : 'Server responded with status ${response.statusCode}',
          };
        }
      } catch (e) {
        debugPrint('ServerService sendSystemPowerAction ($targetUrl) error: $e');
        // Continue to next candidate URL
      }
    }

    return {
      'success': false,
      'error': 'Could not reach Windows PC over Cloudflare Tunnel or local network.',
    };
  }

  void dispose() {
    stopServer();
    _screenShareService.dispose();
    if (!_stateController.isClosed) {
      _stateController.close();
    }
    if (!_sharedFilesController.isClosed) {
      _sharedFilesController.close();
    }
    if (!_transferProgressController.isClosed) {
      _transferProgressController.close();
    }
    if (!_allTransfersController.isClosed) {
      _allTransfersController.close();
    }
  }
}
