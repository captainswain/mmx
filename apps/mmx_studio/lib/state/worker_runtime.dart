import 'dart:async';
import 'dart:isolate';

/// Cancellation is a normal operation outcome, distinct from a kernel failure.
class WorkerCancelled implements Exception {
  const WorkerCancelled();
  @override
  String toString() => 'Operation cancelled';
}

final _activeWorkers = <Future<Object?>, _WorkerHandle<Object?>>{};

/// Execute a sendable computation in an owned isolate. Ownership remains in the
/// caller isolate so cancellation can terminate synchronous CPU work immediately.
Future<T> executeWorker<T>(FutureOr<T> Function() computation) {
  final handle = _WorkerHandle<T>();
  _activeWorkers[handle.result.future] = handle;
  unawaited(handle.start(computation));
  return handle.result.future;
}

/// Returns false for completed or externally supplied futures.
bool cancelWorker(Future<Object?> future) {
  final handle = _activeWorkers[future];
  if (handle == null) return false;
  handle.cancel();
  return true;
}

class _WorkerHandle<T> {
  final result = Completer<T>();
  final messages = ReceivePort();
  Isolate? isolate;
  bool finished = false;

  Future<void> start(FutureOr<T> Function() computation) async {
    messages.listen((dynamic event) {
      if (finished) return;
      if (event is List && event.length == 1) {
        _finish();
        result.complete(event.single as T);
      } else {
        final Object error;
        final StackTrace trace;
        if (event is List && event.length == 2) {
          error = event[1] is StackTrace
              ? event[0] as Object
              : RemoteError(event[0].toString(), event[1].toString());
          trace = event[1] is StackTrace
              ? event[1] as StackTrace
              : StackTrace.fromString(event[1].toString());
        } else {
          error = StateError('Worker exited without a result');
          trace = StackTrace.current;
        }
        _finish();
        result.completeError(error, trace);
      }
    });
    try {
      final child = await Isolate.spawn(
        _workerEntry<T>,
        (computation, messages.sendPort),
        paused: true,
        onError: messages.sendPort,
        onExit: messages.sendPort,
        errorsAreFatal: true,
        debugName: 'mmx geometry worker',
      );
      if (finished) {
        child.kill(priority: Isolate.immediate);
      } else {
        isolate = child;
        child.resume(child.pauseCapability!);
      }
    } catch (error, trace) {
      if (!finished) {
        _finish();
        result.completeError(error, trace);
      }
    }
  }

  void cancel() {
    if (finished) return;
    isolate?.kill(priority: Isolate.immediate);
    _finish();
    result.completeError(const WorkerCancelled(), StackTrace.current);
  }

  void _finish() {
    finished = true;
    _activeWorkers.remove(result.future);
    messages.close();
  }
}

void _workerEntry<T>((FutureOr<T> Function(), SendPort) input) async {
  try {
    final value = await input.$1();
    Isolate.exit(input.$2, <Object?>[value]);
  } catch (error, trace) {
    Isolate.exit(input.$2, <Object?>[error, trace]);
  }
}
