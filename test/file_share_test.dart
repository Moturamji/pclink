import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/data/services/server_service.dart';
import 'package:pclink/features/file_share/models/shared_file.dart';

void main() {
  group('SharedFile Model Tests', () {
    test('SharedFile serializes and deserializes correctly', () {
      final file = SharedFile(
        id: 'file_1',
        name: 'notes.txt',
        size: 4096,
        sourcePlatform: 'windows',
        sourceDeviceName: 'DESKTOP-PC',
        timestamp: DateTime.utc(2026, 1, 1),
        filePath: r'C:\shared\file_1_notes.txt',
      );

      final map = file.toMap();
      expect(map['id'], 'file_1');
      expect(map['name'], 'notes.txt');
      expect(map['size'], 4096);
      expect(map['sourcePlatform'], 'windows');
      // Local server paths must never leak over the wire.
      expect(map.containsKey('filePath'), isFalse);

      final copy = SharedFile.fromMap(map);
      expect(copy.id, file.id);
      expect(copy.name, file.name);
      expect(copy.size, file.size);
      expect(copy.sourcePlatform, 'windows');
      expect(copy.filePath, isNull);
      expect(copy.isFromWindows, isTrue);
      expect(copy.sizeLabel, '4.0 KB');
    });

    test('SharedFile sizeLabel formats bytes, KB, MB and GB', () {
      SharedFile make(int size) => SharedFile(
        id: 'id$size',
        name: 'f',
        size: size,
        sourcePlatform: 'android',
        sourceDeviceName: 'Phone',
        timestamp: DateTime.now(),
      );
      expect(make(900).sizeLabel, '900 B');
      expect(make(2048).sizeLabel, '2.0 KB');
      expect(make(5 * 1024 * 1024).sizeLabel, '5.0 MB');
      expect(make(2 * 1024 * 1024 * 1024).sizeLabel, '2.0 GB');
    });
  });

  group('ServerService File Share Store Tests', () {
    test(
      'addLocalSharedFile copies file into store, removeSharedFile deletes it',
      () async {
        final tmp = Directory.systemTemp.createTempSync('pclink_share_test');
        final source = File('${tmp.path}${Platform.pathSeparator}hello.txt')
          ..writeAsStringSync('hello world');

        final service = ServerService();
        try {
          final item = await service.addLocalSharedFile(
            sourcePath: source.path,
            deviceName: 'Test PC',
          );

          expect(item, isNotNull);
          expect(service.sharedFiles, hasLength(1));
          expect(item!.filePath, isNotNull);
          expect(await File(item.filePath!).exists(), isTrue);
          expect(service.sharedFiles.first.name, 'hello.txt');
          expect(service.sharedFiles.first.isFromWindows, isTrue);

          await service.removeSharedFile(item.id);
          expect(service.sharedFiles, isEmpty);
          expect(await File(item.filePath!).exists(), isFalse);
        } finally {
          service.dispose();
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        }
      },
    );

    test('addLocalSharedFile returns null for missing source files', () async {
      final service = ServerService();
      try {
        final item = await service.addLocalSharedFile(
          sourcePath: 'Z:/this/path/does/not/exist.txt',
          deviceName: 'Test PC',
        );
        expect(item, isNull);
        expect(service.sharedFiles, isEmpty);
      } finally {
        service.dispose();
      }
    });
  });
}
