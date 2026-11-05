# Testing and coverage

## Commands

```sh
cd packages/mmx_core
dart analyze
dart test
dart test --coverage=coverage
dart pub global activate coverage
dart pub global run coverage:format_coverage \
  --lcov --in=coverage --out=coverage/lcov.info \
  --packages=.dart_tool/package_config.json --report-on=lib
```

The kernel suite uses models shipped inside the Meshmixer installer at
`/data/re/meshmixer/extract/meshmixer/models`. The Studio app tests are run
separately with `flutter test` under `apps/mmx_studio`.

## Current status (2026-11-04)

- Kernel: 94 tests, all passing; `dart analyze` clean.
- Studio: 10 widget/state tests passing; `flutter analyze` clean.
- Measured line coverage for the newly added kernel modules:

| Module | Line coverage |
|---|---:|
| `remesh/collapse_mesh.dart` | 99.5% |
| `remesh/isotropic.dart` | 96.3% |
| `remesh/decimate.dart` | 96.9% |
| `tools/complex.dart` | 96.8% |
| `tools/deform.dart` | 100% |
| `tools/pivot.dart` | 100% |
| `tools/polygon.dart` | 100% |
| `tools/tube.dart` | 100% |
| `tools/unwrap.dart` | 100% |
| `repair/holes.dart` | 93.5% |
| `io/mix.dart` | 99.3% |
| `solid/mesh_boolean.dart` | 96.0% |
| `solid/solidifier.dart` | 95.3% |
| `tools/plane_cut.dart` | 76.8% |

`plane_cut.dart` is lower because the coverage tool does not attribute the
nested `splitVertex` and degenerate on-plane branches cleanly; the normal,
oblique, remeshed, fixed-fill, negative-side, slice and slice-group paths all
have tests. Do not treat the 76.8% figure as an untested feature.

## Coverage gaps worth closing

- `PreciseBoolean` fallback paths (when stitching cannot close a loop) are not
  forced by a test; the remesh-and-stitch path and `edgeLength` path are.
- `CollapseMesh.tryCollapse` is exercised through remesh tests but has no direct
  unit tests for boundary-only, sharp-constrained or duplicate-face rejection.
- Studio has no widget tests for the kernel tools added in the tool-breadth
  phase (`Pivot`, `MakePolygon`, `AddTube`, `Unwrap`, `SoftMove`,
  `ComplexTools.generate`/`makePart`). `Extract` in the UI still has its own
  copy of the region-extraction code instead of calling `ComplexTools.extract`.
- `MakePolygon.fromLoop` uses fan triangulation; concave loops are not covered.
- `Unwrap` is planar-only; there is no UV layer storage in `TriMesh` or `.mix`.
- `.mix` `PivotSO`, `DecalSO`, texture/UV and stamp records are preserved by
  `MixIO.rewrite` but not decoded.

## Known product caveats

- Adaptive-density remeshing is a heuristic based on angle defect, not the
  exact Meshmixer falloff. If the validated collapse pass still detects a
  non-manifold result, the kernel falls back to uniform remeshing.
- `Solidifier._enforceMinThickness` is a simple erosion heuristic, not an exact
  wall-thickness solver.
- `PlaneCut.sliceGroups` tags only the positive side.
- Pivot creation is kernel-only; the Studio UI does not expose it yet.
