import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/firebase_options.dart';

void main() {
  group('DefaultFirebaseOptions Platform Tests', () {
    test('macOS options returns valid FirebaseOptions', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final options = DefaultFirebaseOptions.currentPlatform;
      expect(options.projectId, equals('pclink-34bfa'));
      expect(options.apiKey.isNotEmpty, isTrue);
      expect(options.appId.isNotEmpty, isTrue);
      expect(options.databaseURL, isNotNull);
      debugDefaultTargetPlatformOverride = null;
    });

    test('iOS options returns valid FirebaseOptions', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final options = DefaultFirebaseOptions.currentPlatform;
      expect(options.projectId, equals('pclink-34bfa'));
      expect(options.apiKey.isNotEmpty, isTrue);
      expect(options.appId.isNotEmpty, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    test('Windows options returns valid FirebaseOptions', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final options = DefaultFirebaseOptions.currentPlatform;
      expect(options.projectId, equals('pclink-34bfa'));
      expect(options.apiKey.isNotEmpty, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    test('Android options returns valid FirebaseOptions', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final options = DefaultFirebaseOptions.currentPlatform;
      expect(options.projectId, equals('pclink-34bfa'));
      expect(options.apiKey.isNotEmpty, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

