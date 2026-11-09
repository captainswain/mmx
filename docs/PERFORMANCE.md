# Performance validation

## Reproducible kernel measurements

Run from `packages/mmx_core` on an otherwise idle, dedicated machine:

```sh
dart pub get
dart compile exe tool/performance.dart -o /tmp/mmx-performance
/tmp/mmx-performance --host-id=workstation-a > /tmp/baseline.json
/tmp/mmx-performance --host-id=workstation-a \
  --baseline=/tmp/baseline.json > /tmp/candidate.json
```

Choose a stable, non-sensitive host label and preserve the original baseline.
Recompile after changing sources. Use an absolute executable path; on Windows,
choose an `.exe` output path. Baselines belong to the host and toolchain that
produced them, rather than to arbitrary hosted CI runners.

Each of six cases runs in its own AOT process, performs one warmup, and records
three operator calls. Inputs are the vendored 12k-face sphere and a mesh reduced
to approximately 100k faces after two subdivisions. Operations are 50% Reduce,
two Remesh iterations at bounding-box diagonal / 60, and Make Solid at resolution
96. Import, input preparation, process startup, and output checks are excluded
from operator timings. Reports retain all samples, median, min/max, output face
counts, and worker wall time. Three samples are a small repeatability check,
not a tail-latency distribution or confidence interval.

The runner rejects JIT captures. Schema 2 comparisons require identical host ID,
CPU model, logical CPU count, architecture, OS version, physical RAM, Dart
runtime, execution settings, parameters, and exact prepared-input SHA-256
fingerprints. Linux also records available CPU affinity, governor, and cgroup
limits. These checks cannot establish that a machine is idle or has the same
thermal state; operators must control background activity and power settings.
The 100k input depends on the reducer: algorithm corrections can change its hash
and correctly invalidate a comparison.

The JSON records executable and working-tree hashes, Git revision/status, and
fixture hash for investigation. Working-tree hashes describe files at capture
time; always compile immediately before capturing to associate them with the
executable. A dirty tree is recorded explicitly rather than presented as a
release commit.

## Regression gate and memory

A compatible candidate fails if any median exceeds its baseline by **more than
20%**; exactly 20% passes. Exit status is `0` for a capture/pass, `1` for a latency
regression, and `2` for invalid input, failed measurement, or incompatible
provenance. Missing cases, nonpositive samples, and medians inconsistent with
raw samples are rejected. A saved report can be checked without rerunning work:

```sh
dart run tool/performance.dart --baseline=/tmp/baseline.json \
  --compare=/tmp/candidate.json
dart test test/performance_test.dart
```

Per-case `processPeakRssBytes` uses Dart's process resident-memory high-water
mark. It includes loading the prepared mesh, warmup, all three operations,
validation, and fingerprint checks. This is neither incremental operator
allocation nor peak Dart heap usage. Fresh processes prevent another workload's
peak from contaminating the value. RSS meanings differ across operating systems;
compare only the same host and OS. Post-operation RSS samples and startup RSS
are also retained. No memory threshold is asserted without a reviewed capacity
budget.

The benchmark validates basic mesh structure and positive finite output volume.
Topology and geometric accuracy are covered separately by
`test/geometry_acceptance_test.dart` and `tool/validate_corpus.dart`; faster
results do not establish correctness. These measurements are kernel latency,
not UI frame time, interaction latency, cancellation latency, or responsiveness.
Studio still needs representative hardware measurements of those properties.

## Observed local evidence

Measurements and historical comparison are recorded below after capture.
