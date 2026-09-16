// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Benchmark chunk sizes: 64KB, 128KB, 256KB, 512KB, 1MB', () async {
    final tempDir = await Directory.systemTemp.createTemp('pclink_chunk_bench_');
    const sizeMb = 50;
    final totalBytes = sizeMb * 1024 * 1024;
    final testFile = File('${tempDir.path}\\source.dat');

    // Create 50MB test file with pseudo-random content
    final rand = Random(42);
    final writer = testFile.openSync(mode: FileMode.write);
    final genChunk = Uint8List(1024 * 1024);
    for (int m = 0; m < sizeMb; m++) {
      for (int i = 0; i < genChunk.length; i += 4) {
        final r = rand.nextInt(0xFFFFFFFF);
        genChunk[i] = r & 0xFF;
        genChunk[i + 1] = (r >> 8) & 0xFF;
        genChunk[i + 2] = (r >> 16) & 0xFF;
        genChunk[i + 3] = (r >> 24) & 0xFF;
      }
      writer.writeFromSync(genChunk);
    }
    writer.closeSync();

    final chunkSizes = [
      64 * 1024,
      128 * 1024,
      256 * 1024,
      512 * 1024,
      1024 * 1024,
    ];

    print('\n================ CHUNK SIZE BENCHMARK (50 MB Disk Read -> Stream -> Disk Write) ================');

    for (final chunkSize in chunkSizes) {
      final destFile = File('${tempDir.path}\\dest_$chunkSize.dat');
      int chunksProcessed = 0;

      // We read file using RandomAccessFile with exact chunk size to measure raw disk & allocation throughput
      final raf = await testFile.open(mode: FileMode.read);
      final destRaf = await destFile.open(mode: FileMode.write);

      final swIo = Stopwatch()..start();
      var remaining = totalBytes;
      while (remaining > 0) {
        final toRead = min(chunkSize, remaining);
        final buffer = Uint8List(toRead);
        final bytesRead = await raf.readInto(buffer, 0, toRead);
        if (bytesRead <= 0) break;
        await destRaf.writeFrom(buffer, 0, bytesRead);
        chunksProcessed++;
        remaining -= bytesRead;
      }
      await destRaf.flush();
      await destRaf.close();
      await raf.close();
      swIo.stop();

      final elapsedMs = swIo.elapsedMilliseconds;
      final mbPerSec = (totalBytes / (1024 * 1024)) / (elapsedMs / 1000.0);
      final avgLatencyPerChunkUs = (elapsedMs * 1000) / chunksProcessed;

      print('Chunk Size: ${(chunkSize / 1024).toString().padLeft(4)} KB | '
          'Chunks: ${chunksProcessed.toString().padLeft(5)} | '
          'Time: ${elapsedMs.toString().padLeft(4)} ms | '
          'Throughput: ${mbPerSec.toStringAsFixed(1).padLeft(6)} MB/s | '
          'Latency/chunk: ${avgLatencyPerChunkUs.toStringAsFixed(1).padLeft(6)} µs');

      if (await destFile.exists()) {
        await destFile.delete();
      }
    }
    print('=================================================================================================\n');

    await tempDir.delete(recursive: true);
  });
}
