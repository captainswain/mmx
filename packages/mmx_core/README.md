# mmx_core

Pure-Dart geometry kernel for the [mmx project](../../README.md): a clean-room
reimplementation of the useful geometry and fabrication workflows of Autodesk
Meshmixer 3.5.0.

Licensed under Apache-2.0. See the root [`LICENSE`](../../LICENSE),
[`NOTICE`](../../NOTICE) and [`docs/REVERSE-ENGINEERING.md`](../../docs/REVERSE-ENGINEERING.md).

## What is included

- Mesh import/export: OBJ, ASCII/binary PLY, STL, OFF, 3MF and native `.mix`
  (VFMesh 1.2/1.3, face groups, lossless rewrite of unknown records). `.mmx`
  projects persist scene metadata and original `.mix` source attachments.
- Topology: CSR adjacency, edge incidence, boundary loops, components and
  manifold checks.
- Repair: weld, crack closing, hole filling, non-manifold splitting, inspector.
- Remeshing and decimation: isotropic, adaptive, group-aware, linear
  subdivision, QEM/uniform/max-deviation reduce.
- Solid: narrow-band SDF voxelization, surface-nets polygonization, Make Solid,
  offset, hollow, booleans with an explicit grid fallback.
- Analysis: thickness, overhang, stability, deviation, mass properties,
  clearance.
- Fabrication: support forest, orientation, 2D packing, slicing.
- Tools: plane cut, mirror, extrude, shell separation, normal flip, smoothing,
  stamps, primitives, alignment, face groups, selection sets, complex
  split/filter/join, tube, polygon, part, pivot and planar unwrap.
- Rendering: orbit camera, software z-buffer rasterizer, PNG encoder.
- CLI in `bin/mmx.dart` covering the operators.

## Use

```yaml
dependencies:
  mmx_core:
    path: ../packages/mmx_core
```

```dart
import 'package:mmx_core/mmx_core.dart';

final mesh = MeshIO.readFile('model.obj');
final reduced = Decimator.reduce(mesh, percentage: 0.4);
MeshIO.writeFile('out.stl', reduced);
```

Heavy operators are deterministic and allocation-bounded; run them in an
isolate from a UI layer.

## Test

```sh
dart pub get
dart analyze
dart test
```

The test models are vendored under `test/fixtures/models`; no Meshmixer
installation is required. See [`docs/TESTING.md`](../../docs/TESTING.md) for
coverage gates and the analytical/reference corpus.

## Status

Pre-1.0. The remaining project work is tracked in
[`docs/PRODUCTION-READINESS.md`](../../docs/PRODUCTION-READINESS.md).
