import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';

/// Service managing device session tokens and enforcing single-session-per-platform policy.
///
/// Rules:
///  - Only ONE phone (Android) and ONE PC (Windows) can be logged in concurrently.
///  - If a new login is attempted on the same platform (e.g. a second phone logs in, or a second PC logs in),
///    a new session ID is generated and stored in RTDB, superseding the previous session.
///  - The older device on that platform detects that its session is no longer active and logs out.
class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  static const String _sessionFileName = 'pclink_session.json';
  final Random _random = Random.secure();

  String? _cachedSessionId;
  String? _cachedDeviceId;

  /// Returns the current active session ID stored in memory or loaded from disk.
  String? get currentSessionId => _cachedSessionId;

  /// Returns the cached device ID.
  String? get currentDeviceId => _cachedDeviceId;

  /// Generates a cryptographically unique session ID.
  String generateSessionId(String deviceId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randSuffix = _random.nextInt(9000000) + 1000000;
    return '${timestamp}_${randSuffix}_${deviceId.hashCode.abs().toRadixString(16)}';
  }

  /// Locates the persistent session file across Android, Windows, and testing environments.
  Future<File?> _getSessionFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_sessionFileName');
    } catch (_) {
      try {
        final tempDir = await getTemporaryDirectory();
        return File('${tempDir.path}/$_sessionFileName');
      } catch (e) {
        debugPrint('SessionService: Could not resolve session storage directory: $e');
        return null;
      }
    }
  }

  /// Initializes the service by reading any persisted session from disk.
  Future<void> init() async {
    try {
      final file = await _getSessionFile();
      if (file != null && await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final dynamic data = jsonDecode(raw);
          if (data is Map) {
            _cachedSessionId = data['sessionId'] as String?;
            _cachedDeviceId = data['deviceId'] as String?;
            debugPrint('SessionService: Loaded persisted session: $_cachedSessionId');
          }
        }
      }
    } catch (e) {
      debugPrint('SessionService init error: $e');
    }
  }

  /// Saves the active session to local disk.
  Future<void> _saveLocalSession({
    required String sessionId,
    required String deviceId,
    required String platformKey,
  }) async {
    _cachedSessionId = sessionId;
    _cachedDeviceId = deviceId;
    try {
      final file = await _getSessionFile();
      if (file != null) {
        await file.writeAsString(
          jsonEncode({
            'sessionId': sessionId,
            'deviceId': deviceId,
            'platformKey': platformKey,
            'savedAt': DateTime.now().toIso8601String(),
          }),
        );
      }
    } catch (e) {
      debugPrint('SessionService _saveLocalSession error: $e');
    }
  }

  /// Clears the locally stored session on user logout or session eviction.
  Future<void> clearLocalSession() async {
    _cachedSessionId = null;
    _cachedDeviceId = null;
    try {
      final file = await _getSessionFile();
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('SessionService clearLocalSession error: $e');
    }
  }

  /// Registers a brand new session for this device upon user login/registration.
  ///
  /// This stores the new `sessionId` locally AND writes it to RTDB under
  /// `/users/{uid}/devices/{platformKey}/sessionId`.
  /// Any older device listening on this platform slot will detect the mismatch and log out.
  Future<String> registerNewSession({
    required User user,
    required String platformKey,
    required String deviceId,
    DatabaseService? databaseService,
  }) async {
    final dbService = databaseService ?? DatabaseService();
    final newSessionId = generateSessionId(deviceId);

    await _saveLocalSession(
      sessionId: newSessionId,
      deviceId: deviceId,
      platformKey: platformKey,
    );

    await dbService.registerDeviceSession(
      user: user,
      platformKey: platformKey,
      sessionId: newSessionId,
      deviceId: deviceId,
    );

    debugPrint(
      'SessionService: Registered new session $newSessionId for $platformKey ($deviceId)',
    );
    return newSessionId;
  }

  /// Verifies whether the local device session is currently valid against RTDB.
  ///
  /// Returns:
  ///  - `true`: Session is valid (matches remote, or network error prevents check).
  ///  - `false`: Session was superseded by another login on the same platform slot!
  Future<bool> isSessionValid({
    required User user,
    required String platformKey,
    required String deviceId,
    DatabaseService? databaseService,
  }) async {
    if (_cachedSessionId == null) {
      await init();
    }

    final dbService = databaseService ?? DatabaseService();
    final remoteSessionId = await dbService.getDeviceSessionId(
      user: user,
      platformKey: platformKey,
    );

    // If RTDB has no session registered yet (e.g. initial setup or database migration)
    if (remoteSessionId == null || remoteSessionId.isEmpty) {
      if (_cachedSessionId != null && _cachedSessionId!.isNotEmpty) {
        // Adopt our local session in RTDB
        await dbService.registerDeviceSession(
          user: user,
          platformKey: platformKey,
          sessionId: _cachedSessionId!,
          deviceId: deviceId,
        );
      } else {
        // Generate and register new session
        await registerNewSession(
          user: user,
          platformKey: platformKey,
          deviceId: deviceId,
          databaseService: dbService,
        );
      }
      return true;
    }

    // If local has no session recorded, check if remote belongs to this device
    if (_cachedSessionId == null || _cachedSessionId!.isEmpty) {
      final remoteDeviceId = await dbService.getDeviceSlotDeviceId(
        user: user,
        platformKey: platformKey,
      );
      if (remoteDeviceId != null && remoteDeviceId == deviceId) {
        // Same hardware device re-syncing without local file
        await _saveLocalSession(
          sessionId: remoteSessionId,
          deviceId: deviceId,
          platformKey: platformKey,
        );
        return true;
      }
      // Belongs to a different device on this platform
      return false;
    }

    // Both local and remote session IDs exist
    final isValid = _cachedSessionId == remoteSessionId;
    if (!isValid) {
      debugPrint(
        'SessionService: Session mismatch! Local: $_cachedSessionId vs Remote: $remoteSessionId. Superseded by another login.',
      );
    }
    return isValid;
  }
}
