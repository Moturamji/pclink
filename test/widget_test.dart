import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/services/auth_service.dart';

void main() {
  group('AuthService Tests', () {
    test('getErrorMessage returns proper messages for Firebase errors', () {
      expect(
        AuthService.getErrorMessage(Exception('Generic error')),
        contains('Generic error'),
      );
    });
  });
}
