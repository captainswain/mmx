# Native UI responsiveness probe

This opt-in harness is excluded from normal correctness test discovery because
its Dart filename has no `_test.dart` suffix. Run from `apps/mmx_studio` on a
quiet host after `flutter pub get`:

```sh
xvfb-run -a flutter test integration_test/desktop_performance.dart -d linux \
  --dart-define=MMX_PERF_HOST_ID=my-fixed-host \
  --dart-define=MMX_PERF_TOOLCHAIN=Flutter-3.47.9 \
  --dart-define=MMX_PERF_REPORT=/tmp/mmx-ui-performance.json
```

On an interactive desktop, omit `xvfb-run` and select `linux`, `macos`, or
`windows`. Use an absolute writable report path appropriate to that platform.
Record the actual installed Flutter version in `MMX_PERF_TOOLCHAIN`. The report
also captures Dart version, build mode, OS, CPU, ABI, display environment, and
viewport dimensions. JSON is printed with the `MMX_UI_PERFORMANCE_JSON` prefix.
Flutter 3.47.9 forces `flutter test` to debug mode; this command has no supported
`--profile` or `--release` option.

Use the integration driver to measure a profile build:

```sh
xvfb-run -a flutter drive --profile -d linux \
  --driver=test_driver/desktop_performance_driver.dart \
  --target=integration_test/desktop_performance.dart \
  --dart-define=MMX_PERF_HOST_ID=my-fixed-host \
  --dart-define=MMX_PERF_TOOLCHAIN=Flutter-3.47.9 \
  --dart-define=MMX_PERF_REPORT=/tmp/mmx-ui-performance-profile.json
```

For repeatable captures and source/run metadata, use the repository's
[portable collector](../../../tool/performance_evidence.py) or
[performance workflow](../../../.github/workflows/performance.yml). The collector
adds `MMX_PERF_REVISION` from the actual checkout and records the installed Flutter
version. Schema 2 reports retain raw microsecond interval arrays alongside each
distribution so medians and percentiles can be independently checked. Earlier
schema 1 captures retain their original provenance and are not rewritten.

The deterministic 100,352-face torus exercises one cold 50% Reduce through
`StudioState`, then undo and cancellation of a second Reduce. Preparation and
initial rendering are excluded from operation latency. Input/output meshes must
remain valid, closed and manifold; cancellation must preserve geometry/history.

A 16 ms UI-isolate timer measures heartbeat intervals. Continuously requested
framework frames measure post-frame callback intervals, including any UI stalls.
The normal busy indicator remains animated during computation. These intervals
are not kernel execution time, GPU raster duration, or physical presentation
latency. Worker-phase duration includes isolate startup/transfer, while operation
completion includes state processing and rendering. Process RSS includes the
Flutter engine, workers and setup; the high-water mark spans the whole process.

Assertions require UI progress and completed cancellation, with no performance
thresholds or shared-CI timing gate. Xvfb results provide headless responsiveness
evidence for the recorded mode. Interactive target measurement with repeated
samples is still required before claiming frame-rate or memory budgets.
