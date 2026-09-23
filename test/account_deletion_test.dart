import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pclink/data/models/user_deletion_status.dart';
import 'package:pclink/data/services/database_service.dart';

class FakeUser extends Fake implements User {
  @override
  final String uid;
  @override
  final String? email;

  FakeUser({this.uid = 'test_uid_123', this.email = 'test@example.com'});

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'mock_id_token';

  @override
  Future<void> delete() async {}
}

void main() {
  group('Phase 10: 15-Day Account Deletion & Undeletion Lifecycle', () {
    test('UserDeletionStatus parses null and empty state as not requested', () {
      final statusNull = UserDeletionStatus.fromJson(null);
      expect(statusNull.isDeleteRequested, isFalse);
      expect(statusNull.daysRemaining, equals(0));
      expect(statusNull.isPermanentlyExpired, isFalse);

      final statusEmpty = UserDeletionStatus.fromJson({});
      expect(statusEmpty.isDeleteRequested, isFalse);
      expect(statusEmpty.daysRemaining, equals(0));
      expect(statusEmpty.isPermanentlyExpired, isFalse);
    });

    test('UserDeletionStatus accurately computes 15-day countdown', () {
      final now = DateTime.now();
      final requestedAt = now;
      final effectiveAt = now.add(const Duration(days: 15));

      final status = UserDeletionStatus.fromJson({
        'delete': true,
        'deleteRequestedAt': requestedAt.toIso8601String(),
        'deleteEffectiveAt': effectiveAt.toIso8601String(),
      });

      expect(status.isDeleteRequested, isTrue);
      expect(status.daysRemaining, greaterThanOrEqualTo(14));
      expect(status.daysRemaining, lessThanOrEqualTo(15));
      expect(status.hoursRemaining, greaterThan(300));
      expect(status.isPermanentlyExpired, isFalse);
    });

    test('UserDeletionStatus detects when 15 days have expired', () {
      final now = DateTime.now();
      final requestedAt = now.subtract(const Duration(days: 16));
      final effectiveAt = now.subtract(const Duration(days: 1));

      final status = UserDeletionStatus.fromJson({
        'delete': true,
        'deleteRequestedAt': requestedAt.toIso8601String(),
        'deleteEffectiveAt': effectiveAt.toIso8601String(),
      });

      expect(status.isDeleteRequested, isTrue);
      expect(status.daysRemaining, equals(0));
      expect(status.hoursRemaining, equals(0));
      expect(status.isPermanentlyExpired, isTrue);
    });

    test('DatabaseService requestAccountDeletion updates DB with delete: true and 15 days', () async {
      late Map<String, dynamic> capturedBody;
      late String capturedMethod;
      late Uri capturedUri;

      final mockClient = MockClient((request) async {
        capturedMethod = request.method;
        capturedUri = request.url;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final dbService = DatabaseService(client: mockClient);
      final fakeUser = FakeUser(uid: 'user_456');

      final success = await dbService.requestAccountDeletion(user: fakeUser);

      expect(success, isTrue);
      expect(capturedMethod, equals('PATCH'));
      expect(capturedUri.path, contains('/users/user_456.json'));
      expect(capturedBody['delete'], isTrue);
      expect(capturedBody['deleteRequestedAt'], isNotNull);
      expect(capturedBody['deleteEffectiveAt'], isNotNull);
      // Redundant flags are null (cleared from RTDB)
      expect(capturedBody['isDeleted'], isNull);
      expect(capturedBody['deleteRequested'], isNull);

      // Verify effective date is approximately 15 days in the future
      final reqTime = DateTime.parse(capturedBody['deleteRequestedAt'] as String);
      final effTime = DateTime.parse(capturedBody['deleteEffectiveAt'] as String);
      final diff = effTime.difference(reqTime);
      expect(diff.inDays, equals(15));
    });

    test('DatabaseService cancelAccountDeletion updates DB with delete: false and clears timestamps', () async {
      late Map<String, dynamic> capturedBody;
      late String capturedMethod;

      final mockClient = MockClient((request) async {
        capturedMethod = request.method;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final dbService = DatabaseService(client: mockClient);
      final fakeUser = FakeUser(uid: 'user_789');

      final success = await dbService.cancelAccountDeletion(user: fakeUser);

      expect(success, isTrue);
      expect(capturedMethod, equals('PATCH'));
      expect(capturedBody['delete'], isFalse);
      expect(capturedBody['deleteRequestedAt'], isNull);
      expect(capturedBody['deleteEffectiveAt'], isNull);
      expect(capturedBody['undeletedAt'], isNotNull);
      expect(capturedBody['isDeleted'], isNull);
      expect(capturedBody['deleteRequested'], isNull);
    });

    test('DatabaseService purgeExpiredAccount performs DELETE on user node', () async {
      late String capturedMethod;
      late Uri capturedUri;

      final mockClient = MockClient((request) async {
        capturedMethod = request.method;
        capturedUri = request.url;
        return http.Response('null', 200);
      });

      final dbService = DatabaseService(client: mockClient);
      final fakeUser = FakeUser(uid: 'user_purge');

      final success = await dbService.purgeExpiredAccount(user: fakeUser);

      expect(success, isTrue);
      expect(capturedMethod, equals('DELETE'));
      expect(capturedUri.path, contains('/users/user_purge.json'));
    });

    test('DatabaseService getAccountDeletionStatus fetches and parses UserDeletionStatus', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'userId': 'user_status_test',
            'email': 'status@example.com',
            'delete': true,
            'deleteRequestedAt': DateTime.now().toIso8601String(),
            'deleteEffectiveAt':
                DateTime.now().add(const Duration(days: 12)).toIso8601String(),
          }),
          200,
        );
      });

      final dbService = DatabaseService(client: mockClient);
      final fakeUser = FakeUser(uid: 'user_status_test');

      final status = await dbService.getAccountDeletionStatus(user: fakeUser);

      expect(status.isDeleteRequested, isTrue);
      expect(status.daysRemaining, equals(12));
      expect(status.isPermanentlyExpired, isFalse);
    });
  });
}
