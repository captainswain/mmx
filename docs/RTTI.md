# RTTI vtable attribution

Meshmixer ships without a PDB, so Ghidra labels functions `FUN_<address>`. The
executable does retain MSVC RTTI, which gives class names and, through the
vtables, the method slots that belong to each class. `tools/extract_rtti.py`
recovers that structure from the PE image.

## Method

1. Parse the PE section table and map RVAs to file offsets.
2. Scan `.rdata`/`.data` for Complete Object Locators (signature `1`, a
   `pTypeDescriptor` RVA that points at a `.?AV...@@` type name).
3. Treat a run of at least three `.text` pointers preceded by a COL address as
   a vtable; record every slot under the COL's class name.
4. Optionally intersect the slots with the Ghidra function corpus to see which
   methods were decompiled.

Reproduce:

```
python3 tools/extract_rtti.py /data/re/meshmixer/extract/meshmixer.exe /data/re/meshmixer/rtti
```

Outputs: `rtti_vftables.txt` (class, slot count, method RVAs) and
`rtti_classes.txt` (class, method VAs). The copies in this directory were
generated from the 3.5.0 `meshmixer.exe` (SHA-256
`73a5b989e2b5dfae4577f85a15c2d95668249f4759179bf4717d82fdef69e03b`).

## Result

**[observed]** 2,314 classes with vtables and 28,240 method slots. 913 of those
classes have at least one method in the 15,968-function Ghidra corpus.

Representative classes and slot counts:

| Class | Slots | Decompiled | Notes |
|---|---:|---:|---|
| `RemeshTool::mm` | 104 | 10 | UI/tool layer |
| `MakeSolidTool::mm` | 88 | 8 | UI/tool layer |
| `BooleanTool::mm` | 77 | 8 | UI/tool layer |
| `MakePatternTool::mm` | 126 | 19 | UI/tool layer |
| `HollowTool::mm` | 89 | 19 | UI/tool layer |
| `SurfaceRemesher::rms` | 39 | 8 | kernel remesher |
| `SurfaceReducer::rms` | 39 | 8 | kernel reducer |
| `BoundaryJoiner::rms` | 39 | 11 | boundary growing (Boolean/Join) |
| `BoundaryBridge::rms` | 39 | 10 | bridge loops |
| `BoundaryStitcher::rms` | 39 | 11 | stitch boundaries |
| `ARAPDeformer::rms` | 12 | 1 | ARAP deformation |
| `LaplacianDeformer::rms` | 17 | 5 | Laplacian deformation |
| `COILSDeformer::rms` | 17 | 5 | COILS deformation |
| `RotInvCoordDeformer::rms` | 11 | 7 | rotation-invariant coordinates |
| `M2SGridImplicit` | 8 | 2 | mesh-to-solid grid implicit |
| `MeshFileWriter::rms` | 3 | 1 | file writer dispatch |
| `UVLayerMesh::rms` | 98 | 36 | UV layer mesh |
| `VFTriangleMesh::rms` | 91 | 34 | core mesh |
| `IMeshOctree::rms` | 26 | 24 | spatial index |

Notable method addresses (VAs in the loaded image):

* `MeshFileWriter::rms`: `0x1405a5660` (decompiled; a dispatch on
  `*(param_1+0x68)` to writer routines).
* `SurfaceRemesher::rms`: `0x1409df4b0`, `0x1409e09a0` (decompiled).
* `SurfaceReducer::rms`: `0x1409dbb40`, `0x1409dc740` (decompiled).
* `BoundaryJoiner::rms`: `0x1409f1430`, `0x1409f1920`.
* `M2SGridImplicit`: `0x1406b6670` (destructor), `0x1406b7470` (distance/point
  query).

## Limits

* RTTI covers polymorphic classes only. Static-only classes such as
  `MeshBoolean`, `MeshToSolid` and `MeshReducer` have no vtable, which is why
  they do not appear in the table even though their strings and source-file
  names do.
* Slot lists include inherited methods and adjustor thunks, so a class with 39
  slots does not have 39 unique implementations. Shared slots across
  `SurfaceRemesher`, `SurfaceReducer`, `BoundaryJoiner` and others are base
  class methods.
* RTTI gives class identity, not method names. A slot can be attributed to a
  class, but its source-level name remains unknown unless the class layout or
  the call site identifies it.

## Constants seen in the attributed methods

From the decompiled `SurfaceRemesher` methods (`0x1409df4b0`, `0x1409e09a0`),
**[observed]** numeric literals include `1.3333334` (4/3), `0.8`, `10.0`, a
cubic `(x * 3.0 * x - 6.5 * x + 4.0)`, and float constants `5.0886`/`5.0888`
loaded as defaults. Their exact roles (edge-length bounds, smoothing speed,
angle threshold) are **[inferred]** from their position in the remesh loop.
