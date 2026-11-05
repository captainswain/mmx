# mmx_studio

Flutter desktop front end for the `mmx_core` mesh kernel: a cross-platform
clean-room reimplementation of Autodesk Meshmixer 3.5.0's modelling and
fabrication workflow.

Part of the [mmx project](../../README.md). Licensed under Apache-2.0; see the
root [`LICENSE`](../../LICENSE) and [`NOTICE`](../../NOTICE).

## Features

- Import/export OBJ, PLY, STL, OFF and 3MF, plus native `.mix` scenes
  (multi-object import; export writes the selected object).
- Repair: weld, hole fill, non-manifold split, inspector.
- Remesh (isotropic, optional group-boundary preservation), reduce, Make Solid,
  hollow, booleans (kernel only), offset.
- Edit tools: plane cut, mirror, extrude, separate shells, flip normals, Taubin
  smoothing, drop/center on bed, duplicate, combine, pattern arrays, primitive
  fitting, boundary-loop stitching, rigid ICP alignment onto a reference object,
  Extract, Make Part and Pivot.
- Stamps: analytic circle/ring/star/grid/noise height fields applied at the
  selection centroid.
- Analysis: wall thickness, overhang, stability, deviation, measurement,
  inter-object clearance.
- Fabrication: support forest, orientation, bed packing, slicing.
- Sculpt and face selection with dynamic refinement, undo/redo, export.

The tool matrix and the kernel-only/partial list are in
[`docs/TOOL-MATRIX.md`](../../docs/TOOL-MATRIX.md).

## Requirements

- Flutter 3.47 or newer.
- Linux, macOS or Windows desktop target.

## Run

```sh
flutter pub get
flutter run -d linux        # or windows / macos
flutter build linux --release
```

On touch screens the viewport supports one-finger orbit and two-finger orbit +
pinch zoom. The properties panel collapses into a drawer below 900 px so the
same build works on a narrow desktop window or a tablet. Android and iOS
targets are scaffolded; the Linux build is the one verified on this host.

## Tests

```sh
flutter analyze
flutter test
```

The widget suite covers the shell, operator plumbing (reduce, mirror,
flip/measure), Extract/Make Part/Pivot, the narrow layout and the touch pinch
gesture.

## Contributing

See the root [`CONTRIBUTING.md`](../../CONTRIBUTING.md) and
[`CODE_OF_CONDUCT.md`](../../CODE_OF_CONDUCT.md). Security reports follow
[`SECURITY.md`](../../SECURITY.md).
