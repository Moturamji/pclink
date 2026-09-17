import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/server_constants.dart';
import '../../core/utils/cancellation_token.dart';
import '../../core/utils/stream_backpressure.dart';
import '../../core/utils/transfer_fingerprint.dart';
import '../../core/utils/transfer_integrity.dart';
import '../../features/file_share/models/shared_file.dart';
import '../../features/file_share/models/transfer_progress.dart';
import 'screen_share_start_result.dart';

/// Android client for the Windows temporary server's file-sharing API.
///
/// Discovers the PC via adaptive candidate URLs (public WAN/tunnel first, then LAN),
/// sends auth headers, transfers file bytes directly in streaming chunks,
/// and stores files in the public Downloads/PCLink directory with MediaStore indexing.
class FileShareService {
  static const MethodChannel _storageChannel =
      MethodChannel('com.example.pclink/storage');

  final http.Client _client = http.Client();

  List<String> Function()? _getTargetServerUrls;
  String? Function()? _getServerStartTime;
  String? _deviceId;
  String? _currentDeviceName;

  // Real-time file transfer progress broadcast stream (active uploads/downloads)
  TransferProgress? _currentProgress;
  final StreamController<TransferProgress?> _progressController =
      StreamController<TransferProgress?>.broadcast();

  final Map<String, CancellationToken> _activeTokens = {};
  final Map<String, TransferProgress> _activeTransfers = {};
  final StreamController<Map<String, TransferProgress>> _allTransfersController =
      StreamController<Map<String, TransferProgress>>.broadcast();

  Stream<TransferProgress?> get progressStream => _progressController.stream;
  Stream<Map<String, TransferProgress>> get allTransfersStream =>
      _allTransfersController.stream;
  TransferProgress? get currentProgress => _currentProgress;
  Map<String, TransferProgress> get activeTransfers =>
      Map.unmodifiable(_activeTransfers);

  void _emitProgress(TransferProgress? progress) {
    if (progress != null) {
      final existing = _activeTransfers[progress.fileId];
      if (existing != null &&
          !TransferStateMachine.isValidTransition(
            existing.status,
            progress.status,
          )) {
        debugPrint(
          'FileShareService: Rejected invalid state transition: ${existing.status} -> ${progress.status}',
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
          if (_currentProgress?.fileId == progress.fileId) {
            _currentProgress = _activeTransfers.values.isNotEmpty
                ? _activeTransfers.values.last
                : null;
            if (!_progressController.isClosed) {
              _progressController.add(_currentProgress);
            }
          }
        });
      }
    }
    _currentProgress = progress;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
    if (!_allTransfersController.isClosed) {
      _allTransfersController.add(Map.from(_activeTransfers));
    }
  }

  void configure({
    required List<String> Function()? getTargetServerUrls,
    required String? Function()? getServerStartTime,
    required String? deviceId,
    required String? deviceName,
  }) {
    _getTargetServerUrls = getTargetServerUrls;
    _getServerStartTime = getServerStartTime;
    _deviceId = deviceId;
    _currentDeviceName = deviceName;
  }

  /// Cancels an individual transfer by its unique transfer ID without affecting other transfers.
  void cancelTransfer(String transferId) {
    final token = _activeTokens[transferId];
    if (token != null) {
      token.cancel();
    }
    final existing = _activeTransfers[transferId];
    if (existing != null && existing.isActive) {
      _emitProgress(
        existing.copyWith(
          status: TransferStatus.cancelled,
          errorMessage: 'Transfer cancelled by user',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  /// Cancels all active upload or download transfers immediately.
  void cancelActiveTransfers() {
    for (final token in List.of(_activeTokens.values)) {
      token.cancel();
    }
    for (final entry in List.of(_activeTransfers.entries)) {
      if (entry.value.isActive) {
        _emitProgress(
          entry.value.copyWith(
            status: TransferStatus.cancelled,
            errorMessage: 'Transfer cancelled by user',
            timestamp: DateTime.now(),
          ),
        );
      }
    }
  }

  final Set<String> _deadUrls = <String>{};

  /// A single candidate route must accept the connection within this window;
  /// otherwise the transfer fails over to the next address (e.g. LAN).
  static const Duration _connectTimeout = Duration(seconds: 15);

  /// How long the server may take to confirm a fully transmitted upload
  /// (checksum verification + finalization happen before it answers).
  static const Duration _uploadConfirmTimeout = Duration(seconds: 120);

  /// How long the receiver may stay silent before a transfer counts as stalled.
  static const Duration _streamStallTimeout = Duration(seconds: 30);

  /// Files smaller than this never probe for a resumable server-side part file:
  /// the extra round trip costs more than simply re-sending the file.
  static const int _resumeProbeMinBytes = 1 * 1024 * 1024;

  /// Whether stale `.part`/`.meta` leftovers were already cleaned up in this
  /// process. Purging happens once instead of on every download attempt.
  bool _purgedStaleParts = false;

  /// All candidate PC server URLs (public WAN first, then LAN), deduplicated.
  List<String> _candidateUrls() {
    final list = _getTargetServerUrls?.call();
    if (list == null || list.isEmpty) return const <String>[];
    final result = <String>[];
    for (final raw in list) {
      if (raw.isEmpty) continue;
      final s = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
      if (!result.contains(s) && !_deadUrls.contains(s)) {
        result.add(s);
      }
    }
    if (result.isEmpty) {
      for (final raw in list) {
        if (raw.isEmpty) continue;
        final s = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
        if (!result.contains(s)) result.add(s);
      }
    }
    return result;
  }

  /// Picks a legal status for the start of a candidate-route attempt. A retry
  /// can follow a partially completed attempt on another route, so a plain
  /// `connecting` would be rejected by the state machine; in that case the
  /// closest legal non-terminal status is used instead.
  TransferStatus _attemptStartStatus(TransferStatus? current) {
    if (current == null) return TransferStatus.connecting;
    for (final candidate in const [
      TransferStatus.connecting,
      TransferStatus.resuming,
      TransferStatus.transferring,
      TransferStatus.inProgress,
    ]) {
      if (TransferStateMachine.isValidTransition(current, candidate)) {
        return candidate;
      }
    }
    // Same-status emits are always accepted: keeps the live panel ticking.
    return current;
  }

  /// Emits a terminal `cancelled` state for a transfer that was cancelled
  /// before any route attempt began (e.g. during fingerprinting), and drops
  /// its token registration so later `cancelTransfer` calls stay no-ops.
  void _emitEarlyCancelled(
    String transferId,
    String name,
    int totalBytes, {
    required bool isUpload,
  }) {
    _activeTokens.remove(transferId);
    _emitProgress(
      TransferProgress(
        fileId: transferId,
        fileName: name,
        bytesTransferred: 0,
        totalBytes: totalBytes,
        speedBytesPerSec: 0,
        isUpload: isUpload,
        status: TransferStatus.cancelled,
        errorMessage: 'Transfer cancelled by user',
        timestamp: DateTime.now(),
      ),
    );
    Timer(const Duration(seconds: 3), () {
      if (_currentProgress?.fileId == transferId) {
        _emitProgress(null);
      }
    });
  }

  /// Headers that prove this device is the registered Android phone and knows
  /// the current server session (start time) - the file-sharing password.
  Map<String, String> _authHeaders({String? contentType}) {
    final headers = <String, String>{};
    if (contentType != null) headers['Content-Type'] = contentType;
    final deviceId = _deviceId;
    if (deviceId != null && deviceId.isNotEmpty) {
      headers[ServerConstants.authHeader] = deviceId;
    }
    final startTime = _getServerStartTime?.call();
    if (startTime != null && startTime.isNotEmpty) {
      headers[ServerConstants.startTimeHeader] = startTime;
    }
    return headers;
  }

  /// Tries every candidate URL until one responds. Returns null on total failure.
  Future<http.Response?> _tryUrlFallback(
    Future<http.Response> Function(String baseUrl) send,
  ) async {
    final urls = _candidateUrls();
    if (urls.isEmpty) return null;

    for (final url in urls) {
      final tunnel = url.startsWith('https://');
      try {
        final resp = await send(
          url,
        ).timeout(Duration(seconds: tunnel ? 15 : 8));
        return resp;
      } catch (e) {
        final isUnresolvable = e.toString().contains('Failed host lookup') ||
            e.toString().contains('No address associated with hostname');
        if (isUnresolvable) {
          _deadUrls.add(url);
          debugPrint('FileShareService: Pruned unresolvable host: $url');
        } else {
          debugPrint('FileShareService: $url unreachable - $e');
        }
      }
    }
    return null;
  }

  /// Fetches the current list of shared files (from both devices) off the PC.
  Future<List<SharedFile>> listSharedFiles() async {
    final response = await _tryUrlFallback(
      (url) => _client.get(Uri.parse('$url${ServerConstants.filesEndpoint}')),
    );
    if (response == null || response.statusCode != 200) return <SharedFile>[];

    try {
      final dynamic data = jsonDecode(response.body);
      if (data is! List) return <SharedFile>[];
      return data.whereType<Map>().map((m) => SharedFile.fromMap(m)).toList();
    } catch (e) {
      debugPrint('FileShareService listSharedFiles decode error: $e');
      return <SharedFile>[];
    }
  }

  /// Fetches transfer activity measured by the PC.  This gives the phone a
  /// live view of PC-originated sharing/preparation work without pretending
  /// that the sender and receiver must report identical byte counts.
  Future<List<TransferProgress>> listRemoteTransfers() async {
    final response = await _tryUrlFallback(
      (url) => _client
          .get(
            Uri.parse('$url${ServerConstants.transfersEndpoint}'),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 3)),
    );
    if (response == null || response.statusCode != HttpStatus.ok) {
      return const <TransferProgress>[];
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const <TransferProgress>[];
      return decoded
          .whereType<Map>()
          .map(TransferProgress.tryFromMap)
          .whereType<TransferProgress>()
          .toList();
    } catch (e) {
      debugPrint('FileShareService listRemoteTransfers decode error: $e');
      return const <TransferProgress>[];
    }
  }

  /// Requests a view-only session from the paired Windows PC. The PC remains
  /// the authority: it can deny the request or stop the session at any time.
  Future<ScreenShareStartResult> startScreenShare() async {
    final deviceName = Uri.encodeQueryComponent(_currentDeviceName ?? 'Linked phone');
    final response = await _tryUrlFallback(
      (url) => _client.post(
        Uri.parse('$url${ServerConstants.screenShareStartEndpoint}?deviceName=$deviceName'),
        headers: _authHeaders(),
      ),
    );
    if (response == null) {
      return const ScreenShareStartResult(
        started: false,
        message: 'PC Link is unavailable. Check that your PC is online.',
      );
    }
    try {
      final body = jsonDecode(response.body);
      final message = body is Map ? body['error'] as String? : null;
      return ScreenShareStartResult(
        started: response.statusCode == HttpStatus.ok,
        message: message ??
            (response.statusCode == HttpStatus.ok
                ? 'Live view started.'
                : 'Screen sharing could not start.'),
      );
    } catch (_) {
      return ScreenShareStartResult(
        started: response.statusCode == HttpStatus.ok,
        message: response.statusCode == HttpStatus.ok
            ? 'Live view started.'
            : 'Screen sharing could not start.',
      );
    }
  }

  Future<void> stopScreenShare() async {
    await _tryUrlFallback(
      (url) => _client.post(
        Uri.parse('$url${ServerConstants.screenShareStopEndpoint}'),
        headers: _authHeaders(),
      ),
    );
  }

  /// Gets the most recent in-memory JPEG frame. No frame is written to phone
  /// storage, and a null result simply means the next frame is not ready yet.
  Future<Uint8List?> getScreenShareFrame() async {
    final response = await _tryUrlFallback(
      (url) => _client.get(
        Uri.parse('$url${ServerConstants.screenShareFrameEndpoint}'),
        headers: _authHeaders(),
      ),
    );
    if (response == null || response.statusCode != HttpStatus.ok) return null;
    return response.bodyBytes;
  }

  /// Industry-style acknowledged upload: a bounded segment is confirmed by the
  /// PC before the next is read.  This avoids one long tunnel request being the
  /// single point of failure for videos, while keeping memory pressure bounded.
  Future<bool> uploadFile(
    String filePath, {
    CancellationToken? cancelToken,
    String? customTransferId,
  }) async {
    // 2 MB is large enough to keep Wi-Fi/tunnel throughput healthy but small
    // enough to retry cheaply on a phone with limited memory.
    const segmentSize = 2 * 1024 * 1024;
    final urls = _candidateUrls();
    if (urls.isEmpty) return false;

    final file = File(filePath);
    final transferId = customTransferId ??
        'tx_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';
    final token = cancelToken ?? CancellationToken();
    _activeTokens[transferId] = token;
    if (!await file.exists()) {
      _activeTokens.remove(transferId);
      return false;
    }

    final totalBytes = await file.length();
    final name = filePath.split(RegExp(r'[\\/]')).last;
    _emitProgress(
      TransferProgress(
        fileId: transferId,
        fileName: name,
        bytesTransferred: 0,
        totalBytes: totalBytes,
        isUpload: true,
        status: TransferStatus.preparing,
        timestamp: DateTime.now(),
      ),
    );
    // Give the selected-file state a frame before even the lightweight resume
    // fingerprint work begins.
    await Future<void>.delayed(Duration.zero);
    if (token.isCancelled) {
      _emitEarlyCancelled(transferId, name, totalBytes, isUpload: true);
      return false;
    }

    final fingerprint = await TransferFingerprint.computeSourceFingerprint(file);
    final encodedName = Uri.encodeQueryComponent(name);
    final deviceName = Uri.encodeQueryComponent(
      _currentDeviceName ?? 'Android Device',
    );
    final stopwatch = Stopwatch()..start();

    for (final baseUrl in urls) {
      if (token.isCancelled) break;
      try {
        var offset = 0;
        final checkUri = Uri.parse(
          '$baseUrl${ServerConstants.filesUploadEndpoint}?checkOffset=true&name=$encodedName&size=$totalBytes&fileKey=${encodedName}_$totalBytes&fingerprint=$fingerprint',
        );
        final check = await _client
            .get(checkUri, headers: _authHeaders())
            .timeout(const Duration(seconds: 5));
        if (check.statusCode == HttpStatus.ok) {
          final data = jsonDecode(check.body);
          final savedOffset = data is Map ? data['offset'] : null;
          if (savedOffset is int && savedOffset >= 0 && savedOffset < totalBytes) {
            offset = savedOffset;
          }
        }

        _emitProgress(
          TransferProgress(
            fileId: transferId,
            fileName: name,
            bytesTransferred: offset,
            totalBytes: totalBytes,
            isUpload: true,
            status: offset > 0 ? TransferStatus.resuming : TransferStatus.transferring,
            timestamp: DateTime.now(),
          ),
        );

        final source = await file.open(mode: FileMode.read);
        try {
          while (offset < totalBytes && !token.isCancelled) {
            await source.setPosition(offset);
            final bytes = await source.read(min(segmentSize, totalBytes - offset));
            if (bytes.isEmpty) throw const FileSystemException('Source file ended early');
            final nextOffset = offset + bytes.length;
            final isFinalSegment = nextOffset == totalBytes;
            final uri = Uri.parse(
              '$baseUrl${ServerConstants.filesUploadEndpoint}?name=$encodedName&deviceName=$deviceName&size=$totalBytes&offset=$offset&fileKey=${encodedName}_$totalBytes&transferId=$transferId&fingerprint=$fingerprint&chunked=true',
            );
            final request = http.Request('POST', uri)
              ..bodyBytes = bytes
              ..headers.addAll(_authHeaders(contentType: 'application/octet-stream'));
            final chunkCrc = TransferCrc32()..update(bytes);
            request.headers['X-Chunk-Checksum'] = chunkCrc.hexString;

            // Keep the status honest during the receiver's final validation.
            final Future<String>? sourceChecksum = isFinalSegment
                ? TransferCrc32.checksumFile(file)
                : null;
            if (isFinalSegment) {
              _emitProgress(
                TransferProgress(
                  fileId: transferId,
                  fileName: name,
                  bytesTransferred: offset,
                  totalBytes: totalBytes,
                  isUpload: true,
                  status: TransferStatus.verifying,
                  timestamp: DateTime.now(),
                ),
              );
            }
            final response = await _client.send(request).timeout(
              // Each segment is intentionally short-lived. Failing over after
              // 35 seconds is better than leaving a phone stuck on one dead
              // tunnel request for minutes.
              const Duration(seconds: 35),
            );
            final responseBody = await response.stream.bytesToString();
            if (response.statusCode != HttpStatus.accepted &&
                response.statusCode != HttpStatus.ok) {
              throw HttpException('PC rejected upload segment (${response.statusCode})');
            }
            final payload = jsonDecode(responseBody);
            final acknowledged = payload is Map ? payload['offset'] ?? payload['bytesReceived'] : null;
            if (acknowledged is! int || acknowledged <= offset || acknowledged > nextOffset) {
              throw const HttpException('PC returned an invalid upload acknowledgement');
            }
            offset = acknowledged;
            final seconds = stopwatch.elapsedMilliseconds / 1000;
            _emitProgress(
              TransferProgress(
                fileId: transferId,
                fileName: name,
                bytesTransferred: offset,
                totalBytes: totalBytes,
                speedBytesPerSec: seconds > 0 ? offset / seconds : 0,
                isUpload: true,
                status: response.statusCode == HttpStatus.ok
                    ? TransferStatus.verifying
                    : TransferStatus.transferring,
                timestamp: DateTime.now(),
              ),
            );
            if (response.statusCode == HttpStatus.ok) {
              final serverCrc = payload is Map ? payload['crc32'] : null;
              final sourceCrc = await sourceChecksum!;
              if (serverCrc is! String || serverCrc.toLowerCase() != sourceCrc.toLowerCase()) {
                throw const HttpException('The received file did not pass integrity verification');
              }
              _emitProgress(
                TransferProgress(
                  fileId: transferId,
                  fileName: name,
                  bytesTransferred: totalBytes,
                  totalBytes: totalBytes,
                  isUpload: true,
                  status: TransferStatus.completed,
                  timestamp: DateTime.now(),
                ),
              );
              return true;
            }
          }
        } finally {
          await source.close();
        }
      } catch (e) {
        debugPrint('FileShareService: chunk route $baseUrl interrupted: $e');
        // The PC records every accepted segment.  Continue with the next route
        // and resume from its last confirmed byte instead of restarting.
      }
    }

    if (token.isCancelled) {
      _emitEarlyCancelled(transferId, name, totalBytes, isUpload: true);
    } else {
      _emitProgress(
        TransferProgress(
          fileId: transferId,
          fileName: name,
          bytesTransferred: 0,
          totalBytes: totalBytes,
          isUpload: true,
          status: TransferStatus.failed,
          errorMessage: 'Connection interrupted. You can retry and PCLink will resume.',
          timestamp: DateTime.now(),
        ),
      );
    }
    return false;
  }

  /// Previous single-request implementation retained temporarily for reference
  /// while rolling out chunked uploads.
  Future<bool> _uploadFileLegacy(
    String filePath, {
    CancellationToken? cancelToken,
    String? customTransferId,
  }) async {
    final urls = _candidateUrls();
    if (urls.isEmpty) {
      debugPrint('FileShareService uploadFile: no candidate server URLs');
      return false;
    }

    try {
      final file = File(filePath);
      final transferId = customTransferId ??
          'tx_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';
      final token = cancelToken ?? CancellationToken();
      // Registered before ANY async work (file stat, fingerprinting, probing)
      // so a cancel arriving during `preparing` can never be lost.
      _activeTokens[transferId] = token;
      if (token.isCancelled) {
        _emitEarlyCancelled(
          transferId,
          filePath.split(RegExp(r'[\\/]')).last,
          0,
          isUpload: true,
        );
        return false;
      }

      if (!await file.exists()) {
        _activeTokens.remove(transferId);
        return false;
      }

      final totalBytes = await file.length();
      final name = filePath.split(RegExp(r'[\\/]')).last;
      final encodedName = Uri.encodeQueryComponent(name);
      final deviceName = Uri.encodeQueryComponent(
        _currentDeviceName ?? 'Android Device',
      );
      if (token.isCancelled) {
        _emitEarlyCancelled(transferId, name, totalBytes, isUpload: true);
        return false;
      }
      final fingerprint =
          await TransferFingerprint.computeSourceFingerprint(file);
      if (token.isCancelled) {
        _emitEarlyCancelled(transferId, name, totalBytes, isUpload: true);
        return false;
      }

      _emitProgress(
        TransferProgress(
          fileId: transferId,
          fileName: name,
          bytesTransferred: 0,
          totalBytes: totalBytes,
          speedBytesPerSec: 0,
          isUpload: true,
          status: TransferStatus.preparing,
          timestamp: DateTime.now(),
        ),
      );

      for (final baseUrl in urls) {
        if (token.isCancelled) break;
        try {
          // 1. Check if the server already has a verified partial .part file for
          // this upload. Small files skip the probe: the extra round trip costs
          // more than simply restarting them.
          var existingOffset = 0;
          if (totalBytes >= _resumeProbeMinBytes) {
            try {
              final checkUri = Uri.parse(
                '$baseUrl${ServerConstants.filesUploadEndpoint}?checkOffset=true&name=$encodedName&size=$totalBytes&fileKey=${encodedName}_$totalBytes&fingerprint=$fingerprint',
              );
              final checkResp = await _client
                  .get(checkUri, headers: _authHeaders())
                  .timeout(const Duration(seconds: 4));
              if (checkResp.statusCode == 200) {
                final dynamic data = jsonDecode(checkResp.body);
                if (data is Map && data['offset'] is int) {
                  final serverOffset = data['offset'] as int;
                  if (serverOffset > 0 && serverOffset < totalBytes) {
                    existingOffset = serverOffset;
                    debugPrint(
                      'FileShareService: Resuming upload from byte $existingOffset / $totalBytes',
                    );
                  }
                }
              }
            } catch (_) {
              // Check offset is optional, fallback to 0 if unsupported
            }
          }

          final uri = Uri.parse(
            '$baseUrl${ServerConstants.filesUploadEndpoint}?name=$encodedName&deviceName=$deviceName&size=$totalBytes&offset=$existingOffset&fileKey=${encodedName}_$totalBytes&transferId=$transferId&fingerprint=$fingerprint',
          );

          // Aborts this attempt the instant the route stalls or the user cancels, so a
          // dead address (stale tunnel / black-holed WAN route) can never hang the
          // transfer until the OS TCP timeout before failing over to the LAN.
          final abortTrigger = Completer<void>();
          void requestAbort() {
            if (!abortTrigger.isCompleted) abortTrigger.complete();
          }

          token.onCancelled(requestAbort);

          final request = BackpressuredBodyRequest(
            'POST',
            uri,
            abortTrigger: abortTrigger.future,
          );
          final headers = _authHeaders(contentType: 'application/octet-stream');
          headers.forEach((key, val) => request.headers[key] = val);
          request.contentLength = totalBytes - existingOffset;

          final stopwatch = Stopwatch()..start();
          var bytesSentThisSession = 0;
          var lastProgressTime = DateTime.now();
          var lastSpeedBytesPerSec = 0.0;
          final crcCalculator = TransferCrc32();

          final responseFuture = _client.send(request);
          // The abort path (user cancel / watchdog / route failover) can reject
          // this future at any moment - including while the body loop below is
          // unwinding with its own error - so mark it as handled immediately to
          // prevent an unhandled zone error. The awaits further down still
          // observe the result/error normally.
          responseFuture.ignore();

          final watchdog = InactivityWatchdog(
            timeoutDuration: const Duration(seconds: 30),
            onTimeout: () {
              debugPrint(
                'FileShareService: Inactivity timeout reached on upload $transferId',
              );
              requestAbort();
            },
          );

          _emitProgress(
            TransferProgress(
              fileId: transferId,
              fileName: name,
              bytesTransferred: existingOffset,
              totalBytes: totalBytes,
              speedBytesPerSec: 0,
              isUpload: true,
              status: _attemptStartStatus(_activeTransfers[transferId]?.status),
              timestamp: DateTime.now(),
            ),
          );

          var sendCompleted = false;
          try {
            // The file is only read once the connection is actually up, so a dead
            // route can neither buffer the whole file in memory nor make the
            // progress bar report bytes that were never transmitted.
            await request.connected.timeout(_connectTimeout);
            watchdog.notifyProgress();

            _emitProgress(
              TransferProgress(
                fileId: transferId,
                fileName: name,
                bytesTransferred: existingOffset,
                totalBytes: totalBytes,
                speedBytesPerSec: 0,
                isUpload: true,
                status: existingOffset > 0
                    ? TransferStatus.resuming
                    : TransferStatus.transferring,
                timestamp: DateTime.now(),
              ),
            );

            await for (final chunk in StreamBackpressure.openReadOptimized(
              file,
              start: existingOffset,
              chunkSize: StreamBackpressure.defaultChunkSize,
            )) {
              if (token.isCancelled) break;
              watchdog.notifyProgress();
              crcCalculator.update(chunk);
              // Wait for the socket to drain before reading the next chunk:
              // reading and hashing are throttled by the real network rate.
              await request.write(chunk);
              bytesSentThisSession += chunk.length;
              final currentTotalSent = existingOffset + bytesSentThisSession;

              final now = DateTime.now();
              if (now.difference(lastProgressTime).inMilliseconds >= 50 ||
                  currentTotalSent >= totalBytes) {
                lastProgressTime = now;
                final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
                final speed =
                    elapsedSec > 0 ? bytesSentThisSession / elapsedSec : 0.0;
                lastSpeedBytesPerSec = speed;
                _emitProgress(
                  TransferProgress(
                    fileId: transferId,
                    fileName: name,
                    bytesTransferred: currentTotalSent,
                    totalBytes: totalBytes,
                    speedBytesPerSec: speed,
                    isUpload: true,
                    status: TransferStatus.transferring,
                    timestamp: now,
                  ),
                );
              }
            }

            await request.finish();
            sendCompleted = !token.isCancelled;
          } on TimeoutException {
            debugPrint(
              'FileShareService: $baseUrl did not accept the connection for $transferId',
            );
            requestAbort();
          } on BodyStreamClosedException {
            // Route aborted or cancelled - resolved from the state below.
          } catch (e) {
            debugPrint('FileShareService: Upload streaming to $baseUrl failed: $e');
            requestAbort();
          } finally {
            token.removeListener(requestAbort);
          }

          if (token.isCancelled) {
            watchdog.cancel();
            // Drain/ignore client exception on aborted request socket
            responseFuture.then<http.StreamedResponse?>(
              (r) => r,
              onError: (e, s) => null,
            );
            _emitProgress(
              TransferProgress(
                fileId: transferId,
                fileName: name,
                bytesTransferred: existingOffset + bytesSentThisSession,
                totalBytes: totalBytes,
                speedBytesPerSec: 0,
                isUpload: true,
                status: TransferStatus.cancelled,
                timestamp: DateTime.now(),
              ),
            );
            return false;
          }

          if (!sendCompleted) {
            // Route died (stalled connect, dropped socket or watchdog abort) -
            // try the next candidate address instead of hanging on this one.
            watchdog.cancel();
            requestAbort();
            responseFuture.then<http.StreamedResponse?>(
              (r) => r,
              onError: (e, s) => null,
            );
            debugPrint(
              'FileShareService: Upload via $baseUrl did not complete - trying next route',
            );
            continue;
          }

          // Local file has been completely sent, but receiver must verify & finalize!
          // Progress strictly stays below 100% until receiver returns 200 OK.
          _emitProgress(
            TransferProgress(
              fileId: transferId,
              fileName: name,
              bytesTransferred: totalBytes,
              totalBytes: totalBytes,
              speedBytesPerSec: lastSpeedBytesPerSec,
              isUpload: true,
              status: TransferStatus.verifying,
              timestamp: DateTime.now(),
            ),
          );

          // For a resumed upload the running checksum only covers the bytes
          // sent in this attempt.  Start a streamed full-source checksum while
          // the PC verifies its temporary file, so the final comparison covers
          // every byte without holding the UI at a fake 100% state.
          final sourceChecksumFuture = existingOffset == 0
              ? Future<String>.value(crcCalculator.hexString)
              : TransferCrc32.checksumFile(file);

          http.StreamedResponse? streamedResponse;
          try {
            // The receiver answers only after checksum verification and
            // finalization, so this guards the confirmation - not the transfer.
            streamedResponse = await responseFuture.timeout(
              _uploadConfirmTimeout,
            );
          } on TimeoutException {
            debugPrint(
              'FileShareService: no confirmation from $baseUrl for $transferId',
            );
            requestAbort();
          } catch (e) {
            debugPrint('FileShareService: Upload response from $baseUrl failed: $e');
          } finally {
            watchdog.cancel();
          }

          if (streamedResponse == null) continue;

          if (streamedResponse.statusCode == 200) {
            final respBody = await streamedResponse.stream.bytesToString();
            try {
              final dynamic decoded = jsonDecode(respBody);
              if (decoded is Map && decoded['crc32'] is String) {
                final serverCrc = decoded['crc32'] as String;
                final sourceCrc = await sourceChecksumFuture;
                if (serverCrc.toLowerCase() != sourceCrc.toLowerCase()) {
                  debugPrint(
                    'FileShareService: Integrity verification failed! Client=$sourceCrc, Server=$serverCrc',
                  );
                  _emitProgress(
                    TransferProgress(
                      fileId: transferId,
                      fileName: name,
                      bytesTransferred: totalBytes,
                      totalBytes: totalBytes,
                      speedBytesPerSec: 0,
                      isUpload: true,
                      status: TransferStatus.failed,
                      errorMessage:
                          'Integrity check failed (CRC mismatch)',
                      timestamp: DateTime.now(),
                    ),
                  );
                  return false;
                }
              }
            } catch (_) {}

            _emitProgress(
              TransferProgress(
                fileId: transferId,
                fileName: name,
                bytesTransferred: totalBytes,
                totalBytes: totalBytes,
                speedBytesPerSec: 0,
                isUpload: true,
                status: TransferStatus.completed,
                timestamp: DateTime.now(),
              ),
            );
            Timer(const Duration(seconds: 3), () {
              if (_currentProgress?.fileId == transferId) {
                _emitProgress(null);
              }
            });
            return true;
          }

        } catch (e) {
          debugPrint('FileShareService: Upload to $baseUrl failed: $e');
        }
      }

      if (token.isCancelled) {
        _emitEarlyCancelled(transferId, name, totalBytes, isUpload: true);
        return false;
      }

      _emitProgress(
        TransferProgress(
          fileId: transferId,
          fileName: name,
          bytesTransferred: 0,
          totalBytes: totalBytes,
          speedBytesPerSec: 0,
          isUpload: true,
          status: TransferStatus.failed,
          errorMessage: 'Upload failed across all available routes.',
          timestamp: DateTime.now(),
        ),
      );
      Timer(const Duration(seconds: 3), () {
        if (_currentProgress?.fileId == transferId) {
          _emitProgress(null);
        }
      });
      return false;
    } catch (e) {
      debugPrint('FileShareService: uploadFile fatal error: $e');
      return false;
    }
  }

  /// Downloads a shared file from the PC with resumable Range header support.
  Future<File?> downloadFile(
    SharedFile item, {
    CancellationToken? cancelToken,
    String? customTransferId,
  }) async {
    final urls = _candidateUrls();
    if (urls.isEmpty) {
      debugPrint('FileShareService: No server URLs configured for download');
      return null;
    }

    final totalBytes = item.size;
    final transferId = customTransferId ??
        'rx_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';
    final token = cancelToken ?? CancellationToken();
    _activeTokens[transferId] = token;

    _emitProgress(
      TransferProgress(
        fileId: transferId,
        fileName: item.name,
        bytesTransferred: 0,
        totalBytes: totalBytes,
        speedBytesPerSec: 0,
        isUpload: false,
        status: TransferStatus.preparing,
        timestamp: DateTime.now(),
      ),
    );

    for (final baseUrl in urls) {
      if (token.isCancelled) break;
      try {
        final dir = await _getPCLinkDownloadDir();
        if (!_purgedStaleParts) {
          _purgedStaleParts = true;
          // Leftover `.part`/`.meta` fragments from crashed transfers are only
          // worth a directory scan once per process, not per download attempt.
          await TransferFingerprint.purgeStalePartFiles(dir);
        }
        final partFile = File(
          '${dir.path}${Platform.pathSeparator}.part_${item.id}_${item.name}',
        );

        var existingBytes = 0;
        if (await partFile.exists()) {
          existingBytes = await partFile.length();
          if (existingBytes >= totalBytes) {
            // Already fully downloaded in .part file! Verify and finalize non-destructively
            final finalDest =
                await FileSystemUtil.getUniqueDestinationFile(dir, item.name);
            await FileSystemUtil.robustRenameOrCopy(partFile, finalDest);
            await _notifyMediaScanner(finalDest.path);
            _emitProgress(
              TransferProgress(
                fileId: transferId,
                fileName: item.name,
                bytesTransferred: totalBytes,
                totalBytes: totalBytes,
                speedBytesPerSec: 0,
                isUpload: false,
                status: TransferStatus.completed,
                timestamp: DateTime.now(),
              ),
            );
            return finalDest;
          }
        }

        final uri = Uri.parse(
          '$baseUrl${ServerConstants.filesDownloadEndpoint}?id=${Uri.encodeQueryComponent(item.id)}&transferId=$transferId',
        );

        final request = http.Request('GET', uri);
        final headers = _authHeaders();
        headers.forEach((k, v) => request.headers[k] = v);

        if (existingBytes > 0) {
          request.headers['Range'] = 'bytes=$existingBytes-';
          debugPrint(
            'FileShareService: Resuming download from byte $existingBytes / $totalBytes',
          );
        }

        // Connect/headers must arrive promptly, otherwise this route is dead.
        final http.StreamedResponse streamedResponse;
        try {
          streamedResponse = await _client.send(request).timeout(
                _connectTimeout,
              );
        } on TimeoutException {
          debugPrint(
            'FileShareService: Download from $baseUrl timed out while connecting',
          );
          continue;
        }

        if (streamedResponse.statusCode != 200 &&
            streamedResponse.statusCode != 206) {
          continue;
        }

        final isPartial = streamedResponse.statusCode == 206;
        final startOffset = isPartial ? existingBytes : 0;
        // RandomAccessFile writes are awaited, which provides true disk
        // backpressure without the fsync stalls of IOSink.flush() per chunk.
        final raf = await partFile.open(
          mode: isPartial ? FileMode.append : FileMode.write,
        );

        final stopwatch = Stopwatch()..start();
        var bytesReceivedThisSession = 0;
        var lastProgressTime = DateTime.now();
        var lastSpeedBytesPerSec = 0.0;

        final watchdog = InactivityWatchdog(
          timeoutDuration: _streamStallTimeout,
          onTimeout: () {
            // The stalled response stream raises a TimeoutException which fails
            // this route over to the next one; the `.part` file is kept so the
            // retry resumes instead of starting over from zero.
            debugPrint(
              'FileShareService: download $transferId stalled with no data',
            );
          },
        );

        try {
          await for (final chunk in streamedResponse.stream.timeout(
            _streamStallTimeout,
          )) {
            if (token.isCancelled) break;
            watchdog.notifyProgress();
            await raf.writeFrom(chunk);
            bytesReceivedThisSession += chunk.length;

            final currentTotal = startOffset + bytesReceivedThisSession;

            final now = DateTime.now();
            if (now.difference(lastProgressTime).inMilliseconds >= 50 ||
                currentTotal >= totalBytes) {
              lastProgressTime = now;
              final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
              final speed =
                  elapsedSec > 0 ? bytesReceivedThisSession / elapsedSec : 0.0;
              lastSpeedBytesPerSec = speed;
              _emitProgress(
                TransferProgress(
                  fileId: transferId,
                  fileName: item.name,
                  bytesTransferred: currentTotal,
                  totalBytes: totalBytes,
                  speedBytesPerSec: speed,
                  isUpload: false,
                  status: TransferStatus.transferring,
                  timestamp: now,
                ),
              );
            }
          }
          await raf.flush();
          await raf.close();
        } catch (e) {
          await raf.close();
          // Keep partFile for subsequent resume retry
          rethrow;
        } finally {
          watchdog.cancel();
        }

        if (token.isCancelled) {
          if (await partFile.exists()) await partFile.delete();
          _emitProgress(
            TransferProgress(
              fileId: transferId,
              fileName: item.name,
              bytesTransferred: startOffset + bytesReceivedThisSession,
              totalBytes: totalBytes,
              speedBytesPerSec: 0,
              isUpload: false,
              status: TransferStatus.cancelled,
              timestamp: DateTime.now(),
            ),
          );
          return null;
        }

        final totalDownloaded = await partFile.length();
        if (totalBytes > 0 && totalDownloaded < totalBytes) {
          _emitProgress(
            TransferProgress(
              fileId: transferId,
              fileName: item.name,
              bytesTransferred: totalDownloaded,
              totalBytes: totalBytes,
              speedBytesPerSec: 0,
              isUpload: false,
              status: TransferStatus.failed,
              errorMessage: 'Download incomplete',
              timestamp: DateTime.now(),
            ),
          );
          return null;
        }

        // Verify and finalize state transitions
        _emitProgress(
          TransferProgress(
            fileId: transferId,
            fileName: item.name,
            bytesTransferred: totalBytes,
            totalBytes: totalBytes,
            speedBytesPerSec: lastSpeedBytesPerSec,
            isUpload: false,
            status: TransferStatus.verifying,
            timestamp: DateTime.now(),
          ),
        );

        _emitProgress(
          TransferProgress(
            fileId: transferId,
            fileName: item.name,
            bytesTransferred: totalBytes,
            totalBytes: totalBytes,
            speedBytesPerSec: lastSpeedBytesPerSec,
            isUpload: false,
            status: TransferStatus.finalizing,
            timestamp: DateTime.now(),
          ),
        );

        // Atomically rename .part file to destination file non-destructively and notify media scanner
        final finalDest =
            await FileSystemUtil.getUniqueDestinationFile(dir, item.name);
        await FileSystemUtil.robustRenameOrCopy(partFile, finalDest);
        await _notifyMediaScanner(finalDest.path);

        final finalSavedName = finalDest.path.split(RegExp(r'[\\/]')).last;
        _emitProgress(
          TransferProgress(
            fileId: transferId,
            fileName: finalSavedName,
            bytesTransferred: totalBytes,
            totalBytes: totalBytes,
            speedBytesPerSec: 0,
            isUpload: false,
            status: TransferStatus.completed,
            timestamp: DateTime.now(),
          ),
        );

        Timer(const Duration(seconds: 3), () {
          if (_currentProgress?.fileId == transferId) {
            _emitProgress(null);
          }
        });


        return finalDest;
      } catch (e) {
        debugPrint('FileShareService: Download from $baseUrl failed: $e');
      }
    }

    _emitProgress(
      TransferProgress(
        fileId: transferId,
        fileName: item.name,
        bytesTransferred: 0,
        totalBytes: totalBytes,
        speedBytesPerSec: 0,
        isUpload: false,
        status: TransferStatus.failed,
        errorMessage: 'Download failed across all available routes.',
        timestamp: DateTime.now(),
      ),
    );
    Timer(const Duration(seconds: 3), () {
      if (_currentProgress?.fileId == transferId) {
        _emitProgress(null);
      }
    });

    return null;
  }

  /// Notifies the Android MediaScanner to index the newly downloaded file.
  Future<void> _notifyMediaScanner(String filePath) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _storageChannel.invokeMethod('scanFile', {'path': filePath});
      } catch (e) {
        debugPrint('FileShareService: scanFile invoke error: $e');
      }
    }
  }

  /// Resolves (and lazily creates) the standard device Downloads/PCLink folder.
  Future<Directory> _getPCLinkDownloadDir() async {
    if (!kIsWeb && Platform.isAndroid) {
      // 1. Try native Android environment API for Downloads
      try {
        final String? nativePath =
            await _storageChannel.invokeMethod<String>('getPublicDownloadsDirectory');
        if (nativePath != null && nativePath.isNotEmpty) {
          final nativeDir = Directory(nativePath);
          if (!await nativeDir.exists()) {
            await nativeDir.create(recursive: true);
          }
          return nativeDir;
        }
      } catch (e) {
        debugPrint('FileShareService: Native getPublicDownloadsDirectory error: $e');
      }

      // 2. Direct Android primary storage Download folder
      final androidDownload = Directory('/storage/emulated/0/Download/PCLink');
      try {
        if (!await androidDownload.exists()) {
          await androidDownload.create(recursive: true);
        }
        return androidDownload;
      } catch (e) {
        debugPrint(
          'FileShareService: Falling back from /storage/emulated/0/Download/PCLink: $e',
        );
      }

      // 3. App-accessible external storage directories
      try {
        final extDirs = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (extDirs != null && extDirs.isNotEmpty) {
          final candidate =
              Directory('${extDirs.first.path}${Platform.pathSeparator}PCLink');
          if (!await candidate.exists()) {
            await candidate.create(recursive: true);
          }
          return candidate;
        }
      } catch (e) {
        debugPrint('FileShareService: External downloads fallback error: $e');
      }
    }

    // 4. Standard path_provider getDownloadsDirectory
    Directory? targetDir;
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        targetDir = Directory(
          '${downloads.path}${Platform.pathSeparator}PCLink',
        );
      }
    } catch (_) {}

    // 5. Fallback to Documents/PCLink
    try {
      final docs = await getApplicationDocumentsDirectory();
      targetDir ??= Directory(
        '${docs.path}${Platform.pathSeparator}PCLink',
      );
    } catch (_) {}

    targetDir ??= Directory('.${Platform.pathSeparator}PCLink');

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    return targetDir;
  }

  void dispose() {
    _client.close();
    if (!_progressController.isClosed) {
      _progressController.close();
    }
  }
}
