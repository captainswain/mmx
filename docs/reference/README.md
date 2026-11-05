# Reference material

These files are copies of the official Autodesk Meshmixer API headers, not
reverse-engineered artifacts. They are kept here because they document the
application's tool parameters and mesh structures at source level.

Source: <https://github.com/meshmixer/mm-api> (`build/` directory), which
Autodesk published as the remote-scripting API for Meshmixer 3.0. The headers
carry `(C) Copyright 2016 by Autodesk, Inc.` and the Autodesk license notice;
they are included unmodified.

- `StoredCommands.h` - every tool command, its parameter names, ranges and enum
  values, plus the scene/utility commands (camera, view, selection, export).
- `StoredCommands.cpp` - the serializer that shows the wire format of each
  command and the exact types sent.
- `BinarySerializer.h` - the binary stream primitives used by the API.
- `LiveMesh.h` - `PackedLiveMesh`, the packed transfer format, and the
  `VFTriangleMesh` kernel class used by `LiveMeshUtil`.
- `API-PARAMETERS.md` - generated from `StoredCommands.h`: a readable index of
  the tool names and parameters.
- `AUTODESK-HELP-NOTES.md` - summaries of the official 2019 help pages that
  describe the internal algorithm steps for Make Solid, Hollow, Boolean,
  Plane Cut, Make Pattern, Remesh and Reduce, with source URLs.

What this adds over the binary analysis:

* Exact parameter names and enum spellings for Reduce, Remesh, Make Solid,
  Hollow, Make Pattern, booleans, plane cut, smooth, align, attract, stamp,
  tube, pivot and the analysis tools.
* Confirmation that the boolean tool has `FastApproximate`, `Precise` and
  `ExtraPrecise` solution types with `useIntersectionCurves`, `robustMode`,
  `maxRefineDepth` and `postReduce` controls. The help pages then explain the
  actual method: remesh around the intersection, delete triangle strips, and
  grow boundary loops together (Join-like), not voxel CSG.
* The full tool inventory, including tools not yet in mmx (`addTube`,
  `createPivot`, `unwrap`, `generateComplex`, `splitComplex`, `filterComplex`,
  `makePart`, `makeSolidPart`, `makePolygon`, `warp`, `handle`).

`StoredCommands.cpp` is also worth reading when implementing a specific tool:
it serializes every parameter in order, so it doubles as a schema for the
desktop tool's inputs.
