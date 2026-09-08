import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service responsible for managing user authentication state via FirebaseAuth.
class AuthService {
  final FirebaseAuth _auth;

  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  /// Stream emitting auth state changes (logged in / logged out).
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Gets the currently authenticated user, if any.
  User? get currentUser => _auth.currentUser;

  /// Signs in a user with [email] and [password].
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Registers a new user account.
  /// Throws an exception if executed on Windows, enforcing mobile-only registration.
  Future<UserCredential> signUpWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (!kIsWeb && Platform.isWindows) {
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message:
            'Account registration is only permitted on the Android mobile app. Please register on your mobile device first.',
      );
    }

    return await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Signs out the current user session.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Sends a password reset link to the given [email].
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
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
          return error.message ?? 'Registration is not allowed on this device.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        default:
          return error.message ?? 'An authentication error occurred (${error.code}).';
      }
    }
    return error.toString();
  }
}
