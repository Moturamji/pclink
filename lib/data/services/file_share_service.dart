import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/server_constants.dart';
import '../../features/file_share/models/shared_file.dart';

/// Android client for the Windows temporary server's file-sharing API.
///
/// Mirrors the clipboard service: it discovers the PC via the same adaptive
/// candidate-URL list (public WAN/tunnel first, then LAN), sends the same
/// X-Device-Id + X-Start-Time auth headers, and transfers file bytes directly
/// through the temp server - never through Firebase.
class FileShareService {
  final http.Client _client = http.Client();

  List<String> Function()? _getTargetServerUrls;
  String? Function()? _getServerStartTime;
  String? _deviceId;
  String? _currentDeviceName;

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

  /// Tries every candidate URL until one responds. Returns null on total
  /// failure. File sharing is always user-initiated, so a simple loop over the
  /// candidate list (rather than the clipboard's background backoff) is enough.
  Future<http.Response?> _tryUrlFallback(
    Future<http.Response> Function(String baseUrl) send,
  ) async {
    final urls = _candidateUrls();
    if (urls.isEmpty) return null;

    for (final url in urls) {
      // The tunnel (https) can be slow on first contact (cold start / TLS).
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

  /// Uploads a local file (from the phone) to the PC's shared folder.
  /// Returns true when the PC accepted it.
  Future<bool> uploadFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final name = filePath.split(RegExp(r'[\\/]')).last;
      final encodedName = Uri.encodeQueryComponent(name);
      final deviceName = Uri.encodeQueryComponent(
        _currentDeviceName ?? 'Android Device',
      );
      final bytes = await file.readAsBytes();

      final response = await _tryUrlFallback(
        (url) => _client.post(
          Uri.parse(
            '$url${ServerConstants.filesUploadEndpoint}?name=$encodedName&deviceName=$deviceName',
          ),
          headers: _authHeaders(contentType: 'application/octet-stream'),
          body: bytes,
        ),
      );
      return response != null && response.statusCode == 200;
    } catch (e) {
      debugPrint('FileShareService uploadFile error: $e');
      return false;
    }
  }

  /// Downloads a shared file from the PC into a sensible app directory
  /// (Downloads when available, otherwise the app documents folder).
  Future<File?> downloadFile(SharedFile item) async {
    try {
      final response = await _tryUrlFallback(
        (url) => _client.get(
          Uri.parse(
            '$url${ServerConstants.filesDownloadEndpoint}?id=${Uri.encodeQueryComponent(item.id)}',
          ),
        ),
      );
      if (response == null ||
          response.statusCode != 200 ||
          response.bodyBytes.isEmpty) {
        return null;
      }

      Directory dir;
      try {
        dir =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = await getApplicationDocumentsDirectory();
      }

      final dest = File('${dir.path}${Platform.pathSeparator}${item.name}');
      await dest.writeAsBytes(response.bodyBytes, flush: true);
      return dest;
    } catch (e) {
      debugPrint('FileShareService downloadFile error: $e');
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
