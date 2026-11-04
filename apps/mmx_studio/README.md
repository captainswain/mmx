# mmx_studio

Flutter front end for the `mmx_core` mesh kernel: a cross-platform
reimplementation of Autodesk Meshmixer 3.5.0's modelling and fabrication
workflow.

## What it does

- import/export OBJ, PLY, STL, OFF and 3MF, plus native `.mix` scenes
  (multi-object import; export writes the selected object)
- repair (weld, hole fill, non-manifold split, inspector)
- remesh (isotropic, optional group-boundary preservation), reduce, make solid,
  hollow, booleans, offset
- edit tools: plane cut, mirror, extrude, separate shells, flip normals, Taubin
  smoothing, drop/center on bed, duplicate, combine, pattern arrays, primitive
  fitting
- analysis: wall thickness, overhang, stability, deviation, measurement,
  inter-object clearance
- fabrication: support forest, orientation, bed packing, slicing
- sculpt and face selection with dynamic refinement, undo/redo, export

## Run

```bash
flutter pub get
flutter run -d linux        # or windows / macos
flutter build linux --release
```

On touch screens the viewport supports one-finger orbit and two-finger orbit +
pinch zoom. The properties panel collapses into a drawer below 900 px so the
same build works on a narrow desktop window or a tablet. Android and iOS
targets are scaffolded; the Linux build is the one verified on this host.

## Tests

```bash
flutter analyze
flutter test
```

The widget suite covers the shell, the operator plumbing end to end (reduce,
mirror, flip/measure), the narrow layout and the touch pinch gesture.
