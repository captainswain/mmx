# Architecture: mmx (cross-platform mesh studio)

Goal: reproduce the useful behaviour of Meshmixer 3.5.0 on Windows, macOS,
Linux, Android and iOS, from one codebase, without shipping a 26 MB MSVC/Qt
binary and without a legacy OpenGL dependency.

## 1. Technology decision

The brief asked for "high performance multi-platform", with Dart/Flutter
suggested. What was actually built, and why:

| Option | Verdict |
|---|---|
| **Dart kernel + Flutter UI (chosen)** | One language for UI and geometry, AOT compilation on every desktop/mobile target, real parallelism through isolates, typed-array kernels that the AOT compiler turns into tight loops. No FFI marshalling, no dual toolchain, no plugin dependencies. |
| Flutter UI + Rust core via `flutter_rust_bridge` | Strictly faster on the hottest loops and gives access to `wgpu`. The right next step *if* profiling shows the kernel is the bottleneck, but it doubles the build surface and adds a bridge to maintain. |
| C++/Qt (what Meshmixer did) | Best raw speed and the reason Meshmixer is fast, but Qt 5 + MSVC + per-platform packaging is exactly the tax this project exists to avoid. |
| Rust + `wgpu` + `egui` | Excellent performance and one language, but UI iteration (panels, sliders, drag and drop, text input) is slower to build and less polished on mobile. |
| Unity / Unreal | Overkill for a tool with a tool-stack UI and a handful of operators. |

The chosen split is deliberate: **Dart owns the geometry kernel and the app**,
and the rendering boundary is an interface (`Rasterizer`) so a GPU backend can
replace the software one without touching the operators.

## 2. What is implemented

```
packages/mmx_core/                 pure Dart kernel (no Flutter dependency)
  lib/src/mesh/        tri_mesh, topology (CSR adjacency, edge->face, boundary loops,
                       components, manifold tests)
  lib/src/spatial/     BVH: raycast/closest-point/overlap
  lib/src/repair/      weld, crack closing, hole filling (ear clip + relaxation),
                       boundary-loop bridging/stitching, non-manifold splitting,
                       defect inspector
  lib/src/remesh/      isotropic remeshing (split/collapse/flip/relax/project),
                       adaptive-density remeshing with a live validated
                       topology, linear subdivision, QEM
                       decimation (area-weighted quadrics) with a uniform
                       shortest-edge mode and max-deviation stop
  lib/src/solid/       narrow-band SDF voxelizer (ray-parity sign, flood fill),
                       surface-nets polygonizer, make-solid (Fast reprojects onto
                       the input), offset, hollow with escape holes, grid CSG,
                       mesh-level precise boolean (classify + stitch, grid fallback)
  lib/src/analysis/    thickness, overhang, stability, deviation, mass properties
  lib/src/fab/         support forest (posts + struts + bases), orientation
                       search, 2D raster packing, layer slicing
  lib/src/tools/       plane cut (Slice Groups, fixed fill), sculpt brushes with
                       dynamic refinement, selection sets, face groups, soft
                       transform, flip normals, Taubin smoothing, bed placement,
                       duplicate/combine, pattern arrays, primitive fitting,
                       measure, clearance, ICP alignment, procedural stamps,
                       complex split/filter/join, add-tube, make-polygon,
                       make-part/solid-part, pivot, planar unwrap,
                       soft-move/bend
  lib/src/scene/       document, scene objects, snapshot undo with byte budget
  lib/src/io/          OBJ/PLY/STL/OFF/3MF plus the native .mix container
                       (VFMesh 1.2/1.3, face groups, pass-through rewrite)
  lib/src/render/      orbit camera, software z-buffer rasterizer, PNG encoder
  bin/mmx.dart         CLI for every operator
apps/mmx_studio/                   Flutter app (Windows/macOS/Linux today)
```

Mapping from the recovered Meshmixer sources to this tree:

| Meshmixer source | mmx_core |
|---|---|
| `VFTriangleMesh`, `GSurface`, `MeshIO*` | `mesh/tri_mesh.dart`, `io/*` |
| `IMeshOctree`, `OctreeFaceDecomposition` | `spatial/bvh.dart` |
| `MeshRasterizer::RasterizeVolume_RayCast`, `MeshToSolid` | `solid/voxel.dart` |
| `ImplicitPolygonizer` | `solid/surface_nets.dart` |
| `MeshBoolean`, `SurfaceOffset` | `solid/solidifier.dart` |
| `SurfaceRemesher`, `VariationalRemesher`, `MeshRefinement` | `remesh/isotropic.dart` |
| `MeshReducer` | `remesh/decimate.dart` |
| `SimpleHoleFiller`, `LoopStitcher`, `BoundaryJoiner/Stitcher/Bridge` | `repair/holes.dart`, `repair/weld.dart`, `repair/bridge.dart` |
| `MeshThicknessAnalysis`, `OverhangTracker`, `StabilityTool` | `analysis/analysis.dart` |
| `SupportForestGenerator`, `SupportPostGraph` | `fab/supports.dart` |
| `ObjectPacker_2DRasterizeJob`, `ImagePacker` | `fab/packing.dart` |
| `MeshPlaneSlicer`, `MeshStepSlicer` | `fab/slicer.dart`, `tools/plane_cut.dart` |
| `BrushTool2`, `StandardBrushOps3D`, `RefineOp3D` | `tools/sculpt.dart` |
| `MeshMirror`, `SurfaceExtruder`, `SeparateShellsTool` | `tools/edits.dart` |
| `FlipNormalsTool`, `DuplicateTool`, `MakePatternTool`, `FitPrimitiveTool`, `MeasuringTool`, clearance tools | `tools/modify.dart` |
| `AlignToTargetTool` (rigid registration) | `tools/align.dart` |
| `StampTool` (height-field displacement) | `tools/stamp.dart` |
| `lib3mf` (3MF import/export) | `io/threemf.dart`, `io/zip.dart` |
| `VFMesh`/`GSurf`/`MMGS` (`.mix` binary blocks) | `io/mix.dart` |
| `MeshSO`/`Scene`/`StoredCommands` | `scene/document.dart` |
| `Renderer`, `mmShaderManager` | `render/rasterizer.dart` |

## 3. Performance engineering

Measured on an 8-core x86-64 Linux host with `dart compile exe` (AOT) against
the shipped `bunnyr.obj` (5,550 verts / 10,996 faces):

| Operation | Time |
|---|---|
| Import + topology + BVH build | 38 ms |
| QEM decimate 50 % (10,996 -> 5,498 faces) | 108 ms |
| Isotropic remesh, 4 iterations | 394 ms |
| Make Solid, 128³ grid (183 k output faces) | 1.20 s |
| Hollow with escape holes | 1.62 s |
| Thickness scan (per-vertex ray casts) | 56 ms |
| Support forest (55 posts) | 46 ms |
| Pack 6 objects on a 300×300 bed | 1 ms |
| Slice at 0.2 mm (250 layers) | 254 ms |
| Render 960×640 with z-buffer | 12 ms |

Techniques used, in order of impact:

1. **Flat typed arrays, no per-element objects.** Vertices and indices are
   `Float32List`/`Uint32List`; adjacency is CSR (`vFaceStart`/`vFaces`), edge
   incidence is an integer-keyed map. Hot loops allocate nothing.
2. **Isolates for every heavy operator.** The UI calls `Isolate.run` with
   captured typed arrays; the Dart VM copies/transfers the buffers and the UI
   thread stays responsive. There is no shared mutable state between workers,
   which removes an entire class of races the original job framework had to
   guard against.
3. **Narrow-band SDF instead of full-grid distance.** Only cells within
   `bandCells` of the surface get exact point-triangle distances; the far field
   is flood-filled and clamped. This is what makes a 128³ make-solid finish in
   about a second.
4. **BVH for every spatial query** (ray casts, closest point, thickness,
   projection, support drop). Build is median-split; queries are
   stack-traversal with slab tests.
5. **Rebuild-per-pass for topology-changing operators.** Remeshing rebuilds
   adjacency between passes instead of maintaining a half-edge structure
   incrementally; for the mesh sizes this tool targets the rebuild is cheaper
   than the bookkeeping, and it keeps the code auditable.

## 4. Rendering

The viewport uses a software rasterizer that produces an RGBA frame which
Flutter uploads with `decodeImageFromPixels`. That is a portability decision,
not a speed claim:

* It runs identically on Windows/macOS/Linux/Android/iOS with no platform view
  and no GL/Vulkan/Metal context plumbing.
* It gives a real z-buffer, per-face shading, selection tinting, per-vertex
  analysis heat maps, a cut-plane preview and the print bed, matching what the
  legacy OpenGL path in the original does.
* 12 ms/frame for an 11 k-face model at 960×640 leaves headroom for the UI, and
  the frame is produced off the UI isolate.

**Known ceiling:** beyond roughly 300–500 k visible triangles the software path
becomes the bottleneck. The next step is a `wgpu`-backed renderer behind the
same `Rasterizer` interface (or `flutter_gpu` once it is stable), which is why
the interface takes plain arrays and a camera rather than Flutter objects.

## 5. Correctness and verification

`dart test` runs 98 tests against the models that ship inside the Meshmixer
installer, asserting invariants rather than snapshots:

* import/export round trips for STL/OBJ/PLY preserve area within 1e-4;
* decimation keeps volume within ±15 % and area within 20 % at 25 % budget;
* remeshing produces mean edge length near the requested target and valence ≈ 6;
* Make Solid returns a mesh with **zero boundary loops** (watertight) and volume
  within 15 % of the input;
* boolean difference removes volume and stays closed; union of disjoint shapes
  yields two components;
* hollow yields a closed shell with a volume consistent with wall thickness;
* plane cut caps the cut and stays closed;
* analysis operators return physically plausible numbers (thickness > 0,
  overhang area < total area, COM inside the support polygon);
* edit operators: normal flips reverse signed volume, Taubin smoothing keeps
  volume within 5 %, bed placement lands the lowest point on the bed, join and
  pattern produce the expected shell counts, fitted primitives are closed, and
  measured clearance matches the analytic gap between separated spheres;
* group-aware remeshing preserves the face-group ids and both sides of a seam;
* `.mix` round trips preserve vertex/face counts and volume, and files written
  by mmx_core open in Meshmixer 3.5.0 under Wine with matching counts;
* ICP recovers a known rigid offset (RMS below 0.35 mm on a 25 mm sphere) and
  leaves an already-aligned mesh fixed;
* bridging a two-loop slit closes both boundary loops with no non-manifold
  edges, and the crease/twist brushes keep the mesh valid and finite;
* a circular stamp raises the surface and increases volume, while a ring stamp
  leaves the centre vertex fixed;
* undo/redo restores object state.

## 6. Limitations and next steps

1. **GPU renderer.** Software raster for portability today; `wgpu`/Impeller
   backend for large scenes.
2. **Exact booleans.** Current CSG is implicit-grid based (as the original
   appears to be). A mesh-exact boolean would preserve sharp features at low
   resolution.
3. **`VariationalRemesher` equivalence.** Group-boundary preservation is now
   implemented (seam pinning plus group transfer), but it is constraint-based
   rather than a full variational energy solve, so the original's density
   transition fields are approximated by the isotropic target length.
4. **AMF and `.mix` extras.** OBJ/PLY/STL/OFF/3MF and the `.mix` mesh/scene
   container are supported. AMF is still not parsed, and `.mix` import ignores
   PivotSO/DecalSO records, stamps and shaders (mesh objects are imported).
5. **Mobile UI.** Pinch zoom and two-finger orbit are implemented, and the
   panel collapses into a drawer under 900 px. Stylus pressure is not wired to
   brush strength, and Android/iOS are scaffolded but not built on this host
   (no Android SDK installed).
