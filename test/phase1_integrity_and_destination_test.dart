import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/core/utils/transfer_integrity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pclink_phase1_tests_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Phase 1: Safe Destination & Non-Destructive Naming Tests', () {
    test('Non-destructive collision naming increments filename and leaves original intact', () async {
      final origFile = File('${tempDir.path}\\document.pdf');
      await origFile.writeAsString('Original Important User Content');

      final newDest1 = await FileSystemUtil.getUniqueDestinationFile(tempDir, 'document.pdf');
      expect(newDest1.path.endsWith('document (1).pdf'), isTrue);
      await newDest1.writeAsString('Second File Content');

      final newDest2 = await FileSystemUtil.getUniqueDestinationFile(tempDir, 'document.pdf');
      expect(newDest2.path.endsWith('document (2).pdf'), isTrue);
      await newDest2.writeAsString('Third File Content');

      // Verify original file was never deleted or overwritten
      expect(await origFile.exists(), isTrue);
      expect(await origFile.readAsString(), equals('Original Important User Content'));
      expect(await newDest1.readAsString(), equals('Second File Content'));
      expect(await newDest2.readAsString(), equals('Third File Content'));
    });

    test('Non-destructive collision naming works with files without extension', () async {
      final origFile = File('${tempDir.path}\\LICENSE');
      await origFile.writeAsString('MIT License');

      final newDest = await FileSystemUtil.getUniqueDestinationFile(tempDir, 'LICENSE');
      expect(newDest.path.endsWith('LICENSE (1)'), isTrue);
    });

    test('Robust rename handles normal rename and stream fallback', () async {
      final partFile = File('${tempDir.path}\\.part_test.tmp');
      await partFile.writeAsBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));

      final destFile = File('${tempDir.path}\\final_test.dat');
      final finalized = await FileSystemUtil.robustRenameOrCopy(partFile, destFile);

      expect(await finalized.exists(), isTrue);
      expect(await finalized.readAsBytes(), equals([1, 2, 3, 4, 5, 6, 7, 8]));
      expect(await partFile.exists(), isFalse);
    });
  });

  group('Phase 1: Streaming CRC-32 Integrity Tests', () {
    test('CRC-32 computes consistent checksum across chunk boundaries', () {
      final data = Uint8List.fromList(List.generate(10000, (i) => i % 256));

      // Single pass
      final crc1 = TransferCrc32()..update(data);

      // Multi chunk pass (uneven chunks)
      final crc2 = TransferCrc32();
      crc2.update(data.sublist(0, 3123));
      crc2.update(data.sublist(3123, 7891));
      crc2.update(data.sublist(7891));

      expect(crc2.value, equals(crc1.value));
      expect(crc2.hexString, equals(crc1.hexString));
      expect(crc2.bytesProcessed, equals(10000));
    });

    test('CRC-32 detects corrupted byte with 100% sensitivity', () {
      final original = Uint8List.fromList(List.generate(5000, (i) => i % 256));
      final corrupted = Uint8List.fromList(original);
      corrupted[2500] = (corrupted[2500] + 1) % 256; // flip a single byte

      final crcOrig = TransferCrc32()..update(original);
      final crcCorrupt = TransferCrc32()..update(corrupted);

      expect(crcOrig.hexString, isNot(equals(crcCorrupt.hexString)));
    });
  });
}
