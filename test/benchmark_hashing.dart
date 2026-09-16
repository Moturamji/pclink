// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure Dart IEEE 802.3 CRC-32 implementation
class Crc32 {
  static final Uint32List _table = _initTable();

  static Uint32List _initTable() {
    final table = Uint32List(256);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[i] = c;
    }
    return table;
  }

  int _crc = 0xFFFFFFFF;

  void add(List<int> chunk) {
    var c = _crc;
    for (int i = 0; i < chunk.length; i++) {
      c = _table[(c ^ chunk[i]) & 0xFF] ^ (c >>> 8);
    }
    _crc = c;
  }

  int get value => _crc ^ 0xFFFFFFFF;
  String get hexString => value.toRadixString(16).padLeft(8, '0');
}

void main() {
  test('Benchmark SHA-256 vs CRC-32 on large data streams', () {
    const sizeMb = 50; // 50MB benchmark
    final totalBytes = sizeMb * 1024 * 1024;
    final chunkSizes = [64 * 1024, 256 * 1024, 512 * 1024];

    print('\n================ HASHING BENCHMARK (50 MB Payload) ================');

    for (final chunkSize in chunkSizes) {
      final chunkCount = totalBytes ~/ chunkSize;
      final sampleChunk = Uint8List(chunkSize);
      final rand = Random(42);
      for (int i = 0; i < chunkSize; i++) {
        sampleChunk[i] = rand.nextInt(256);
      }

      // Benchmark CRC32
      final swCrc = Stopwatch()..start();
      final crc = Crc32();
      for (int i = 0; i < chunkCount; i++) {
        crc.add(sampleChunk);
      }
      swCrc.stop();
      final crcMs = swCrc.elapsedMilliseconds;
      final crcMbPerSec = (totalBytes / (1024 * 1024)) / (crcMs / 1000.0);

      // Benchmark SHA-256 streaming
      final swSha = Stopwatch()..start();
      final shaSink = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((d) {}),
      );
      for (int i = 0; i < chunkCount; i++) {
        shaSink.add(sampleChunk);
      }
      shaSink.close();
      swSha.stop();
      final shaMs = swSha.elapsedMilliseconds;
      final shaMbPerSec = (totalBytes / (1024 * 1024)) / (shaMs / 1000.0);

      print('Chunk: ${chunkSize ~/ 1024} KB | '
          'CRC-32: ${crcMs}ms (${crcMbPerSec.toStringAsFixed(1)} MB/s) | '
          'SHA-256: ${shaMs}ms (${shaMbPerSec.toStringAsFixed(1)} MB/s) | '
          'CRC is ${(crcMbPerSec / shaMbPerSec).toStringAsFixed(1)}x faster');
    }
    print('====================================================================\n');
  });
}
