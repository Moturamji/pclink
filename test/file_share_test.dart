import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/data/services/server_service.dart';
import 'package:pclink/features/file_share/models/shared_file.dart';
import 'package:pclink/features/file_share/models/transfer_progress.dart';

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

  group('TransferProgress Model Tests', () {
    test('Calculates fraction, percentages, speed labels, and remaining labels correctly', () {
      final progress = TransferProgress(
        fileId: 'tx_123',
        fileName: 'video.mp4',
        bytesTransferred: 5 * 1024 * 1024,
        totalBytes: 10 * 1024 * 1024,
        speedBytesPerSec: 2.5 * 1024 * 1024,
        isUpload: true,
        status: TransferStatus.inProgress,
        timestamp: DateTime.now(),
      );

      expect(progress.fraction, 0.5);
      expect(progress.percentageLabel, '50.0%');
      expect(progress.speedLabel, '2.50 MB/s');
      expect(progress.transferredLabel, '5.00 MB / 10.00 MB');
      expect(progress.remainingBytes, 5 * 1024 * 1024);
      expect(progress.remainingLabel, '2 sec remaining');
    });

    test('Handles completed, failed, and cancelled transfer status labels', () {
      final completed = TransferProgress(
        fileId: 'tx_123',
        fileName: 'doc.pdf',
        bytesTransferred: 1024,
        totalBytes: 1024,
        isUpload: false,
        status: TransferStatus.completed,
        timestamp: DateTime.now(),
      );
      expect(completed.fraction, 1.0);
      expect(completed.percentageLabel, '100.0%');
      expect(completed.remainingLabel, 'Completed');

      final failed = completed.copyWith(status: TransferStatus.failed);
      expect(failed.remainingLabel, 'Failed');

      final cancelled = completed.copyWith(status: TransferStatus.cancelled);
      expect(cancelled.remainingLabel, 'Cancelled');
    });

    test('Ensures exact byte tracking and clamp safety under zero and edge conditions', () {
      final zero = TransferProgress(
        fileId: 'zero_1',
        fileName: 'empty.bin',
        bytesTransferred: 0,
        totalBytes: 0,
        isUpload: false,
        status: TransferStatus.inProgress,
        timestamp: DateTime.now(),
      );
      expect(zero.fraction, 0.0);
      expect(zero.percentageLabel, '0.0%');
      expect(zero.remainingBytes, 0);

      final exact = TransferProgress(
        fileId: 'exact_1',
        fileName: 'large.zip',
        bytesTransferred: 1048576,
        totalBytes: 1048576,
        isUpload: true,
        status: TransferStatus.completed,
        timestamp: DateTime.now(),
      );
      expect(exact.fraction, 1.0);
      expect(exact.percentageLabel, '100.0%');
      expect(exact.remainingBytes, 0);
    });
  });
}
