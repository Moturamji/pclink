import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/device_details.dart';
import '../models/linked_device.dart';

/// Service for managing user collections and device state in Firebase Realtime Database.
class DatabaseService {
  final FirebaseDatabase _db;

  DatabaseService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  /// Initializes the user record (if not present) and stores/updates the current platform device details.
  Future<void> syncUserAndDevice({
    required User user,
    required DeviceDetails details,
  }) async {
    final userRef = _db.ref('users/${user.uid}');
    final nowIso = DateTime.now().toIso8601String();

    // 1. Verify and initialize user profile
    final userSnapshot = await userRef.get();
    if (!userSnapshot.exists) {
      await userRef.set({
        'userId': user.uid,
        'email': user.email ?? '',
        'createdAt': nowIso,
        'lastActive': nowIso,
      });
    } else {
      await userRef.update({
        'lastActive': nowIso,
      });
    }

    // 2. Store or update platform-specific device node (android or windows)
    final platformKey = details.isWindows ? 'windows' : 'android';
    final deviceRef = userRef.child('devices/$platformKey');

    await deviceRef.set({
      'deviceId': details.deviceId,
      'deviceName': details.deviceName,
      'osVersion': details.osVersion,
      'ipAddress': details.primaryIp,
      'lastSeen': nowIso,
      'isOnline': true,
    });

    // 3. Set up disconnect hook for online presence
    try {
      await deviceRef.onDisconnect().update({
        'isOnline': false,
        'lastSeen': nowIso,
      });
    } catch (_) {
      // In web or restricted environments, gracefully skip onDisconnect
    }
  }

  /// Listens to real-time updates of all devices linked to [userId].
  Stream<List<LinkedDevice>> watchUserDevices(String userId) {
    return _db.ref('users/$userId/devices').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) {
        return <LinkedDevice>[];
      }

      final List<LinkedDevice> devices = [];
      data.forEach((key, value) {
        if (value is Map) {
          devices.add(LinkedDevice.fromMap(key.toString(), value));
        }
      });

      return devices;
    });
  }
}
