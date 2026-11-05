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
     (`u32 24`, face id, three indices, u32 0, u32 0xFFFFFFFF).
   * `VFMesh 1.2` (older): four u32 counts (vertices, vertices, faces, faces),
     56-byte vertex records (`u32 vertexId`, 3f position, 3f normal, u32
     vertexCount, u32 0, 4f RGBA, u32 0) and 20-byte face records (face id,
     three indices, u32 0).
   Both end with the constant 194-byte `MeshPolygons 1.0` trailer.
4. `[length][MMSDB block]`: `u32 6` + `MMSDB\0`, `u32 17` +
   `SemanticDB 01.20\0` and a fixed 55-byte body.

A `.mix` written by `mmx_core` for `bunnyr.obj` and `sphere.obj` opens in the
unmodified Meshmixer 3.5.0 under Wine with the correct vertex and triangle
counts, so the writer is byte-compatible with the shipped reader. The reader
also parses the official API sample
(`mm-api/python/examples/sphere.mix`, VFMesh 1.2, 6302 vertices, 12600 faces,
volume 4.18879) and the 3.5.0 scene saved under Wine (VFMesh 1.3). Multi-object
scenes are written as one `MeshSO9`/`MMGS` pair per object and round-trip through
mmx_core's reader; the shipped 3.5.0 build was verified on single-object files
(its Import dialog merges appended meshes into one object).

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

## 6. Algorithms (inferred from module names, parameter names and log strings)

| Capability | Evidence | Inference |
|---|---|---|
| Voxelization | `MeshRasterizer::RasterizeVolume_RayCast`, log `find surface voxels took %f`, `MeshToSolid::GenerateVoxelSolid: m_nTargetGridResolution is %d`; decompiled grid loop indexes `x + nx*(y + ny*z)` and tests sign changes against six neighbours | Ray-cast voxelization into a signed field with target grid resolution |
| Solid conversion | `ImplicitPolygonizer.cpp`, `Make Solid` modes Blocky/Fast/Accurate, offset, min thickness, auto-repair | Implicit surface polygonization of the voxel field |
| Booleans | `MeshBoolean.cpp`, `SimpleBooleanParamAlias`, union/intersection/difference actions; API exposes `solutionType=FastApproximate|Precise|ExtraPrecise`, `useIntersectionCurves`, `robustMode`, `maxRefineDepth`, `postReduce` | FastApproximate is voxel/implicit CSG; Precise/ExtraPrecise are mesh-intersection algorithms with boundary resampling and refinement |
| Remeshing | `SurfaceRemesher.cpp`, `VariationalRemesher.cpp`, `MeshRefinement.cpp`, `RefinementConstraint.cpp`, params Target Edge Length/Regularity/Adaptive Density/Transition | Isotropic + adaptive remeshing with edge split/collapse/flip and density transition |
| Decimation | `MeshReducer.cpp`, `Reduce Type` Percentage/Triangle Budget/Max Deviation, `Shape Preserving` | Quadric-error edge collapse with boundary constraints |
| Hole filling | `SimpleHoleFiller.cpp`, `LoopStitcher.cpp`, `BoundaryJoiner/Stitcher/Bridge`, fill types Flat Minimal/Flat Remeshed/Smooth MVC | Boundary-loop triangulation with relaxation variants |
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
  are still named `FUN_<address>`; the source-path and log strings are what tie
  them to `libgeometry`/`libmeshtools` modules.
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
* The boolean pipeline is now partly resolved: the API header documents
  `FastApproximate`, `Precise` and `ExtraPrecise` solution types with
  `useIntersectionCurves`, `robustMode`, `maxRefineDepth` and `postReduce`.
  That makes the precise path a mesh-intersection algorithm rather than pure
  voxel CSG; the exact refinement thresholds and robustness constants are still
  **[unknown]**.
* The `.mix` container is parsed and written for triangle meshes (see section
  5). What remains unparsed inside it: `PivotSO`, `DecalSO`, stamps, shaders,
  and the per-face polygon-group table in the `MeshPolygons 1.0` trailer
  (mmx writes the constant single-group trailer Meshmixer itself emits).

## 8. References

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

