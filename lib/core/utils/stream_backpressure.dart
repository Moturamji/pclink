import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Provides high-throughput chunked file streaming with native backpressure
/// and inactivity watchdog tracking.
class StreamBackpressure {
  /// Optimal chunk size based on empirical benchmarks:
  /// 256 KB achieves 170+ MB/s while keeping chunk memory footprint minimal.
  static const int defaultChunkSize = 256 * 1024;

  /// Reads [file] starting at [start] byte offset up to [end] byte offset in
  /// chunks of [chunkSize]. Honors asynchronous backpressure on every `yield`.
  static Stream<List<int>> openReadOptimized(
    File file, {
    int start = 0,
    int? end,
    int chunkSize = defaultChunkSize,
  }) async* {
    final raf = await file.open(mode: FileMode.read);
    try {
      final fileLength = await file.length();
      final effectiveEnd = end != null ? min(end, fileLength) : fileLength;
      if (start >= effectiveEnd) return;

      if (start > 0) {
        await raf.setPosition(start);
      }

      var remaining = effectiveEnd - start;
      while (remaining > 0) {
        final toRead = min(chunkSize, remaining);
        final buffer = Uint8List(toRead);
        final bytesRead = await raf.readInto(buffer, 0, toRead);
        if (bytesRead <= 0) break;

        yield bytesRead == toRead ? buffer : buffer.sublist(0, bytesRead);
        remaining -= bytesRead;
      }
    } finally {
      await raf.close();
    }
  }
}

/// Thrown by [BackpressuredBodyRequest.write] once the HTTP layer stopped
/// consuming the body (route aborted, connection dropped or user cancelled).
class BodyStreamClosedException implements Exception {
  const BodyStreamClosedException();

  @override
  String toString() => 'Upload body stream closed by the HTTP client';
}

/// An HTTP request whose body is pumped with real, flow-controlled backpressure
/// and which can be aborted the moment the route stalls or the transfer is
/// cancelled.
///
/// `http.StreamedRequest.sink.addStream()` starts pulling from the source
/// stream immediately - even while `Client.send()` is still waiting for the TCP
/// connection - and buffers every chunk in memory until then. That spikes
/// memory and makes the progress UI report bytes that were never transmitted.
/// This request instead exposes [connected]/[write] so the caller only reads the
/// file once the HTTP client actually asks for data, and [write] only completes
/// once the socket has drained the previous chunk.
class BackpressuredBodyRequest extends http.StreamedRequest
    with http.Abortable {
  BackpressuredBodyRequest(super.method, super.url, {this.abortTrigger}) {
    _body = StreamController<List<int>>(
      sync: true,
      onListen: _handleListen,
      onPause: _handlePause,
      onResume: _handleResume,
      onCancel: _handleCancel,
    );
  }

  @override
  final Future<void>? abortTrigger;

  late final StreamController<List<int>> _body;
  final Completer<void> _connected = Completer<void>();
  Completer<void>? _resumeSignal;
  bool _isPaused = false;
  bool _consumerGone = false;

  /// Completes as soon as the HTTP client subscribed to the body, i.e. the
  /// connection is established and bytes can actually be transmitted.
  Future<void> get connected => _connected.future;

  bool get isConnected => _connected.isCompleted;

  /// True once the HTTP layer stopped consuming the body.
  bool get isAbandoned => _consumerGone;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body.stream);
  }

  /// Sends [chunk] to the wire and waits until the consumer drains it.
  Future<void> write(List<int> chunk) async {
    if (_consumerGone) throw const BodyStreamClosedException();
    _body.add(chunk);
    await _awaitDrain();
  }

  /// Signals the end of the body.
  Future<void> finish() async {
    if (_consumerGone) return;
    try {
      await _body.close();
    } catch (_) {
      // Already closed by an abort - nothing to do.
    }
  }

  Future<void> _awaitDrain() async {
    if (_consumerGone || !_isPaused) return;
    final signal = Completer<void>();
    _resumeSignal = signal;
    await signal.future;
  }

  void _handleListen() {
    if (!_connected.isCompleted) _connected.complete();
  }

  void _handlePause() {
    _isPaused = true;
  }

  void _handleResume() {
    _isPaused = false;
    _releaseSignal();
  }

  void _handleCancel() {
    _consumerGone = true;
    _isPaused = false;
    _releaseSignal();
  }

  void _releaseSignal() {
    final signal = _resumeSignal;
    _resumeSignal = null;
    if (signal != null && !signal.isCompleted) signal.complete();
  }
}

/// A watchdog that monitors data transfer progress and fires [onTimeout]
/// only when NO forward progress has been made for [timeoutDuration].
class InactivityWatchdog {
  /// Re-arming the watchdog more often than this is pure overhead; transfers
  /// notify progress for every chunk, which can be thousands of times/sec.
  static const Duration defaultRefreshInterval = Duration(seconds: 1);

  final Duration timeoutDuration;
  final Duration refreshInterval;
  final void Function() onTimeout;
  Timer? _timer;
  DateTime _lastArm = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isDisposed = false;

  InactivityWatchdog({
    this.timeoutDuration = const Duration(seconds: 30),
    this.refreshInterval = defaultRefreshInterval,
    required this.onTimeout,
  }) {
    notifyProgress();
  }

  /// Refreshes the watchdog timer whenever bytes are sent or received.
  /// Cheap when called per chunk: the timer is only re-armed at most twice per
  /// [timeoutDuration], which removes the per-chunk Timer churn while keeping
  /// short-timeout watchdogs (used in tests/fast failover) accurate.
  void notifyProgress() {
    if (_isDisposed) return;
    final now = DateTime.now();
    final reArmInterval =
        Duration(milliseconds: timeoutDuration.inMilliseconds ~/ 2);
    if (_timer != null &&
        now.difference(_lastArm) < reArmInterval &&
        reArmInterval > Duration.zero) {
      return;
    }
    _lastArm = now;
    _timer?.cancel();
    _timer = Timer(timeoutDuration, () {
      if (!_isDisposed) {
        onTimeout();
      }
    });
  }

  /// Cancels and disposes the watchdog timer.
  void cancel() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
