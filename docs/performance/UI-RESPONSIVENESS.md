# Native Studio responsiveness evidence

The opt-in [desktop harness](../../apps/mmx_studio/integration_test/desktop_performance.dart)
measures a real Studio window and worker operation. Its filename excludes it
from ordinary correctness test discovery. See the adjacent
[execution instructions](../../apps/mmx_studio/integration_test/desktop_performance.md)
for debug and profile commands. Profile uses `flutter drive` with a minimal
integration driver because `flutter test` forces debug mode in Flutter 3.47.9.

## Workload and capture conditions

Recaptured after the operation-completion and per-session recovery fixes on
2026-11-09, in separate quiet windows from the kernel benchmarks:
Linux x64, AMD Ryzen 9 7950X, 32 logical processors, Linux 7.0.0-42,
Flutter 3.47.9, Dart 3.13.7. Xvfb provided the display; the viewport was
892 × 674 logical pixels at device pixel ratio 1. Raw reports include exact
runtime and host metadata:

- [Debug capture](2026-11-09-linux-ui-debug.json)
- [Profile capture](2026-11-09-linux-ui-profile.json)

Each process generates a deterministic closed torus with 50,176 vertices and
100,352 faces (224 × 224 periodic grid, radii 20 and 5, mesh fingerprint
`efae274e`). After setup and initial rendering, it observes 500 ms idle, runs
one cold Reduce at 50%, undoes it, and cancels a second Reduce at the first
UI heartbeat during computation. Both modes produced 50,176 valid, closed,
manifold output faces. Cancellation preserved the input and undo depth.

## Observations

All durations below are milliseconds. These are single captures, not medians
across independent runs or a regression threshold.

| Measurement | Debug | Profile |
| --- | ---: | ---: |
| Reduce operation completion | 955.195 | 741.463 |
| Worker await phase | 841.885 | 667.350 |
| UI heartbeat interval during worker, p95 / max | 22.367 / 95.681 | 20.565 / 34.133 |
| Framework post-frame interval during worker, p95 / max | 24.591 / 93.116 | 20.928 / 33.026 |
| Whole-operation maximum post-frame interval | 118.324 | 59.495 |
| Cancel request to worker phase end | 12.609 | 0.081 |
| Cancel request to operation settled | 141.758 | 143.197 |
| Whole-process peak RSS, MiB | 572.586 | 402.824 |

The UI loop and frame callbacks made progress during computation. The profile
capture still showed a 59.495 ms frame interval over the complete Reduce and
105.449 ms during cancellation/rollback. Those observations leave interactive
frame-budget work open; they do not establish a sustained 60 FPS experience.

## Interpretation and limits

The timer targets 16 ms. Continuously requested framework frames and the normal
busy animation expose UI-isolate stalls. Post-frame intervals measure framework
completion cadence, not GPU raster duration or physical presentation. Worker
await includes isolate startup and transfer; full operation completion also
includes checkpointing, validation, cache work and scene rendering. These
measurements are distinct from the standalone kernel timings.

Peak RSS includes Flutter, workers, setup and validation, and cannot reset
between operations in one process. Debug and profile have different runtime
costs and must be compared separately. No timing thresholds run in shared CI;
the harness asserts mesh correctness, UI progress and successful cancellation.
Repeated profile/release captures on interactive target hardware are still
needed for frame-rate and memory budgets. Windows/macOS responsiveness was not
measured by these Linux captures.
