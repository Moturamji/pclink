import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../firebase_options.dart';
import 'platform_helpers.dart';

/// Lightweight User implementation for platforms where Keychain or native SDK
/// is restricted (e.g. macOS without Apple Developer certificate).
class RestUser implements User {
  final String _uid;
  final String? _email;
  String _idToken;
  final String? _refreshToken;
  final String _apiKey;

  RestUser({
    required String uid,
    String? email,
    required String idToken,
    String? refreshToken,
    required String apiKey,
  })  : _uid = uid,
        _email = email,
        _idToken = idToken,
        _refreshToken = refreshToken,
        _apiKey = apiKey;

  @override
  String get uid => _uid;

  @override
  String? get email => _email;

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    if (forceRefresh && _refreshToken != null && _refreshToken!.isNotEmpty) {
      try {
        final res = await http.post(
          Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'refresh_token',
            'refresh_token': _refreshToken,
          },
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          _idToken = data['id_token'] ?? _idToken;
        }
      } catch (_) {}
    }
    return _idToken;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lightweight UserCredential implementation wrapping RestUser.
class RestUserCredential implements UserCredential {
  final User _user;
  RestUserCredential(this._user);

  @override
  User get user => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Service responsible for managing user authentication state via FirebaseAuth,
/// with automatic direct Firebase REST fallback on platforms where native Keychain is unavailable.
class AuthService {
  final FirebaseAuth? _customAuth;
  final http.Client _httpClient;

  static User? _restUser;
  static final StreamController<User?> _restStreamController =
      StreamController<User?>.broadcast();
  static bool _restSessionLoaded = false;

  AuthService({FirebaseAuth? auth, http.Client? httpClient})
      : _customAuth = auth,
        _httpClient = httpClient ?? http.Client() {
    _initRestSession();
  }

  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  static File? get _sessionFile {
    try {
      if (kIsWeb) return null;
      if (Platform.isMacOS && Platform.environment.containsKey('HOME')) {
        final dir = Directory(
            '${Platform.environment['HOME']}/Library/Application Support/pclink');
        if (!dir.existsSync()) {
          try {
            dir.createSync(recursive: true);
          } catch (_) {}
        }
        if (dir.existsSync()) {
          return File('${dir.path}/auth_session.json');
        }
      }
      return File('.auth_session.json');
    } catch (_) {
      return null;
    }
  }

  static void _initRestSession() {
    if (_restSessionLoaded) return;
    _restSessionLoaded = true;
    try {
      final file = _sessionFile;
      if (file != null && file.existsSync()) {
        final content = file.readAsStringSync().trim();
        if (content.isNotEmpty) {
          final data = jsonDecode(content);
          _restUser = RestUser(
            uid: data['uid'] ?? '',
            email: data['email'],
            idToken: data['idToken'] ?? '',
            refreshToken: data['refreshToken'],
            apiKey: data['apiKey'] ??
                DefaultFirebaseOptions.currentPlatform.apiKey,
          );
          _restStreamController.add(_restUser);
        }
      }
    } catch (_) {}
  }

  /// Stream emitting auth state changes (logged in / logged out).
  Stream<User?> get authStateChanges {
    final controller = StreamController<User?>();
    final current = currentUser;
    controller.add(current);

    StreamSubscription<User?>? nativeSub;
    try {
      nativeSub = _auth.authStateChanges().listen((user) {
        if (_restUser == null) {
          controller.add(user);
        }
      });
    } catch (_) {}

    final restSub = _restStreamController.stream.listen((user) {
      controller.add(user);
    });

    controller.onCancel = () {
      nativeSub?.cancel();
      restSub.cancel();
    };

    return controller.stream;
  }

  /// Gets the currently authenticated user, if any.
  User? get currentUser {
    if (_restUser != null) return _restUser;
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// Signs in a user with [email] and [password], falling back to direct
  /// Firebase REST authentication if native Keychain access fails.
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('keychain') ||
          (e is FirebaseAuthException &&
              (e.code.contains('keychain') || errStr.contains('keychain')))) {
        debugPrint(
            'AuthService: macOS Keychain restricted. Seamlessly logging in via Firebase REST API...');
        return await signInViaRest(email: email, password: password);
      }
      rethrow;
    }
  }

  /// Directly authenticates with Google Firebase Auth REST API (no Keychain required).
  Future<UserCredential> signInViaRest({
    required String email,
    required String password,
  }) async {
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    final url = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey');
    final response = await _httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final user = RestUser(
        uid: data['localId'] ?? '',
        email: data['email'] ?? email.trim(),
        idToken: data['idToken'] ?? '',
        refreshToken: data['refreshToken'],
        apiKey: apiKey,
      );
      _restUser = user;
      _restStreamController.add(user);

      // Persist local session
      try {
        final file = _sessionFile;
        if (file != null) {
          file.writeAsStringSync(jsonEncode({
            'uid': user.uid,
            'email': user.email,
            'idToken': data['idToken'],
            'refreshToken': data['refreshToken'],
            'apiKey': apiKey,
          }));
        }
      } catch (_) {}

      return RestUserCredential(user);
    } else {
      String code = 'unknown';
      String message = 'Authentication failed';
      try {
        final errJson = jsonDecode(response.body);
        final rawMsg = errJson['error']?['message'] as String? ?? '';
        if (rawMsg.contains('EMAIL_NOT_FOUND')) {
          code = 'user-not-found';
          message = 'No user found with this email address.';
        } else if (rawMsg.contains('INVALID_PASSWORD')) {
          code = 'wrong-password';
          message = 'Incorrect password. Please try again.';
        } else if (rawMsg.contains('INVALID_LOGIN_CREDENTIALS')) {
          code = 'invalid-credential';
          message = 'Invalid email or password combination.';
        } else if (rawMsg.contains('USER_DISABLED')) {
          code = 'user-disabled';
          message = 'This user account has been disabled.';
        } else if (rawMsg.contains('TOO_MANY_ATTEMPTS')) {
          code = 'too-many-requests';
          message = 'Too many attempts. Please try again later.';
        } else {
          message = rawMsg.isNotEmpty ? rawMsg : message;
        }
      } catch (_) {}

      throw FirebaseAuthException(code: code, message: message);
    }
  }

  /// Registers a new user account.
  /// Throws an exception if executed on desktop hosts, enforcing mobile-only registration.
  Future<UserCredential> signUpWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (isDesktopHost) {
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message:
            'Account registration is only permitted on the mobile app. Please register on your mobile device first.',
      );
    }

    return await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Signs out the current user session and clears local session cache.
  Future<void> signOut() async {
    _restUser = null;
    try {
      final file = _sessionFile;
      if (file != null && file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
    _restStreamController.add(null);
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  /// Sends a password reset link to the given [email].
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('keychain') ||
          (e is FirebaseAuthException &&
              (e.code.contains('keychain') || errStr.contains('keychain')))) {
        final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
        final res = await _httpClient.post(
          Uri.parse(
              'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'requestType': 'PASSWORD_RESET',
            'email': email.trim(),
          }),
        );
        if (res.statusCode != 200) {
          throw FirebaseAuthException(
              code: 'network-request-failed',
              message: 'Failed to send reset email.');
        }
        return;
      }
      rethrow;
    }
  }

  /// Translates FirebaseAuthExceptions into friendly user messages.
  static String getErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No user found with this email address.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        case 'invalid-credential':
          return 'Invalid email or password combination.';
        case 'email-already-in-use':
          return 'An account already exists for this email.';
        case 'invalid-email':
          return 'The email address is invalid.';
        case 'weak-password':
          return 'Password must be at least 6 characters long.';
        case 'user-disabled':
          return 'This user account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'operation-not-allowed':
          return error.message ??
              'Registration is not allowed on this device.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        default:
          return error.message ??
              'An authentication error occurred (${error.code}).';
      }
    }
    return error.toString();
  }
}
