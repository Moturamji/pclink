import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pclink/data/models/device_details.dart';
import 'package:pclink/data/models/linked_device.dart';
import 'package:pclink/data/services/database_service.dart';
import 'package:pclink/data/services/session_service.dart';

class FakeUser extends Fake implements User {
  @override
  final String uid;
  @override
  final String? email;

  FakeUser({this.uid = 'test_uid_session', this.email = 'user@example.com'});

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'mock_token';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Single Phone & Single PC Session Policy Tests', () {
    late FakeUser user;
    late Map<String, dynamic> mockDatabase;

    setUp(() {
      user = FakeUser();
      mockDatabase = <String, dynamic>{};
    });

    http.Client createMockDbClient() {
      return MockClient((request) async {
        final path = request.url.path;

        // PATCH /users/{uid}/devices/{platform}.json
        if (request.method == 'PATCH') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (path.contains('/devices/android.json')) {
            mockDatabase['android'] = {
              ...(mockDatabase['android'] as Map<String, dynamic>? ?? {}),
              ...body,
            };
            return http.Response(jsonEncode(mockDatabase['android']), 200);
          } else if (path.contains('/devices/windows.json')) {
            mockDatabase['windows'] = {
              ...(mockDatabase['windows'] as Map<String, dynamic>? ?? {}),
              ...body,
            };
            return http.Response(jsonEncode(mockDatabase['windows']), 200);
          }
        }

        // GET /users/{uid}/devices/{platform}/sessionId.json
        if (request.method == 'GET' && path.endsWith('/sessionId.json')) {
          if (path.contains('/android/')) {
            final sid = mockDatabase['android']?['sessionId'];
            return http.Response(jsonEncode(sid), 200);
          } else if (path.contains('/windows/')) {
            final sid = mockDatabase['windows']?['sessionId'];
            return http.Response(jsonEncode(sid), 200);
          }
        }

        // GET /users/{uid}/devices/{platform}/deviceId.json
        if (request.method == 'GET' && path.endsWith('/deviceId.json')) {
          if (path.contains('/android/')) {
            final did = mockDatabase['android']?['deviceId'];
            return http.Response(jsonEncode(did), 200);
          } else if (path.contains('/windows/')) {
            final did = mockDatabase['windows']?['deviceId'];
            return http.Response(jsonEncode(did), 200);
          }
        }

        // GET /users/{uid}/devices.json
        if (request.method == 'GET' && path.endsWith('/devices.json')) {
          return http.Response(jsonEncode(mockDatabase), 200);
        }

        // GET /users/{uid}.json
        if (request.method == 'GET' && path.contains('/users/')) {
          return http.Response('{"userId": "test_uid"}', 200);
        }

        return http.Response('null', 200);
      });
    }

    test('LinkedDevice serializes and deserializes sessionId correctly', () {
      final dev = LinkedDevice(
        platformKey: 'android',
        deviceId: 'phone_001',
        deviceName: 'Pixel 9 Pro',
        osVersion: 'Android 15',
        ipAddress: '192.168.1.50',
        isOnline: true,
        sessionId: 'sess_phone_001',
      );

      final map = dev.toMap();
      expect(map['sessionId'], equals('sess_phone_001'));

      final fromMap = LinkedDevice.fromMap('android', map);
      expect(fromMap.sessionId, equals('sess_phone_001'));
      expect(fromMap, equals(dev));
    });

    test('1 Phone and 1 PC can both be logged in simultaneously without conflict', () async {
      final mockClient = createMockDbClient();
      final dbService = DatabaseService(client: mockClient);

      // Register Phone 1
      await dbService.registerDeviceSession(
        user: user,
        platformKey: 'android',
        sessionId: 'phone_sess_1',
        deviceId: 'pixel_phone_id',
      );

      // Register PC 1
      await dbService.registerDeviceSession(
        user: user,
        platformKey: 'windows',
        sessionId: 'pc_sess_1',
        deviceId: 'dell_pc_id',
      );

      // Verify both sessions coexist in their respective platform slots
      final phoneSid = await dbService.getDeviceSessionId(user: user, platformKey: 'android');
      final pcSid = await dbService.getDeviceSessionId(user: user, platformKey: 'windows');

      expect(phoneSid, equals('phone_sess_1'));
      expect(pcSid, equals('pc_sess_1'));
    });

    test('When Phone 2 logs in, Phone 1 session is invalidated while PC 1 is unaffected', () async {
      final mockClient = createMockDbClient();
      final dbService = DatabaseService(client: mockClient);

      // Initial state: Phone 1 and PC 1 are logged in
      await dbService.registerDeviceSession(
        user: user,
        platformKey: 'android',
        sessionId: 'phone_sess_1',
        deviceId: 'phone_1_hardware_id',
      );
      await dbService.registerDeviceSession(
        user: user,
        platformKey: 'windows',
        sessionId: 'pc_sess_1',
        deviceId: 'pc_1_hardware_id',
      );

      // Now Phone 2 logs in
      await dbService.registerDeviceSession(
        user: user,
        platformKey: 'android',
        sessionId: 'phone_sess_2',
        deviceId: 'phone_2_hardware_id',
      );

      // Phone slot should now have Phone 2's session
      final currentPhoneSid = await dbService.getDeviceSessionId(user: user, platformKey: 'android');
      expect(currentPhoneSid, equals('phone_sess_2'));

      // Phone 1 compares its local session ('phone_sess_1') with current remote ('phone_sess_2')
      const phone1LocalSession = 'phone_sess_1';
      final isPhone1StillValid = phone1LocalSession == currentPhoneSid;
      expect(isPhone1StillValid, isFalse, reason: 'Phone 1 must be marked invalid/superseded!');

      // PC 1 is completely unaffected
      final currentPcSid = await dbService.getDeviceSessionId(user: user, platformKey: 'windows');
      const pc1LocalSession = 'pc_sess_1';
      final isPc1StillValid = pc1LocalSession == currentPcSid;
      expect(isPc1StillValid, isTrue, reason: 'PC 1 session must remain active!');
    });

    test('When PC 2 logs in, PC 1 session is invalidated while Phone 2 is unaffected', () async {
      final mockClient = createMockDbClient();
      final dbService = DatabaseService(client: mockClient);

      // State: Phone 2 and PC 1 are logged in
      await dbService.registerDeviceSession(
        user: user,
        platformKey: 'android',
        sessionId: 'phone_sess_2',
        deviceId: 'phone_2_hardware_id',
      );
      await dbService.registerDeviceSession(
        user: user,
        platformKey: 'windows',
        sessionId: 'pc_sess_1',
        deviceId: 'pc_1_hardware_id',
      );

      // PC 2 logs in
      await dbService.registerDeviceSession(
        user: user,
        platformKey: 'windows',
        sessionId: 'pc_sess_2',
        deviceId: 'pc_2_hardware_id',
      );

      // Windows slot should now have PC 2's session
      final currentPcSid = await dbService.getDeviceSessionId(user: user, platformKey: 'windows');
      expect(currentPcSid, equals('pc_sess_2'));

      // PC 1 detects superseded session
      const pc1LocalSession = 'pc_sess_1';
      expect(pc1LocalSession == currentPcSid, isFalse, reason: 'PC 1 must be logged out!');

      // Phone 2 detects untouched session
      final currentPhoneSid = await dbService.getDeviceSessionId(user: user, platformKey: 'android');
      const phone2LocalSession = 'phone_sess_2';
      expect(phone2LocalSession == currentPhoneSid, isTrue, reason: 'Phone 2 must remain logged in!');
    });

    test('listenDeviceSession emits updated remote session IDs for live eviction', () async {
      final mockClient = createMockDbClient();
      final dbService = DatabaseService(client: mockClient);

      // Seed initial session
      await dbService.registerDeviceSession(
        user: user,
        platformKey: 'android',
        sessionId: 'live_session_1',
        deviceId: 'device_alpha',
      );

      final stream = dbService.listenDeviceSession(
        user: user,
        platformKey: 'android',
        interval: const Duration(milliseconds: 50),
      );

      final receivedSessions = <String?>[];
      final sub = stream.listen((sid) {
        receivedSessions.add(sid);
      });

      await Future.delayed(const Duration(milliseconds: 80));

      // Another phone logs in and updates session in RTDB
      await dbService.registerDeviceSession(
        user: user,
        platformKey: 'android',
        sessionId: 'live_session_2',
        deviceId: 'device_beta',
      );

      await Future.delayed(const Duration(milliseconds: 120));
      await sub.cancel();

      expect(receivedSessions, contains('live_session_1'));
      expect(receivedSessions, contains('live_session_2'));
    });

    test('syncUserAndDevice preserves and attaches sessionId in device payload', () async {
      final mockClient = createMockDbClient();
      final dbService = DatabaseService(client: mockClient);

      const details = DeviceDetails(
        platform: 'Android',
        deviceId: 'android_test_dev',
        deviceName: 'Pixel 8',
        osVersion: 'Android 14',
        primaryIp: '192.168.1.10',
        interfaces: [],
        additionalDetails: {},
      );

      await dbService.syncUserAndDevice(
        user: user,
        details: details,
        sessionId: 'test_synced_session_xyz',
      );

      final androidNode = mockDatabase['android'] as Map<String, dynamic>?;
      expect(androidNode, isNotNull);
      expect(androidNode!['sessionId'], equals('test_synced_session_xyz'));
      expect(androidNode['deviceId'], equals('android_test_dev'));
    });

    test('SessionService generates unique non-empty session IDs', () {
      final sessionService = SessionService();
      final sid1 = sessionService.generateSessionId('device_1');
      final sid2 = sessionService.generateSessionId('device_1');
      expect(sid1, isNotEmpty);
      expect(sid2, isNotEmpty);
      expect(sid1, isNot(equals(sid2)));
    });
  });
}
