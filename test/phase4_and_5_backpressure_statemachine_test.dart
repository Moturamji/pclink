import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pclink/core/utils/stream_backpressure.dart';
import 'package:pclink/features/file_share/models/transfer_progress.dart';

void main() {
  group('Phase 4: Stream Backpressure & Inactivity Watchdog Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('p4_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('openReadOptimized streams in exact 256KB chunks', () async {
      final file = File('${tempDir.path}/chunk_test.dat');
      // Create a 600KB file (2 full 256KB chunks + 1 88KB chunk)
      final totalSize = 600 * 1024;
      final bytes = Uint8List(totalSize);
      for (var i = 0; i < totalSize; i++) {
        bytes[i] = i % 256;
      }
      await file.writeAsBytes(bytes);

      final chunkSizes = <int>[];
      await for (final chunk in StreamBackpressure.openReadOptimized(file)) {
        chunkSizes.add(chunk.length);
      }

      expect(chunkSizes.length, 3);
      expect(chunkSizes[0], 256 * 1024);
      expect(chunkSizes[1], 256 * 1024);
      expect(chunkSizes[2], 88 * 1024);
    });

    test('openReadOptimized honors start offset properly', () async {
      final file = File('${tempDir.path}/offset_test.dat');
      final totalSize = 512 * 1024;
      final bytes = Uint8List(totalSize);
      for (var i = 0; i < totalSize; i++) {
        bytes[i] = (i + 1) % 256;
      }
      await file.writeAsBytes(bytes);

      // Start at 300KB
      final startOffset = 300 * 1024;
      final readBytes = <int>[];
      await for (final chunk in StreamBackpressure.openReadOptimized(
        file,
        start: startOffset,
      )) {
        readBytes.addAll(chunk);
      }

      expect(readBytes.length, totalSize - startOffset);
      expect(readBytes[0], bytes[startOffset]);
      expect(readBytes.last, bytes.last);
    });

    test('InactivityWatchdog triggers on inactivity and resets on progress', () async {
      var timeoutTriggered = false;
      final watchdog = InactivityWatchdog(
        timeoutDuration: const Duration(milliseconds: 150),
        onTimeout: () {
          timeoutTriggered = true;
        },
      );

      // Notify progress before timeout
      await Future<void>.delayed(const Duration(milliseconds: 80));
      watchdog.notifyProgress();
      expect(timeoutTriggered, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      watchdog.notifyProgress();
      expect(timeoutTriggered, isFalse);

      // Now cease progress and wait for timeout
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(timeoutTriggered, isTrue);

      watchdog.cancel();
    });

    test('InactivityWatchdog does not fire if cancelled early', () async {
      var timeoutTriggered = false;
      final watchdog = InactivityWatchdog(
        timeoutDuration: const Duration(milliseconds: 100),
        onTimeout: () {
          timeoutTriggered = true;
        },
      );

      watchdog.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(timeoutTriggered, isFalse);
    });
  });

  group('Phase 5: Transfer State Machine & Real-Time Progress Semantics Tests', () {
    test('State machine validates legal forward transitions and rejects illegal backwards transitions', () {
      // Legal transitions
      expect(
        TransferStateMachine.isValidTransition(
          TransferStatus.idle,
          TransferStatus.preparing,
        ),
        isTrue,
      );
      expect(
        TransferStateMachine.isValidTransition(
          TransferStatus.preparing,
          TransferStatus.transferring,
        ),
        isTrue,
      );
      expect(
        TransferStateMachine.isValidTransition(
          TransferStatus.transferring,
          TransferStatus.verifying,
        ),
        isTrue,
      );
      expect(
        TransferStateMachine.isValidTransition(
          TransferStatus.verifying,
          TransferStatus.finalizing,
        ),
        isTrue,
      );
      expect(
        TransferStateMachine.isValidTransition(
          TransferStatus.finalizing,
          TransferStatus.completed,
        ),
        isTrue,
      );

      // Illegal transitions
      // Terminal state COMPLETED cannot transition to anything
      expect(
        TransferStateMachine.isValidTransition(
          TransferStatus.completed,
          TransferStatus.transferring,
        ),
        isFalse,
      );
      expect(
        TransferStateMachine.isValidTransition(
          TransferStatus.completed,
          TransferStatus.idle,
        ),
        isFalse,
      );

      // Cannot jump from idle directly to verifying or completed
      expect(
        TransferStateMachine.isValidTransition(
          TransferStatus.idle,
          TransferStatus.verifying,
        ),
        isFalse,
      );
      expect(
        TransferStateMachine.isValidTransition(
          TransferStatus.idle,
          TransferStatus.completed,
        ),
        isFalse,
      );
    });

    test('Progress fraction strictly never displays 100% until TransferStatus.completed', () {
      const totalBytes = 1000000;

      // Transferring with all bytes sent still clamps to 0.99
      final inProgressFull = TransferProgress(
        fileId: 'tx_test',
        fileName: 'sample.dat',
        bytesTransferred: totalBytes,
        totalBytes: totalBytes,
        isUpload: true,
        status: TransferStatus.transferring,
        timestamp: DateTime.now(),
      );
      expect(inProgressFull.fraction, lessThanOrEqualTo(0.99));
      expect(inProgressFull.percentageLabel, '99.0%');

      // Verifying state
      final verifyingProgress = TransferProgress(
        fileId: 'tx_test',
        fileName: 'sample.dat',
        bytesTransferred: totalBytes,
        totalBytes: totalBytes,
        isUpload: true,
        status: TransferStatus.verifying,
        timestamp: DateTime.now(),
      );
      expect(verifyingProgress.fraction, lessThanOrEqualTo(0.99));
      expect(verifyingProgress.percentageLabel, 'Verifying...');

      // Finalizing state
      final finalizingProgress = TransferProgress(
        fileId: 'tx_test',
        fileName: 'sample.dat',
        bytesTransferred: totalBytes,
        totalBytes: totalBytes,
        isUpload: true,
        status: TransferStatus.finalizing,
        timestamp: DateTime.now(),
      );
      expect(finalizingProgress.fraction, lessThanOrEqualTo(0.99));
      expect(finalizingProgress.percentageLabel, 'Finalizing...');

      // ONLY completed reaches 1.0 and 100%
      final completedProgress = TransferProgress(
        fileId: 'tx_test',
        fileName: 'sample.dat',
        bytesTransferred: totalBytes,
        totalBytes: totalBytes,
        isUpload: true,
        status: TransferStatus.completed,
        timestamp: DateTime.now(),
      );
      expect(completedProgress.fraction, 1.0);
      expect(completedProgress.percentageLabel, '100%');
    });

    test('isActive and isTerminal identify running vs terminal states accurately', () {
      final runningStates = [
        TransferStatus.preparing,
        TransferStatus.connecting,
        TransferStatus.transferring,
        TransferStatus.inProgress,
        TransferStatus.verifying,
        TransferStatus.finalizing,
        TransferStatus.resuming,
      ];
      for (final state in runningStates) {
        final p = TransferProgress(
          fileId: 'tx',
          fileName: 'f',
          bytesTransferred: 0,
          totalBytes: 100,
          isUpload: true,
          status: state,
          timestamp: DateTime.now(),
        );
        expect(p.isActive, isTrue, reason: '$state should be active');
        expect(p.isTerminal, isFalse, reason: '$state should not be terminal');
      }

      final terminalStates = [
        TransferStatus.completed,
        TransferStatus.failed,
        TransferStatus.cancelled,
      ];
      for (final state in terminalStates) {
        final p = TransferProgress(
          fileId: 'tx',
          fileName: 'f',
          bytesTransferred: 0,
          totalBytes: 100,
          isUpload: true,
          status: state,
          timestamp: DateTime.now(),
        );
        expect(p.isActive, isFalse, reason: '$state should not be active');
        expect(p.isTerminal, isTrue, reason: '$state should be terminal');
      }
    });
  });
}
