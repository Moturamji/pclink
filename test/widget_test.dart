import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/core/utils/validators.dart';
import 'package:pclink/data/models/device_details.dart';
import 'package:pclink/data/services/auth_service.dart';

void main() {
  group('Validators Unit Tests', () {
    test('validateEmail validates correctly', () {
      expect(Validators.validateEmail(''), 'Please enter your email');
      expect(Validators.validateEmail('invalid-email'), 'Please enter a valid email address');
      expect(Validators.validateEmail('user@domain.com'), isNull);
    });

    test('validatePassword validates min length', () {
      expect(Validators.validatePassword(''), 'Please enter your password');
      expect(Validators.validatePassword('12345'), 'Password must be at least 6 characters');
      expect(Validators.validatePassword('123456'), isNull);
    });

    test('validateConfirmPassword checks equality', () {
      expect(Validators.validateConfirmPassword('', '123456'), 'Please confirm your password');
      expect(Validators.validateConfirmPassword('123', '123456'), 'Passwords do not match');
      expect(Validators.validateConfirmPassword('123456', '123456'), isNull);
    });
  });

  group('DeviceDetails Model Tests', () {
    test('DeviceDetails computes helper getters correctly', () {
      const details = DeviceDetails(
        platform: 'Android',
        deviceId: 'test-device-id',
        deviceName: 'Pixel 7',
        osVersion: 'Android 14',
        primaryIp: '192.168.1.100',
        interfaces: [],
        additionalDetails: {},
      );

      expect(details.isAndroid, isTrue);
      expect(details.isWindows, isFalse);
      expect(details.isConnected, isTrue);
    });
  });

  group('AuthService Tests', () {
    test('getErrorMessage returns proper message for exceptions', () {
      expect(
        AuthService.getErrorMessage(Exception('Generic error')),
        contains('Generic error'),
      );
    });
  });
}
