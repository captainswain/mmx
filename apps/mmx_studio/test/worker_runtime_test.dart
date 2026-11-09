import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmx_studio/state/worker_runtime.dart';

// The port proves that the synchronous loop actually started, rather than only
// asserting cancellation of a queued future.
int endlessWorker(SendPort started) {
  started.send('started');
  var n = 0;
  while (true) {
    n = (n + 1) & 0x7fffffff;
    if (n % 100000 == 0) started.send('tick');
  }
}

Future<int> launchEndless(SendPort port) =>
    executeWorker(() => endlessWorker(port));

void main() {
  test('worker results and typed failures propagate', () async {
    expect(await executeWorker(() => 42), 42);
    await expectLater(
      executeWorker<int>(() => throw const FormatException('bad input')),
      throwsFormatException,
    );
  });

  test('cancellation terminates synchronous CPU work', () async {
    final started = ReceivePort();
    final port = started.sendPort;
    final running = Completer<void>();
    var ticks = 0;
    started.listen((event) {
      if (event == 'started' && !running.isCompleted) running.complete();
      if (event == 'tick') ticks++;
    });
    final job = launchEndless(port);
    final outcome = expectLater(job, throwsA(isA<WorkerCancelled>()));
    await running.future.timeout(const Duration(seconds: 5));
    expect(cancelWorker(job), true);
    await outcome.timeout(const Duration(seconds: 2));
    expect(cancelWorker(job), false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stoppedAt = ticks;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      ticks,
      stoppedAt,
      reason: 'Cancelled isolate must stop producing heartbeats',
    );
    // A subsequent worker is unaffected.
    expect(await executeWorker(() => 7), 7);
    started.close();
  });

  test('cancellation before spawn completes is safe', () async {
    final job = executeWorker(() => 99);
    final outcome = expectLater(job, throwsA(isA<WorkerCancelled>()));
    expect(cancelWorker(job), true);
    await outcome;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  test(
    'unexpected isolate exit and unsendable results fail promptly',
    () async {
      await expectLater(
        executeWorker<int>(() {
          Isolate.exit();
        }).timeout(const Duration(seconds: 3)),
        throwsStateError,
      );
      await expectLater(
        executeWorker(() => ReceivePort()).timeout(const Duration(seconds: 3)),
        throwsA(isNot(isA<TimeoutException>())),
      );
    },
  );

  test('external futures cannot be killed', () {
    expect(cancelWorker(Future.value(1)), false);
  });
}
