import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'transfer_integrity.dart';

/// Utilities for generating transfer fingerprints, managing `.meta` sidecar files,
/// and cleaning up stale temporary files.
class TransferFingerprint {
  /// Computes a lightweight, highly specific fingerprint for a local source file.
  /// Combines filename, exact byte length, last modified timestamp, and a CRC-32
  /// hash of the initial 64 KB header block.
  /// Execution time: <1ms even on multi-gigabyte files.
  static Future<String> computeSourceFingerprint(File file) async {
    if (!await file.exists()) return '';

    final stat = await file.stat();
    final size = stat.size;
    final modifiedMs = stat.modified.millisecondsSinceEpoch;
    final name = file.path.split(RegExp(r'[\\/]')).last;

    // Read first 64KB for header verification
    final headCrc = TransferCrc32();
    if (size > 0) {
      final raf = await file.open(mode: FileMode.read);
      try {
        final toRead = min(64 * 1024, size);
        final buffer = Uint8List(toRead);
        final bytesRead = await raf.readInto(buffer, 0, toRead);
        if (bytesRead > 0) {
          headCrc.update(buffer.sublist(0, bytesRead));
        }
      } finally {
        await raf.close();
      }
    }

    final rawString = '${name}_${size}_${modifiedMs}_${headCrc.hexString}';
    final fullCrc = TransferCrc32()..update(utf8.encode(rawString));
    return fullCrc.hexString;
  }

  /// Saves a resume metadata sidecar file alongside the `.part` file.
  static Future<void> writeMetaFile({
    required File metaFile,
    required String fingerprint,
    required String originalName,
    required int totalBytes,
    required int verifiedOffset,
  }) async {
    final data = {
      'fingerprint': fingerprint,
      'originalName': originalName,
      'totalBytes': totalBytes,
      'verifiedOffset': verifiedOffset,
      'lastUpdatedMs': DateTime.now().millisecondsSinceEpoch,
    };
    await metaFile.writeAsString(jsonEncode(data));
  }

  /// Reads and validates a resume metadata sidecar file.
  /// Returns the verified offset if [expectedFingerprint] matches and
  /// physical `.part` file exists and has sufficient length.
  /// Returns 0 if invalid or mismatched.
  static Future<int> readVerifiedOffset({
    required File partFile,
    required File metaFile,
    required String expectedFingerprint,
    required int expectedTotalBytes,
  }) async {
    if (!await partFile.exists() || !await metaFile.exists()) {
      return 0;
    }

    try {
      final content = await metaFile.readAsString();
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map) return 0;

      final savedFp = decoded['fingerprint'] as String?;
      final savedTotal = decoded['totalBytes'] as int?;
      final verifiedOffset = decoded['verifiedOffset'] as int?;

      if (savedFp == null ||
          savedFp.toLowerCase() != expectedFingerprint.toLowerCase() ||
          savedTotal != expectedTotalBytes ||
          verifiedOffset == null ||
          verifiedOffset <= 0) {
        // Fingerprint or total size mismatch!
        return 0;
      }

      final physicalLength = await partFile.length();
      if (physicalLength < verifiedOffset) {
        // Physical file was truncated below verified offset
        return physicalLength;
      }

      return verifiedOffset;
    } catch (_) {
      return 0;
    }
  }

  /// Cleans up stale `.part` and `.meta` files older than [maxAge] in [dir].
  static Future<int> purgeStalePartFiles(
    Directory dir, {
    Duration maxAge = const Duration(hours: 24),
  }) async {
    if (!await dir.exists()) return 0;

    int purgedCount = 0;
    final now = DateTime.now();

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final fileName = entity.path.split(RegExp(r'[\\/]')).last;
          if (fileName.startsWith('.part_') &&
              (fileName.endsWith('.tmp') || fileName.endsWith('.meta'))) {
            try {
              final stat = await entity.stat();
              if (now.difference(stat.modified) > maxAge) {
                await entity.delete();
                purgedCount++;
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    return purgedCount;
  }
}
