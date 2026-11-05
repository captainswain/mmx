# Reverse engineering report: Autodesk Meshmixer 3.5.0 (Windows x64)

Target: <https://marketplace.autodesk.com/apps/2e40e347-0369-4603-b83f-ecab324aed0f>
(Meshmixer, Autodesk Inc., version 3.5.0, released 2024-11-12, last updated
2025-01-06, listed as no longer in development).

Everything below is tied to the shipped artifact. Observations are labelled
**[observed]**, inferences **[inferred]**, and open questions **[unknown]**.

## 1. Artifact identity

| Item | Value |
|---|---|
| Installer | `Autodesk_Meshmixer_v3p5_Win64.exe`, 105,521,856 bytes |
| SHA-256 | `5d08cb6254e4d4280137d6d37ec689fc3f0c61dad08bbc978a451ac16b7f271c` |
| Installer type | NSIS self-extracting PE32 i386 stub (**observed**: `$PLUGINSDIR`, `Uninstall.exe.nsis`, 672 files / 317 MB extracted) |
| Main executable | `meshmixer.exe`, 26,177,848 bytes, PE32+ AMD64 |
| SHA-256 | `73a5b989e2b5dfae4577f85a15c2d95668249f4759179bf4717d82fdef69e03b` |
| Toolchain | MSVC 2015 runtime (`MSVCP140`, `mfc140u`, `VCRUNTIME140`) **[observed]** |
| UI framework | Qt 5.9.3, MSVC 2015 x64, dynamic (**observed** version string in `Qt5Core.dll`) |
| Bundled libraries | `lib3MF.dll`, `libPrint3D.dll`, `boost_{chrono,filesystem,system,thread}-vc140-mt-1_61`, `libpng15`, `zlib`, `libacml_dll` (AMD ACML BLAS/LAPACK), `pgc.dll`/`pgftnrtl.dll` (PGI Fortran runtime), `Chronicle.dll`, `MC3.dll`, `MC3d.dll`, `UPI.dll` |

The installer ships `meshmixer/models/{bunnyr,dog,elephant,gremlin,plane,sphere}.obj`,
`meshmixer/libraries/{default_brushtex,default_polygons,default_shaders,parts}`,
`meshmixer/printers/printers.xml` plus an XSD, and localized help PDFs
(`hotkeys.pdf`, `printing3dinfo.pdf`).

## 2. Module and binary layout

`meshmixer.exe` statically links the geometry kernel; the separate DLLs are
support code, not the kernel.

* `MC3.dll` / `MC3d.dll` are **Autodesk licensing/telemetry**, not geometry
  **[observed]**: both export exactly the same 70 symbols (`CMLFacade::Initialize`,
  `TrackUserEvent`, `OnCrash`, `CommonFileInput`, UPI install queries) and
  import libcurl, ws2_32, LDAP, MSI. `MC3d.dll` is the *debug* build (links
  `mfc140ud`, `MSVCP140D`, `ucrtbased`).
* `Chronicle.dll` is Autodesk's analytics library; `meshmixer.exe` imports
  `Facade::Waypoints::toolStarted`, `toolFinished`, `documentOpened`,
  `documentSaved` **[observed]**.

The geometry code is compiled into the executable. Three Ghidra headless passes
were run: a focused pass over the 127 functions that reference recovered kernel
strings (`ghidra_decomp2.txt`), a caller pass for 6 key addresses
(`ghidra_key_callers.txt`, 13 functions), and a broad caller pass that
decompiled 15,968 functions for 383 target addresses (`ghidra_callers.txt`).
The kernel uses SSE intrinsics, so most arithmetic shows up as vector
instructions rather than scalar `sqrt`/`atan2` calls; the passes confirm control
flow and call relationships, while the module and string evidence supplies the
algorithm names.

Its source tree survives in
`__FILE__` assert strings: 375 distinct paths under
`E:\workspace\meshmixer-all\label\MeshmixerWin7\Src\`, with this layout
**[observed]**:

```
libgeometry/            mesh, mesh_processing, spatial, parameterization, fabrication, curve, image, base, geometry
libmeshtools/           Operators, EditTools, Brushes, SceneGraph, Core, AnalysisTools, SelectionTools, UVTools, Stamps, Fields, Parts, CreationTools
meshmixer/              libgui, qtui, tools, sg, sys, core, libraries, a3dp, AutoCam, oauth, qtutil
```

Representative translation units (**observed** paths):

* `libgeometry/mesh`: `VFTriangleMesh.cpp`, `GSurface.cpp`, `MeshIO.cpp`,
  `MeshIO_3MF.cpp`, `PatchTopology.cpp`, `UVLayerMesh.cpp`, `IDMap.h`.
* `libgeometry/mesh_processing`: `MeshReducer.cpp`, `MeshRefinement.cpp`,
  `MeshRasterizer.cpp`, `MeshPlaneSlicer.cpp`, `MeshStepSlicer.cpp`,
  `SimpleHoleFiller.cpp`, `LoopStitcher.cpp`, `BoundaryLoopSplit.cpp`,
  `EdgeWelder.cpp`, `ARAPDeformer.cpp`, `LaplacianDeformer.cpp`,
  `Delaunay2D.cpp`, `MeshAttractor.cpp`, `MinDistances.cpp`,
  `MeshProjection.cpp`, `SurfaceAreaSelection.cpp`.
* `libgeometry/spatial`: `IMeshOctree.cpp`, `OctreeFaceDecomposition.cpp`.
* `libgeometry/fabrication`: `SupportForestGenerator.cpp`, `SupportPostGraph.cpp`.
* `libgeometry/curve`: `DiscreteRod.cpp`, `DiscreteRodSimulator.cpp`.
* `libgeometry/image`: `ImplicitPolygonizer.cpp`, `ImagePacker.cpp`,
  `SurfaceUVPatchSampler.cpp`.
* `libgeometry/parameterization`: `PlanarParameterization.cpp`,
  `MeshCurveExpMap.cpp`, `PatchTopologyBuilder.cpp`.
* `libmeshtools/Operators`: `SurfaceRemesher.cpp`, `VariationalRemesher.cpp`,
  `SurfaceReducer.cpp`, `SurfaceOffset.cpp`, `SurfaceExtruder.cpp`,
  `MeshBoolean.cpp`, `HoleFiller.cpp`, `BoundaryBridge.cpp`,
  `BoundaryJoiner.cpp`, `BoundaryStitcher.cpp`, `MeshPlaneCut.cpp`,
  `MeshMirror.cpp`, `MeshThicknessAnalysis.cpp`, `OverhangTracker.cpp`,
  `PrintBedOptimization.cpp`, `SolidPartMaker.cpp`, `PartMaker.cpp`,
  `SplitNonManifoldSurface.cpp`, `CreateInteriorSurface.cpp`,
  `SurfaceUVGenerator.cpp`, `SurfaceUnwrapper.cpp`.
* `meshmixer/tools`: `BrushTool2.cpp`, `SmoothBrushTool.cpp`,
  `SurfaceBrushTool.cpp`, `StampTool.cpp`, `DeformTool.cpp`, `HoleFiller` UI,
  `PrintTool.cpp`, `UnitsTool.cpp`, `TransformManipWidget.cpp`,
  `ConvexDecompTool.cpp`, `ExportVectorGraphicsTool.cpp`.
* `meshmixer/sg`: `Renderer.cpp`, `mmShader.cpp`, `mmShaderManager.cpp`,
  `LiveMeshManager.cpp`, `StoredCommands.cpp`.
* `meshmixer/core`: `VertexBufferManager.cpp`, `mmFrameBufferManager.cpp`,
  `TextureCache.cpp`, `LiveMesh.cpp`.

## 3. UI and feature inventory

The executable carries 128 `<ToolHelp>` documents (`tool_help/*.xml`), of which
44 are individually named, plus 128 `<Title>` / `<ShortDescription>` pairs
**[observed]**. The named tools:

```
AlignTool CloseCracksTool ConvertToPartTool ConvertToSolidTool ConvertToStampTool
DeformTool DropTool DuplicateTool EditPlaneCutTool ExtractTool ExtrudeTool
FaceSelectionTool FaceTransformTool FaceVariationalMoveTool FitPrimitiveTool
FlipNormalsTool GenerateFaceGroupsTool HandleTool InspectorTool JoinTool
MakePartTool MakePatternTool MakeSolidTool MeasuringTool MirrorTool OverhangTool
ReduceTool RemeshTool ReplaceTool SelectPlaneCutTool SmoothBoundaryTool
SmoothingBrushTool SmoothTool SoftTransformTool StabilityTool StampTool
StitchBoundaryTool StrengthTool SurfaceBrushTool TransformTool UnitsTool
VolumeBrushTool
```

Action bar handlers recovered from Qt meta-object strings **[observed]**:
`userActionBar{Meshmix,Import,Select,Sculpt,Stamp,Edits,Analysis,Shaders,
SeparateShells,Export,Print}`, `userEditAction{Mirror,Duplicate,Transform,
CreatePivot,Align,AlignToTarget,PlaneCut,Combine,Union,Intersection,Difference,
WeldCracks,MakeSolid,CreateInteriorSurface,ExtractExteriorSurface,
SplitNonManifoldSurface,MakePattern,Hollow,VariationalRemesh,
GenerateFaceGroups,Unwrap}`, `userAnalysisAction{Inspector,Thickness,Units,
Measure,MeshQuery,Stability,Orientation,PrintBedLayout,Strength,Overhangs,
Slicing,Deviation,Clearance}`.

### Tool parameters (recovered label / internal name pairs)

These come from the compiled Qt meta-object property tables **[observed]** and
define the exact knob set a faithful reimplementation must expose:

* Remesh: `Remesh Mode`, `Remesh Type`, `Relative Density`, `Adaptive Density`,
  `Target Edge Length`, `Linear Subdivision`, `Edge Length`, `Regularity`,
  `Threshold`, `Transition`, `transitionWidthWorld`, `Smooth Group Boundaries`,
  `Preserve Sharp Edges`, `Sharp Threshold`, `Boundary Mode` (Free Boundary /
  Refined Boundary).
* Reduce: `Reduce Target`, `Reduce Type` (Percentage / Triangle Budget /
  Max Deviation), `Uniform`, `Shape Preserving`, `Tri Count`,
  `maxDeviationWorld`, `Preserve Boundaries`, `Preserve Group Boundaries`.
* Make Solid: `Solid Type` (Blocky / Accurate; help text also lists "Fast"),
  `Solid Accuracy`, `Cell Size`, `Mesh Density`, `meshCellSize`,
  `Min Thickness`, `Cull Edges Threshold`, `Close Open Boundaries`,
  `Auto-Repair Result`, `Transfer Groups`, `Offset Distance`, `Smoothing`,
  `Sharp Edge Preserve`, `Color Transfer Mode` (No Colors / Vertex-to-Vertex /
  Material-to-Vertex).
* Hollow: `Holes Per Hollow`, `Hole Radius`, `Hole Taper`.
* Plane Cut: `Cut Type` (Cut (Discard Half) / Slice (Keep Both) / Slice Groups),
  `Fill Type` (No Fill / Minimal Fill / Remeshed Fill / Fixed Fill),
  `Use Intersection Curves`, `Preview Iterations`, `Target Edge Scale`,
  `Merge Border Rings`, `Handle Co-Planarity` (`robustMode`), `Delta`.
* Hole fill: `Fill Type` (Flat Minimal / Flat Remeshed / Smooth MVC),
  `Smoothness`, `Preserve Shape`, `Iterations`, `Border Rings`,
  `Preserve Mesh Boundary`, `Preserve Group Borders`, `Project to Target`,
  `Create New Groups`.
* Deform: `Deformation Type` (Linear / Nonlinear), `Flat Transition` /
  `Stretchy Transition`, `Boundary Continuity` (`Boundaries`, `SoftPosition
  Boundary`, `SoftTangent`), `Refine Mesh`, `Ignore Groups`, `falloffFixed`,
  `Shared Frame`.
* Pattern: `Pattern Type` (Dual Edges, Mesh + Delaunay Edges, Mesh + Delaunay
  Dual Edges, Tiled Tubes, Tiled Spheres, Lattice, Random Primitives (Volume /
  Surface), FaceGroup Borders), `Tiling Mode` (Regular Grid / Hex Grid),
  `Element Dimension`, `Element Spacing`, `Composition` (Subtract / Intersect),
  `Clip To Surface`, `Grid Smoothing`, `Grid Resolution`, `Mesh Resolution`,
  `Gradient` (No / Line / Sphere), `Start Scale`, `End Scale`.
* Supports: preset XML fields `OverhangAngle`, `ContactTolerance`,
  `VerticalOffset`, `LayerHeight`, `SupportMaxAngle`, `SupportDensity`,
  `PostDiameter`, `TipDiameter`, `BaseDiameter`, `AllowTopConnections`,
  `OptimizationRounds`, `TipHeight`, `BaseHeight`, `StrutDensity`,
  `PostSides`, `PolicyType`, `SolidMinOffset`; shipped presets include
  "Replicator 3mm Defaults", "Ultimaker2 (Dizingof's settings)",
  "SLA/DLP Printer", "Autodesk Ember", "Advanced Support".
* Packing: `Packing Mode` (Stacked / Optimized), `Packing Style` (Square /
  Left-to-Right), `Packing Quality` (Fastest / Medium Quality / Max Quality),
  `Packing Origin` (Bed Origin / Rear Left Corner / Centered), `Border Width`,
  `Transformation Mode` (2D Move / 2D Move & Rotate).
* Brush properties: `Strength`, `Spacing`, `Symmetry`, `AlignToStroke`,
  `Lazyness`, `flow`, plus refinement toggles (`Refine`, `AdaptiveReduce`,
  `Reduce`, `NonUniformReduce`). Brush icons enumerate the sculpt ops:
  `drag, draw, draw2, draw3, drawmax, flatten, inflate, pinch, move, spikes,
  paint, attract, meshRefine, meshReduce, meshReduceNonuniform, zipper, blur`.
* Selection: `Expand/Contract Ring`, `Connected`, `Expand to Groups`,
  `Invert Connected`, `Optimize Boundary`, `Create Facegroup`,
  `Clear Facegroup`, paint vs lasso mode.

### Interaction model

From `help_docs/hotkeys.pdf` **[observed]**: Meshmixer and Fusion 360
navigation modes; `Alt`-based tumble/pan/zoom; undo/redo with tool-change
skipping; tool hotkeys (`S` select faces, `T` transform, `Shift+T` soft
transform, `N` align, `I` inspector, `Shift+Y` separate shells, `2` surface
brush, `3` volume brush, `4` stamp, `O` overhangs); brush modifiers
(primary/secondary/invert, symmetry, refinement, adaptive refinement, hold
boundary, preserve groups, attract); selection-based commands (discard, erase &
fill, smooth loop, extrude, fit primitive, reduce, remesh, offset, extract,
optimize boundary).

## 4. Rendering

**[observed]** `meshmixer.exe` imports `OPENGL32` (87 functions) and `GLU32`
(`gluPerspective`, `gluProject`, `gluUnProject`, `gluLookAt`, `gluOrtho2D`).
The imports include `glBegin`, `glEnd`, `glGenLists`/`glCallList`,
`glEnableClientState`/`glDisableClientState`, `glDrawArrays`, `glDrawElements`,
`glGetDoublev`: legacy fixed-function OpenGL 2.x with client-side vertex arrays,
not core-profile OpenGL.

Embedded GLSL strings are 1.20-era **[observed]**:

```glsl
varying vec4 ambientGlobal;
varying vec3 normal;
varying vec4 worldPos;
uniform int enable_mirror_plane;
uniform vec3 mirror_plane_origin;
uniform vec3 mirror_plane_normal;
uniform int cut_plane_mode; // 0 = ignore; 1 = discard; 2 = red
uniform vec4 cut_plane_eqn;
uniform float stamp_radius;
uniform sampler2D texImage;
gl_Position = gl_ModelViewProjectionMatrix * worldPos; // ftransform();
```

Shading is per-pixel Phong with a fixed 1-light rig (`diffuse[1]`,
`lightDir[1]`, `halfVector[1]`), plus mirror-plane, cut-plane (discard or red
highlight), texture and stamp overlays. `mmShaderManager`/`TextureCache`/
`VertexBufferManager`/`mmFrameBufferManager` handle resource management and
offscreen passes (AO and analysis heat maps are computed per vertex:
`MeshVertexAOJob`, `MeshVertexValueSmoothJob`).

## 5. Data model and formats

**[observed]** File dialogs accept `*.obj *.ply *.stl *.amf *.3mf *.off *.mix`
and Meshmixer's native format is `.mix` (autosave name
`autosave_%d_%s_%02d_%02d_%02d.mix`). 3MF is handled by the bundled `lib3mf`.
Part libraries are `.prt` files with `semantic="VERTEX|NORMAL|COLOR"`
bindings; stamps and shaders live as `.png` assets in
`libraries/default_{brushtex,polygons,shaders}`.

Scene graph objects: `MeshSO`, `PivotSO`, `DecalSO`, `Camera`, `Scene`,
`SemanticDB`, with a command/history system (`StoredCommands`,
`*ActivationChangedHistoryNode`, `MaxUndoMemorySize` preference).

### `.mix` container (recovered from a saved scene)

**[observed]** A scene saved by the running 3.5.0 build under Wine was parsed
directly. The file is a sequence of length-prefixed records:

1. `[uint32 LE length][XML]` describing `SceneObjects`, one `MeshSO<n>` record
   per object (Filename, MeshBlockID, Visibility, transforms) and
   `SemanticDB`. The 3.5.0 build writes `MeshSO9`; the 3.0 API sample writes
   `MeshSO11`.
2. `[length][block index]`: block count, block id/size pairs, semantic block id
   and size.
3. `[length][MMGS block]`: `u32 5` + `MMGS\0`, `u32 12` + `GSurf 01.01\0`,
   then a mesh chunk. Two chunk versions exist:
   * `VFMesh 1.3`: six u32 counts/strides (vertices, vertices, faces, faces,
     56, 24), 60-byte vertex records (`u32 56`, vertex id, 3f position, 3f
     normal, u32 vertexCount, u32 0, 4f RGBA, u32 0) and 28-byte face records
     (`u32 24`, face id, three indices, **group id**, `u32 0xFFFFFFFF`).
   * `VFMesh 1.2` (older): four u32 counts (vertices, vertices, faces, faces),
     56-byte vertex records (`u32 vertexId`, 3f position, 3f normal, u32
     vertexCount, u32 0, 4f RGBA, u32 0) and 20-byte face records (face id,
     three indices, **group id**).
   Both end with the constant 194-byte `MeshPolygons 1.0` trailer.
4. `[length][MMSDB block]`: `u32 6` + `MMSDB\0`, `u32 17` +
   `SemanticDB 01.20\0` and a fixed 55-byte body.

A `.mix` written by `mmx_core` for `bunnyr.obj` and `sphere.obj` opens in the
unmodified Meshmixer 3.5.0 under Wine with the correct vertex and triangle
counts, so the writer is byte-compatible with the shipped reader. The reader
also parses the official API sample
(`mm-api/python/examples/sphere.mix`, VFMesh 1.2, 6302 vertices, 12600 faces,
volume 4.18879) and the 3.5.0 scene saved under Wine (VFMesh 1.3). Face groups
are stored as the group id in each face record: a 3.5.0 scene with all faces
tagged group 4 reads back as group 4, and a two-group sphere written by
`mmx_core` displays as two face-group colors in the unmodified 3.5.0 build.
Multi-object scenes are written as one `MeshSO9`/`MMGS` pair per object and
round-trip through mmx_core's reader; the shipped 3.5.0 build was verified on
single-object files (its Import dialog merges appended meshes into one object).

### Official API headers (mm-api)

**[observed]** Autodesk published the remote-scripting API for Meshmixer 3.0 at
<https://github.com/meshmixer/mm-api>. Its `build/` directory contains the
actual internal headers `StoredCommands.h`, `StoredCommands.cpp`,
`BinarySerializer.h` and `LiveMesh.h`, carrying Autodesk's 2016 copyright. This
is source-level documentation, not a leak, and it resolves several points that
strings alone could not:

* `StoredCommands.h` lists every tool accepted by `BeginTool` and its parameter
  names, ranges and enum values. Examples: Reduce exposes
  `goalType=Percentage|TriangleBudget|MaxDeviation` and
  `reduceMetric=Uniform|QuadricError`; Remesh exposes
  `goalType=RelativeDensity|AdaptiveDensity|TargetEdgeLength|LinearSubdivision`,
  `transitionWidth`, `sharpThreshold` and
  `boundaryMode=FreeBoundary|FixedBoundary|RefinedFixedBoundary`; Make Solid
  exposes `solidType=Blocky|Fast|Accurate|FastSharp` plus
  `solidResolution`/`meshResolution`; Hollow exposes `holesPerComponent`;
  Make Pattern lists ten pattern generators (mesh edges, dual edges, Delaunay,
  tubes, spheres, lattice, Poisson 2D/3D, face-group edges, custom).
* The boolean command documents `solutionType=FastApproximate|Precise|
  ExtraPrecise`, `useIntersectionCurves`, `robustMode`, `robustModeDelta`,
  `maxRefineDepth` and `postReduce`. This shows the precise path is a
  mesh-intersection algorithm with boundary resampling, not only voxel CSG.
* `LiveMesh.h` documents `PackedLiveMesh` (version, vertex/triangle counts,
  flags for normals/colors/UVs/groups) and the `rms::VFTriangleMesh` kernel
  class, confirming the kernel namespace and mesh layout.
* The full tool inventory includes tools not yet in mmx: `addTube`,
  `createPivot`, `unwrap`, `generateComplex`, `splitComplex`, `filterComplex`,
  `makePart`, `makeSolidPart`, `makePolygon`, `warp`, `handle`.

Copies and a generated parameter index are kept in `docs/reference/`
(`StoredCommands.h`, `LiveMesh.h`, `BinarySerializer.h`, `API-PARAMETERS.md`).

The same author (Ryan Schmidt, `[RMS]` in the headers) maintains the
open-source `geometry3Sharp` C# library, whose class list overlaps the kernel
almost one-for-one: `MeshBoolean`/`MeshMeshCut`, `MeshStitchLoops`, `MeshICP`,
`MeshPlaneCut`, `MeshIterativeSmooth`, `Reducer`, `Remesher`,
`SimpleHoleFiller`, `MeshLoopClosure`. It is the closest available source-level
reference for the algorithms Meshmixer used. His successor application,
Cotangent2, states it implements "better versions of Meshmixer Tools" and uses
geometry3Sharp for the geometry work.

The executable's RTTI also yields 3,612 class names. They confirm the kernel
namespace and class inventory: `rms::MeshBoolean`, `rms::MeshReducer`,
`rms::SurfaceReducer`, `rms::SurfaceRemesher`, `rms::VariationalRemesher`,
`rms::ARAPDeformer`, `rms::COILSDeformer`, `rms::RotInvCoordDeformer`,
`rms::MeshPlaneCut`, `rms::MeshBoundaryJoin`, `rms::MeshFileReader/Writer`,
`rms::M2SGridImplicit` (mesh-to-solid grid implicit) and
`rms::SupportMesherGridImplicit`. That inventory is consistent with the
module-name evidence and with the geometry3Sharp class list.

Recovering the vtables behind those names (`tools/extract_rtti.py`) attributes
method slots to classes: 2,314 classes and 28,240 slots, of which 913 classes
have at least one method in the Ghidra corpus. `SurfaceRemesher::rms` has 39
slots (8 decompiled, including `0x1409df4b0` and `0x1409e09a0`),
`SurfaceReducer::rms` 39 (8), `BoundaryJoiner::rms` 39 (11),
`M2SGridImplicit` 8 (2), `MeshFileWriter::rms` 3 (1), and the tool layer has
`RemeshTool` 104, `MakeSolidTool` 88, `BooleanTool` 77 and `MakePatternTool`
126 slots. This does not recover method names, but it turns anonymous `FUN_`
addresses into class-attributed methods. See `docs/RTTI.md`.

Autodesk's 2019 help pages go further than the strings: they describe the
internal steps. Make Solid voxelizes at Solid Accuracy and again at Mesh
Density, with Fast reprojecting onto the input, Accurate meshing a signed
distance field, and Sharp Edge Preserve recovering edges like Attract to
Target. Boolean does not cut: it remeshes around the intersection, deletes
triangle strips to create boundary loops, then grows the loops together while
sliding them on the input surfaces, with Search Depth retries at higher density
and Precise/Max Quality/Fast Approximate solution modes. Remesh uses rounds of
split/collapse/flip plus Laplacian smoothing and reprojection, with Regularity,
Transition and boundary modes. Reduce's Uniform mode is shortest-edge-first and
Shape Preserving is quadric-error collapse. Plane Cut fill modes are No Fill,
Minimal (constrained Delaunay), Remeshed and Fixed. Hollow is Make Solid
Accurate with a negative offset. Detailed notes are in
`docs/reference/AUTODESK-HELP-NOTES.md`.

## 6. Algorithms (inferred from module names, parameter names and log strings)

| Capability | Evidence | Inference |
|---|---|---|
| Voxelization | `MeshRasterizer::RasterizeVolume_RayCast`, log `find surface voxels took %f`, `MeshToSolid::GenerateVoxelSolid: m_nTargetGridResolution is %d`; decompiled grid loop indexes `x + nx*(y + ny*z)` and tests sign changes against six neighbours; Autodesk Make Solid help describes voxelizing at Solid Accuracy then a second voxelization at Mesh Density | Ray-cast voxelization into a signed field with target grid resolution, followed by a second grid meshing pass |
| Solid conversion | `ImplicitPolygonizer.cpp`; API `solidType=Blocky|Fast|Accurate|FastSharp`; Autodesk help: Fast meshes voxels then reprojects onto the input, Accurate computes and meshes a signed distance field, Block meshes cubes, Sharp Edge Preserve recovers sharp edges like Attract to Target; Cull Edges drops edges below a fraction of the voxel edge length, Min Thickness adds spheres, open boundaries are filled with Minimal Erase & Fill | Implicit polygonization plus optional reprojection or SDF meshing, with a cell-size-based edge cull |
| Booleans | `MeshBoolean.cpp`, `SimpleBooleanParamAlias`; API `solutionType=FastApproximate|Precise|ExtraPrecise`, `useIntersectionCurves`, `robustMode`, `maxRefineDepth`, `postReduce`; Autodesk help: no cutting, instead remesh around the intersection, delete triangle strips to make boundary loops, then grow the loops together while sliding on the input surfaces (Join-like); Search Depth retries at higher density; Fast Approximate is unconstrained Join-like, Precise solves the intersection curve, Max Quality raises thresholds | Remesh-and-stitch boundary growing, not voxel CSG. The voxel boolean path is Make Pattern, which performs the boolean on a grid and extracts a surface |
| Remeshing | `SurfaceRemesher.cpp`, `VariationalRemesher.cpp`, `MeshRefinement.cpp`, `RefinementConstraint.cpp`; Autodesk Remesh help: rounds of split/collapse/flip interleaved with Laplacian smoothing and reprojection, Regularity controls smoothing, Transition widens the density band, boundary modes Fixed/Free/Refined, Linear Subdivision splits only; geometry3Sharp Remesher cites Botsch & Kobbelt SGP 2004 | Iterative isotropic/adaptive remeshing with edge split/collapse/flip, Laplacian smoothing, projection and constraints |
| Decimation | `MeshReducer.cpp`, `Reduce Type` Percentage/Triangle Budget/Max Deviation, `Shape Preserving`; Autodesk Reduce help: Uniform is shortest-edges-first, Shape Preserving is quadric-error collapse, Max Deviation is checked at vertices only; geometry3Sharp weights vertex quadrics by incident triangle area | QEM edge collapse for Shape Preserving with area-weighted quadrics; shortest-edge-first collapse for Uniform |
| Hole filling | `SimpleHoleFiller.cpp`, `LoopStitcher.cpp`, `BoundaryJoiner/Stitcher/Bridge`; Autodesk Plane Cut help fill types: No Fill, Minimal (constrained Delaunay), Remeshed (remesh the minimal fill), Fixed (clip a fixed triangle pattern); Erase & Fill Minimal/Flat Refined/Smooth MVC | Boundary-loop triangulation with Delaunay, remeshed and fixed-pattern variants |
| Plane cut | `MeshPlaneCut` RTTI, `MeshPlaneSlicer`; API `cutType=PreciseGeometricCut|PreciseGeometricSlice|NearestPointAttach|RefinedICPAttach`, fill types as above; Autodesk help: Cut/Slice/Slice Groups | Exact plane/edge intersection, with optional constrained-Delaunay or remeshed caps |
| Hollow | API `hollowType`, `holesPerComponent`, `holeRadiusWorld`, `holeTaperWorld`; Autodesk help: Make Solid Accurate with a negative offset equal to wall thickness, escape holes added by boolean subtraction | SDF offset shell plus boolean escape holes |
| Deformation | `ARAPDeformer.cpp`, `LaplacianDeformer.cpp`, part attachment help text naming COILS/RotInvCoord deformation; the SIGGRAPH 2010 sketch states composition uses dynamic mesh parameterization (Schmidt et al. 2006) and linear variational deformation (Botsch & Sorkine 2008), plus a topology-independent geometric differential deformation | As-rigid-as-possible and Laplacian solvers, dense linear algebra via ACML |
| Curves | `DiscreteRod.cpp`, `DiscreteRodSimulator.cpp` | Discrete elastic rods for curve handles / hair |
| Spatial index | `IMeshOctree.cpp`, `OctreeFaceDecomposition.cpp`, `VoxelGrid`, `ParticleGrid`, `MeshVertexAOJob` | Octree/grid acceleration for queries, AO and nearest-point work |
| 2D geometry | `Delaunay2D.cpp` with `Wm4::Delaunay2/3` RTTI (Wild Magic) | Delaunay triangulation for patterns and parameterization |
| Parameterization | `PlanarParameterization.cpp`, `MeshCurveExpMap.cpp`, `PatchTopologyBuilder.cpp`, UVLayout | Per-patch planar parameterization and UV packing |
| Supports | `SupportForestGenerator.cpp`, `SupportPostGraph.cpp`, `ComputeOptimizeForcesJob`, OptimizationRounds | Post graph optimization with force-aware rounds |
| Packing | `ObjectPacker_2DRasterizeJob`, `[Pack2D] Packing at pos %d=(%d,%d) with grid index %d (metric %f)` | Rasterized 2D bin packing with a placement metric |
| Slicing | `MeshPlaneSlicer.cpp`, `MeshStepSlicer.cpp`, `MeshStepSlicer_SlicingJob` | Planar contour slicing |
| Analysis | `MeshThicknessAnalysis.cpp`, `OverhangTracker.cpp`, `StabilityTool.cpp`, deviation/clearance tools | Inward ray thickness, overhang angle, COM/support-polygon stability |
| Parallelism | `ProgressTrackingExecutor`, `ToolManParallelJobManager2`, `*_Job`/`*_Job_Data` RTTI | Job-based worker threading with progress monitors |

## 7. What was not established

* Ghidra's full auto-analysis of the 26 MB executable exceeded the 90-minute
  headless budget (118,356 functions recovered, but the reference pass did not
  finish, so `getReferencesTo` returned nothing for the kernel strings). That
  was worked around by locating 158 kernel strings directly in `.rdata`,
  recovering their xref instructions with `objdump`, and running targeted
  headless passes on the saved project: 127 functions touching kernel strings
  (`/data/re/meshmixer/ghidra_decomp2.txt`), 13 callers of 6 key addresses
  (`ghidra_key_callers.txt`), and a broad caller corpus of 15,968 functions for
  383 target addresses (`ghidra_callers.txt`). There is no PDB, so the functions
  are still named `FUN_<address>`; RTTI vtable recovery attributes 913 classes
  to functions in that corpus (see `docs/RTTI.md`), but individual method names
  remain unknown. The source-path and log strings are what tie functions to
  `libgeometry`/`libmeshtools` modules.
* From that decompilation, these behaviours are now **[observed]** rather than
  inferred:
  * `MeshToSolid::GenerateVoxelSolid` rejects a target grid resolution below 1
    (logs `m_nTargetGridResolution is %d` and returns an empty result) and adds
    its float offset to the mesh bounds before rasterizing.
  * `SupportForestGenerator::InitializeGraph` computes its overhang threshold
    from `(90 - angle)` degrees converted to radians, and scales the density
    parameter by 0.01; the terminator bias branches use 0.5 and -0.01.
  * `MeshReducer` asserts are at `MeshReducer.cpp` lines 479 and 487, and the
    reducer uses a hash-keyed edge map (`0x9e3779b9` mix constants) rather than
    a linear scan.
  * The voxel rasterizer path passes mode 5 into the rasterize call.
* Exact numeric constants that are still **[unknown]**: collapse thresholds
  inside the reducer's edge queue, quadric weighting, the support optimization
  objective, and the adaptive-density transition widths. The reimplementation
  uses standard published formulations and documents each one.
* The boolean pipeline is now resolved by Autodesk's own help text: it is a
  remesh-and-stitch algorithm (remesh around the intersection, delete strips,
  grow boundary loops while sliding on the input surfaces), with Search Depth
  retries and Precise/Max Quality/Fast Approximate modes. It is not voxel CSG;
  the voxel boolean path is Make Pattern. The exact density multipliers, merge
  iteration counts and robustness thresholds are still **[unknown]**.
* The `.mix` container is parsed and written for triangle meshes (see section
  5), including per-face group ids. `PivotSO`, `DecalSO`, stamps and shaders are
  not decoded, but `MixIO.rewrite` rebuilds only the mesh blocks and keeps every
  other record byte-for-byte, so those objects survive an edit round-trip. The
  `MeshPolygons 1.0` trailer is constant in all observed scenes, so it carries
  no group table.

## 8. References

* Autodesk Meshmixer 2019 help: Make Solid
  <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-F8C64203-AFB7-449C-A395-2C029A80BB6C.htm>,
  Boolean <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-355503DE-889B-4168-8398-084F9BBD508B.htm>,
  Remesh <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-6EF8ABD4-AB4A-426F-A0C4-DE96FAABF520.htm>,
  Reduce <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-54087649-E962-409E-8565-F646BDA80B33.htm>,
  Hollow <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-4092B330-FF8D-4523-BB43-9453F60BCF4E.htm>,
  Plane Cut <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-C36CDABA-05F7-44B0-9529-C33D9E435220.htm>,
  Make Pattern <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-DFDE32B6-40A7-4237-AE07-45334A464663.htm>;
  summarized in `docs/reference/AUTODESK-HELP-NOTES.md`.
* Autodesk Research Meshmixer project page:
  <https://www.research.autodesk.com/projects/meshmixer/>.
* Meshmixer manual (older, UI-level):
  <https://forums.autodesk.com/autodesk/attachments/autodesk/3ds-max-maya-forum-tr/10043/1/MeshmixerManual.pdf>.
* Autodesk Meshmixer API headers: <https://github.com/meshmixer/mm-api>
  (`build/StoredCommands.h`, `build/LiveMesh.h`, `build/BinarySerializer.h`;
  local copies in `docs/reference/`).
* Autodesk Meshmixer API Python wrapper and examples:
  <https://github.com/meshmixer/mm-api/tree/master/python>
  (`examples/sphere.mix` is the VFMesh 1.2 test vector).
* Ryan Schmidt and Karan Singh, "meshmixer: an interface for rapid mesh
  composition", SIGGRAPH 2010 Talks:
  <https://dl.acm.org/doi/10.1145/1837026.1837034>
  (PDF: <https://papervideos.s3.amazonaws.com/meshmixerSketch10.pdf>).
* geometry3Sharp, open-source geometry library by the Meshmixer author:
  <https://github.com/gradientspace/geometry3Sharp>
  (`MeshBoolean`, `MeshMeshCut`, `MeshStitchLoops`, `MeshICP`, `MeshPlaneCut`,
  `MeshIterativeSmooth`, `Reducer`, `Remesher`, `SimpleHoleFiller`).
* Cotangent2, the Meshmixer successor by the same author:
  <https://www.cotangent.io/> and
  <https://github.com/gradientspace/Cotangent2>.
* Ryan Schmidt's project page for Meshmixer:
  <https://www.rms80.com/projects/meshmixer>.
* Just Solve the File Format Problem, MeshMixer entry:
  <https://fileformats.archiveteam.org/wiki/MeshMixer>.

