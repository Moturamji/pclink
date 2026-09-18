import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/data/services/screen_share_service.dart';
import 'package:pclink/data/services/windows_autostart_service.dart';
import 'package:pclink/data/services/windows_permission_service.dart';

void main() {
  group('WindowsAutostartService Tests', () {
    test('Service responds predictably when queried', () async {
      final isEnabled = await WindowsAutostartService.isAutostartEnabled();
      expect(isEnabled, isA<bool>());
      expect(WindowsAutostartService.autostartNotifier.value, isA<bool>());
    });
  });

  group('WindowsPermissionService Tests', () {
    test('hasCompletedPermissionSetup returns a boolean', () async {
      final completed = await WindowsPermissionService.hasCompletedPermissionSetup();
      expect(completed, isA<bool>());
    });
  });

  group('ScreenShareService State Tests', () {
    test('consentNotifier reacts and ScreenShareStatus exposes true authorization', () {
      expect(ScreenShareService.consentNotifier, isNotNull);
      const status = ScreenShareStatus(
        isStreaming: false,
        isAuthorized: true,
        viewerName: null,
        lastFrameAt: null,
      );
      expect(status.isStreaming, isFalse);
      expect(status.isAuthorized, isTrue);
      expect(status.enabled, isFalse); // backward compatible alias
    });
  });
}
