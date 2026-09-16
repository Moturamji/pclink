/// A token passed to asynchronous file transfer operations to allow per-transfer cancellation.
class CancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  /// Whether cancellation has been requested for this specific transfer.
  bool get isCancelled => _isCancelled;

  /// Requests cancellation of this transfer.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
    _listeners.clear();
  }

  /// Registers a callback to be invoked when this transfer is cancelled.
  void onCancelled(void Function() listener) {
    if (_isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  /// Removes a previously registered callback.
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}
