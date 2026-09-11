import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/server_constants.dart';
import '../../features/file_share/models/shared_file.dart';
import '../../features/file_share/models/transfer_progress.dart';

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

  TransferProgress? _currentProgress;
  final StreamController<TransferProgress?> _progressController =
      StreamController<TransferProgress?>.broadcast();

  bool _isCancelled = false;

  Stream<TransferProgress?> get progressStream => _progressController.stream;
  TransferProgress? get currentProgress => _currentProgress;

  void _emitProgress(TransferProgress? progress) {
    _currentProgress = progress;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
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

  /// Cancels any active upload or download streams immediately.
  void cancelActiveTransfers() {
    _isCancelled = true;
    if (_currentProgress != null &&
        _currentProgress!.status == TransferStatus.inProgress) {
      _emitProgress(
        _currentProgress!.copyWith(
          status: TransferStatus.cancelled,
          errorMessage: 'Transfer cancelled by user',
          timestamp: DateTime.now(),
        ),
      );
      Timer(const Duration(seconds: 2), () {
        _emitProgress(null);
      });
    }
  }

  /// All candidate PC server URLs (public WAN first, then LAN), deduplicated.
  List<String> _candidateUrls() {
    final list = _getTargetServerUrls?.call();
    if (list == null || list.isEmpty) return const <String>[];
    final result = <String>[];
    for (final raw in list) {
      if (raw.isEmpty) continue;
      final s = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
      if (!result.contains(s)) result.add(s);
    }
    return result;
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
        debugPrint('FileShareService: $url unreachable - $e');
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

  /// Uploads a local file from phone to PC with real-time streaming progress, percentage, and speed tracking.
  Future<bool> uploadFile(String filePath) async {
    _isCancelled = false;
    final urls = _candidateUrls();
    if (urls.isEmpty) {
      debugPrint('FileShareService uploadFile: no candidate server URLs');
      return false;
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final totalBytes = await file.length();
      final name = filePath.split(RegExp(r'[\\/]')).last;
      final encodedName = Uri.encodeQueryComponent(name);
      final deviceName = Uri.encodeQueryComponent(
        _currentDeviceName ?? 'Android Device',
      );
      final transferId = 'tx_${DateTime.now().millisecondsSinceEpoch}';

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
        if (_isCancelled) break;
        try {
          final uri = Uri.parse(
            '$baseUrl${ServerConstants.filesUploadEndpoint}?name=$encodedName&deviceName=$deviceName&size=$totalBytes',
          );

          final request = http.StreamedRequest('POST', uri);
          final headers = _authHeaders(contentType: 'application/octet-stream');
          headers.forEach((key, val) => request.headers[key] = val);
          request.contentLength = totalBytes;

          final stopwatch = Stopwatch()..start();
          var bytesSent = 0;
          var lastProgressTime = DateTime.now();

          final responseFuture = _client.send(request);

          try {
            await for (final chunk in file.openRead()) {
              if (_isCancelled) {
                break;
              }
              request.sink.add(chunk);
              bytesSent += chunk.length;

              final now = DateTime.now();
              if (now.difference(lastProgressTime).inMilliseconds >= 50 ||
                  bytesSent >= totalBytes) {
                lastProgressTime = now;
                final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
                final speed = elapsedSec > 0 ? bytesSent / elapsedSec : 0.0;
                _emitProgress(
                  TransferProgress(
                    fileId: transferId,
                    fileName: name,
                    bytesTransferred: bytesSent,
                    totalBytes: totalBytes,
                    speedBytesPerSec: speed,
                    isUpload: true,
                    status: TransferStatus.inProgress,
                    timestamp: now,
                  ),
                );
              }
            }
            await request.sink.close();
          } catch (e) {
            debugPrint('FileShareService: Upload streaming failed: $e');
            await request.sink.close();
            rethrow;
          }

          if (_isCancelled) {
            _emitProgress(
              TransferProgress(
                fileId: transferId,
                fileName: name,
                bytesTransferred: bytesSent,
                totalBytes: totalBytes,
                speedBytesPerSec: 0,
                isUpload: true,
                status: TransferStatus.cancelled,
                timestamp: DateTime.now(),
              ),
            );
            return false;
          }

          final streamedResponse = await responseFuture.timeout(
            const Duration(seconds: 15),
          );

          if (streamedResponse.statusCode == 200) {
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
      debugPrint('FileShareService uploadFile error: $e');
      return false;
    }
  }

  /// Downloads a shared file from PC to phone with real-time streaming chunks, speed, and percentage tracking.
  Future<File?> downloadFile(SharedFile item) async {
    _isCancelled = false;
    final urls = _candidateUrls();
    if (urls.isEmpty) return null;

    final transferId = 'rx_${DateTime.now().millisecondsSinceEpoch}';
    final totalBytes = item.size;

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
      if (_isCancelled) break;
      try {
        final uri = Uri.parse(
          '$baseUrl${ServerConstants.filesDownloadEndpoint}?id=${Uri.encodeQueryComponent(item.id)}',
        );

        final request = http.Request('GET', uri);
        final streamedResponse = await _client.send(request);

        if (streamedResponse.statusCode != 200) continue;

        final actualTotal = streamedResponse.contentLength ?? totalBytes;
        final dir = await _getPCLinkDownloadDir();
        final dest = File('${dir.path}${Platform.pathSeparator}${item.name}');
        final sink = dest.openWrite();

        final stopwatch = Stopwatch()..start();
        var bytesReceived = 0;
        var lastProgressTime = DateTime.now();

        try {
          await for (final chunk in streamedResponse.stream) {
            if (_isCancelled) break;
            sink.add(chunk);
            bytesReceived += chunk.length;

            final now = DateTime.now();
            if (now.difference(lastProgressTime).inMilliseconds >= 50 ||
                bytesReceived >= actualTotal) {
              lastProgressTime = now;
              final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
              final speed = elapsedSec > 0 ? bytesReceived / elapsedSec : 0.0;
              _emitProgress(
                TransferProgress(
                  fileId: transferId,
                  fileName: item.name,
                  bytesTransferred: bytesReceived,
                  totalBytes: actualTotal,
                  speedBytesPerSec: speed,
                  isUpload: false,
                  status: TransferStatus.inProgress,
                  timestamp: now,
                ),
              );
            }
          }
          await sink.flush();
          await sink.close();
        } catch (e) {
          await sink.close();
          if (await dest.exists()) await dest.delete();
          rethrow;
        }

        if (_isCancelled || (actualTotal > 0 && bytesReceived < actualTotal)) {
          if (await dest.exists()) await dest.delete();
          if (_isCancelled) {
            _emitProgress(
              TransferProgress(
                fileId: transferId,
                fileName: item.name,
                bytesTransferred: bytesReceived,
                totalBytes: actualTotal,
                speedBytesPerSec: 0,
                isUpload: false,
                status: TransferStatus.cancelled,
                timestamp: DateTime.now(),
              ),
            );
          } else {
            _emitProgress(
              TransferProgress(
                fileId: transferId,
                fileName: item.name,
                bytesTransferred: bytesReceived,
                totalBytes: actualTotal,
                speedBytesPerSec: 0,
                isUpload: false,
                status: TransferStatus.failed,
                errorMessage: 'Download incomplete',
                timestamp: DateTime.now(),
              ),
            );
          }
          return null;
        }

        // Notify Android MediaStore so the file immediately shows up in Downloads / Files app
        await _notifyMediaScanner(dest.path);

        _emitProgress(
          TransferProgress(
            fileId: transferId,
            fileName: item.name,
            bytesTransferred: actualTotal,
            totalBytes: actualTotal,
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

        return dest;
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
