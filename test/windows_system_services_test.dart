import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/data/services/windows_autostart_service.dart';
import 'package:pclink/data/services/windows_permission_service.dart';

void main() {
  group('WindowsAutostartService Tests', () {
    test('Service responds predictably when queried', () async {
      final isEnabled = await WindowsAutostartService.isAutostartEnabled();
      // On non-windows test environment or mock, expect boolean response
      expect(isEnabled, isA<bool>());
    });
  });

  group('WindowsPermissionService Tests', () {
    test('hasCompletedPermissionSetup returns a boolean', () async {
      final completed = await WindowsPermissionService.hasCompletedPermissionSetup();
      expect(completed, isA<bool>());
    });
  });
}
