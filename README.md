# mmx

A clean-room, cross-platform mesh studio and geometry kernel built from a
reverse engineering study of **Autodesk Meshmixer 3.5.0**.

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Dart](https://img.shields.io/badge/Dart-3.13%2B-blue)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.47%2B-02569B)](https://flutter.dev)
[![CI](https://github.com/palindsay/mmx/actions/workflows/ci.yml/badge.svg)](https://github.com/palindsay/mmx/actions/workflows/ci.yml)

> **Status: pre-1.0.** The core geometry workflows are usable and tested; the
> release acceptance is tracked in [`docs/PRODUCTION-READINESS.md`](docs/PRODUCTION-READINESS.md).
> The source is Apache-2.0. Sample models are Autodesk assets; see
> [`NOTICE`](NOTICE).

## What this is

mmx has two parts:

- **`mmx_core`** - a pure-Dart geometry kernel: import/export, topology,
  repair, remeshing, decimation, SDF solidification, booleans, analysis,
  supports, packing and slicing.
- **`mmx_studio`** - a Flutter desktop app for selection, sculpting, repair,
  remesh/reduce, solid/hollow, plane cuts, mirroring, supports, analysis and
  print preparation.

The reverse-engineering report is part of the repository:
[`docs/REVERSE-ENGINEERING.md`](docs/REVERSE-ENGINEERING.md). It separates
**[observed]** evidence from **[inferred]** conclusions and **[unknown]**
constants, and documents the `.mix` binary format, RTTI, recovered method names
and tool semantics.

## Documentation

- [Documentation index](docs/README.md)
- [Reverse-engineering report](docs/REVERSE-ENGINEERING.md)
- [Tool and action coverage](docs/TOOL-MATRIX.md)
- [CLI reference](docs/CLI.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Testing and coverage](docs/TESTING.md)
- [Production readiness and remaining release gates](docs/PRODUCTION-READINESS.md)
- [Installers, signing and rollback](docs/RELEASE.md)
- [Performance measurement](docs/PERFORMANCE.md)
- [Finish plan](docs/FINISH-PLAN.md)
- [Remediation plan](docs/REMEDIATION-PLAN.md)

## Features

**Formats:** OBJ, PLY, STL (binary/ASCII), OFF, 3MF (OPC zip) and native
Meshmixer `.mix` scenes. The `.mix` reader supports VFMesh 1.2 and 1.3, face
groups and lossless rewrite of unknown records. Native `.mmx` projects preserve
the whole editable scene and original imported `.mix` bytes. OBJ/OFF/PLY support
concave polygons; PLY accepts ASCII and both binary byte orders. Unsupported
3MF material/extension semantics fail explicitly.

**Geometry:** CSR topology, BVH raycast/closest-point, weld, crack closing,
hole filling, non-manifold splitting, defect inspection, isotropic and
adaptive remeshing, QEM and uniform decimation, SDF voxelization, surface-nets
polygonization, Make Solid, offset, hollow, booleans with an explicit fallback,
plane cutting with capping, mirroring, extrusion, shell separation, ICP
alignment, primitive fitting and procedural stamps.

**Analysis and fabrication:** wall thickness, overhang, stability, deviation,
mass properties, clearance, support forests, orientation search, 2D bed packing
and layer slicing.

**Studio:** object browser, tool panels, sculpt/select brushes, analysis heat
maps, grouped sculpt undo, viewport transform/pivot handles, explicit import
units, project recovery, native file dialogs, and touch orbit/pinch gestures.
Geometry and rendering run in workers; cancellation terminates active CPU work.
Linux, Windows and macOS have build, integration and installer CI jobs.

## Build and test

Requirements: Flutter 3.47+ and Dart 3.13+. No Meshmixer installation is needed
for tests; the sample models are vendored under
`packages/mmx_core/test/fixtures/models`.

```sh
# Full verification (kernel + Studio)
./tool/verify.sh

# Kernel only
cd packages/mmx_core
dart pub get
dart analyze
dart test

# Studio
cd apps/mmx_studio
flutter pub get
flutter analyze
flutter test
```

Verification includes kernel properties, parser fidelity, worker cancellation,
desktop interactions and project recovery. Commands and coverage gates are in
[`docs/TESTING.md`](docs/TESTING.md).

## CLI

```sh
cd packages/mmx_core
dart run bin/mmx.dart info model.obj
dart run bin/mmx.dart reduce model.obj out.stl --percent 0.3
dart run bin/mmx.dart remesh model.obj out.stl --edge 1.2 --iters 4
dart run bin/mmx.dart solid model.obj solid.stl --mode accurate --res 160
dart run bin/mmx.dart hollow model.obj shell.stl --thickness 2 --holes 4
dart run bin/mmx.dart supports model.obj supports.stl --angle 45
dart run bin/mmx.dart analyze model.obj
dart run bin/mmx.dart measure model.obj
dart run bin/mmx.dart convert model.obj scene.mix
dart run bin/mmx.dart render model.obj view.png --width 1200 --height 800

# AOT build
dart compile exe bin/mmx.dart -o mmx
```

## Desktop app

```sh
cd apps/mmx_studio
flutter pub get
flutter run -d linux        # or windows / macos
flutter build linux --release
```

Use the Project menu to open/save `.mmx` projects, transform the selected object,
and apply booleans. Native dialogs import/export mesh files; project saves preserve
the whole scene. Recovery autosaves are offered on restart.

The app starts with a procedural sphere. Repository sample models are test
fixtures and are excluded from release bundles.

## Performance

The AOT benchmark records workload hashes, host/toolchain identity, latency
samples and process peak memory. Compare runs on the same quiet machine with
identical inputs; see [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md). Kernel
benchmarks do not measure interactive frame latency.

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md),
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) and [`SUPPORT.md`](SUPPORT.md).
Security issues follow [`SECURITY.md`](SECURITY.md). The project uses a clean-room rule: no Autodesk
source code is copied; the binary, its RTTI/strings and public API headers are
the evidence.

## License and attribution

The mmx source code is licensed under the **Apache License 2.0**. See
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

The sample geometry (`bunnyr.obj`, `dog.obj`, `elephant.obj`, `gremlin.obj`,
`plane.obj`, `sphere.obj`) comes from the Meshmixer installer and remains
Copyright Autodesk, Inc. It is included as repository test fixtures and excluded
from binary releases. The public API headers under `docs/reference/` are reproduced from
Autodesk's `meshmixer/mm-api` repository for reference.

Meshmixer is a trademark of Autodesk, Inc. mmx is an independent project and is
not affiliated with or endorsed by Autodesk.

## Acknowledgments

The geometry approach follows published work by Botsch, Kobbelt, Sorkine and
Schmidt, and the open-source lineage around Meshmixer (geometry3Sharp,
Cotangent2 and libgeometry). Those projects informed the algorithms; mmx does
not link against them.
