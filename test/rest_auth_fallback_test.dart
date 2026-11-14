import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pclink/data/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AuthService REST fallback logs in with Google Identity Toolkit without Keychain', () async {
    final mockClient = MockClient((request) async {
      if (request.url.toString().contains('signInWithPassword')) {
        final body = jsonDecode(request.body);
        if (body['email'] == 'test@example.com' && body['password'] == 'password123') {
          return http.Response(
            jsonEncode({
              'localId': 'mock-uid-12345',
              'email': 'test@example.com',
              'idToken': 'mock-jwt-token-999',
              'refreshToken': 'mock-refresh-token-888',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else {
          return http.Response(
            jsonEncode({
              'error': {'message': 'INVALID_PASSWORD'}
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        }
      }
      return http.Response('Not Found', 404);
    });

    final authService = AuthService(httpClient: mockClient);
    final cred = await authService.signInViaRest(
      email: 'test@example.com',
      password: 'password123',
    );

    expect(cred.user, isNotNull);
    expect(cred.user!.uid, equals('mock-uid-12345'));
    expect(cred.user!.email, equals('test@example.com'));
    expect(await cred.user!.getIdToken(), equals('mock-jwt-token-999'));
    expect(authService.currentUser?.uid, equals('mock-uid-12345'));
  });
}

