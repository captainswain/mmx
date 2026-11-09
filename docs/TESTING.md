# Testing and coverage

## Verification

Run `./tool/verify.sh` from the repository root. It resolves dependencies, checks
Dart formatting, runs both analyzers, then executes the kernel and Studio suites.
Tests use checked-in fixtures; no Meshmixer installation is required.

Observed on 2026-11-09: 169 kernel tests and 53 Studio tests pass; both analyzers
and formatting checks are clean. The analytical corpus passes all 22 cases.

For focused work:

```sh
cd packages/mmx_core
dart test test/geometry_acceptance_test.dart test/io_fidelity_test.dart
dart run tool/validate_corpus.dart
cd ../../apps/mmx_studio
flutter test test/interaction_test.dart test/recovery_test.dart test/worker_runtime_test.dart
xvfb-run -a flutter test integration_test -d linux
```

Use `-d windows` or `-d macos` on those hosts, without Xvfb. The native integration
workflow checks procedural startup, native plugin registration, non-ASCII paths,
import units, reduction, undo/redo, project save/reopen, and watertight STL export.
It injects file paths; native dialogs and clean-account accessibility still need
manual acceptance. See [release procedures](RELEASE.md).

## Regression coverage

- Geometry tests assert closed/manifold/oriented topology and analytical volume,
  exercise extreme scales, overlapping/disjoint/empty booleans, repeated edits,
  attribute interpolation, and allocation limits. Randomized cases use fixed seeds.
- Parser tests cover binary byte orders, reordered PLY properties, concave faces,
  malformed indices, archive checksums/limits, 3MF instances/units, project metadata
  and byte-preserved imported `.mix` source attachments.
- Studio tests cover transform/pivot gestures, single-entry sculpt undo, spatial
  cache invalidation, stale results, failed/canceled import rollback, recovery
  write ordering, unreadable recovery preservation and keyboard save shortcuts.
- Completion tests keep open/save/import locked through rendering, preserve new
  edits from completion listeners, and roll back failed incoming previews.
  Recovery leases isolate simultaneous sessions; a real child-process crash
  test verifies exclusive ownership and subsequent recovery.
- Worker tests terminate an active synchronous CPU loop, cancel during spawn,
  propagate errors, and verify unexpected worker exit completes promptly.
- Python packaging tests verify repeated archives are byte-identical and file
  manifests/checksums reflect their contents.

## Coverage gate

```sh
./tool/coverage.sh
python3 -B -m unittest discover -s tool -p 'test_package_release.py'
```

The collector uses a fresh temporary directory for raw coverage on every run;
merging stale records after source changes can produce incorrect line counts.
The current report is `packages/mmx_core/coverage/lcov.info`.

CI requires more than 80% line coverage separately for native project IO,
atomic writes, ZIP, 3MF, polygon triangulation, OBJ, PLY, STL, mesh attribute
transfer and generated-mesh allocation guards. Missing records
fail the gate. This is a targeted line-coverage requirement; it does not establish
exhaustive parser fuzzing, branch coverage or whole-project coverage.

The fresh local run measured 100% for OBJ, PLY, STL, 3MF, atomic writes and mesh
allocation guards; 99.5% for project IO, 99.3% for ZIP, 98.8% for triangulation
and 96.4% for attribute transfer.

## Geometry references and performance

The [analytical corpus](../packages/mmx_core/tool/corpus/README.md) reports explicit
volume tolerances and topology requirements. Its reference-manifest mode accepts
independently acquired Meshmixer output and records comparison failures. No such
external output has been supplied, so analytical success proves no parity claim.

[Performance instructions](PERFORMANCE.md) describe host identity, exact input
hashes, AOT samples, peak RSS and regression budgets. Run measurements on an idle,
fixed host; never gate kernel latency using unrelated shared-runner baselines.

## Algorithm limits

Adaptive density is a heuristic. Precise boolean and adaptive-remesh fallbacks
are reported explicitly. Hollow thickness is approximate within voxel error;
Make Solid rejects positive `minThickness` because a global minimum-wall solver
is unimplemented. Grid reconstruction has no material-region correspondence
guarantee. Planar unwrap has no persisted UV layer. Imported unknown `.mix`
records are retained as source attachments; they are not interpreted as editable
scene objects. These limitations are tracked in [production readiness](PRODUCTION-READINESS.md).
