import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/auth_io.dart';

void main() {
  test('Verify Firebase service account credentials against Google IAM', () async {
    final file = File('firebase_service_account.json');
    if (!file.existsSync()) {
      // Allow running in environments where local credentials are not deployed
      return;
    }

    final jsonStr = file.readAsStringSync();
    final credentials = ServiceAccountCredentials.fromJson(jsonStr);
    expect(credentials.projectId, equals('pclink-34bfa'));
    expect(credentials.email, equals('firebase-adminsdk-fbsvc@pclink-34bfa.iam.gserviceaccount.com'));

    final client = await clientViaServiceAccount(
      credentials,
      ['https://www.googleapis.com/auth/firebase.messaging'],
    );
    expect(client.credentials.accessToken.data.isNotEmpty, isTrue);
    expect(client.credentials.accessToken.type, equals('Bearer'));
    debugPrint('Token successfully obtained for projectId: ${credentials.projectId}');
    client.close();
  });
}
