# Method-name recovery

Meshmixer ships without a PDB. The executable does retain MSVC RTTI and
`__FUNCTION__` strings of the form `Class::Method`, which is enough to name the
methods that log or assert their own name. This document records the recovery
process and what it covers.

## Process

1. Extract printable runs from `.rdata`, `.data` and `.text`.
2. Match `Class::Method` and collect every occurrence (537 runs, 198 unique
   names).
3. Parse the `.pdata` exception directory to map an instruction address to its
   function start.
4. Disassemble `.text` with Capstone, find RIP-relative operands whose target
   falls inside one of those string runs, and attribute the name to the
   containing function.
5. Parse RTTI Complete Object Locators, vtables and class hierarchies to attach
   names to vtable slots and propagate base-class slot names.
6. Apply the names to the Ghidra project (`ApplyNames.java`) and export the
   result (`ExportNames.java`).

Scripts are in `/data/re/meshmixer/ghidra_scripts/`; the generated tables are
`method_names.csv` (173 functions) and `slot_names.txt`.

## Result

**[observed]** 173 functions renamed with 148 kernel method names. The Ghidra
project now contains 118,144 functions, of which 80,300 have names (Qt imports,
demangled C++ runtime symbols and the recovered kernel names).

Representative recovered methods:

| Class | Methods |
|---|---|
| `MeshBoolean` | `Validate`, `ValidateIntersection`, `Validate_CompleteFastPreview`, `InitializeOperation`, `UpdateRefinement`, `RemoveContainedTriangles`, `FindJoinLoopPairs`, `JoinSurfaces` |
| `MeshBoundaryJoin` | `ComputeResult`, `JoinSurfaces`, `Validate` |
| `MeshBoundaryMerge` | `DoRefineStep` |
| `MeshPlaneCut` | `ComputeResult`, `DoAttach`, `GetChange`, `Validate` |
| `MeshReducer` | `ReduceToMinEdgeLength` |
| `MeshToSolid` | `GenerateVoxelSolid` |
| `MeshRasterizer` | `RasterizeVolume_RayCast`, `RasterizeVolume_TriangleBoxes`, `RaycastSolidRasterize` |
| `SurfaceRemesher` | `ApplyEdit` |
| `SurfaceReducer` | `ApplyEdit` |
| `SurfaceReplacer` | `ApplyEdit` |
| `SurfaceOffset` | `FinalizeEdit` |
| `BoundaryJoiner` | `InitializeEditROI` |
| `MultiComponentMeshEdit` | `RecomputeROI` |
| `AttractToTarget` | `ApplyEdit`, `SolveAttract`, `SolveAttract_V2` |
| `HoleFiller` | `FindFillBoundaryCorrespondence`, `MakeFillMesh_CircleUV`, `MakeFillMesh_ParamGen`, `MakeFillMesh_PlanarGen`, `MakeFillMesh_PlanarParamGen`, `ParamAndOpt`, `SetCutRegion` |
| `SupportForestGenerator` | `Generate`, `OptimizateSupportGraph2` |
| `SupportMesher` | `GenerateSolid` |
| `Delaunay2D` / `Delaunay2` | `Compute`, `ExtractMesh` |
| `BoundaryEmbedder` | `EmbedExact` |
| `MeshRefinement` | `StepDebugCheck` |
| `MeshUtils` | `CollapseSlivers`, `FindROIBoundaryLoops`, `GetBoundaryLoopMaps`, `GetSubMesh`, `MergeVertices` |
| `MeshDefectTracker` | `FindDefects`, `TryAutoRepairAll` |
| `MeshThicknessAnalysis` | `FindDefects`, `TryAutoRepairAll` |
| `MakePattern` | `GeneratePattern_GridType`, `Validate`, `initialize_grid_from_graph` |
| `PatchTopologyBuilder` | `RebuildAll`, `UpdateWithinBounds_Edges` |
| `PlanarParam` / `PlanarParameterization` | `ARAP`, `Parameterize_OneRing`, `check_for_nan_inf` |

## Limits

* The 198 unique `Class::Method` strings are the complete set of such strings in
  the binary. Methods that never log or assert their name remain `FUN_<addr>`.
* RTTI gives class names, vtable ownership and base classes, but not method
  names. Only 59 vtable slots have a string-derived name; base-class
  propagation extends that to the shared slots but cannot invent names.
* No public PDB was found: Autodesk's symbol server
  (`https://symbols.autodesk.com/`) returns 404 for
  `meshmixer.pdb/6943C40F11DA44558EBE127899A87FE31/meshmixer.pdb`, and the NSIS
  installer contains only `meshmixer.exe`.
* The remaining names can be inferred from the open-source relatives below, but
  those are inference, not exact symbol names.

## Open-source relatives and what they contribute

* **libgeometry** (Ryan Schmidt, 2008, source zip at
  `http://graphicscode.s3.amazonaws.com/libgeometry.zip`): the older C++ mesh
  library. It contains `IMesh`, `VFTriangleMesh`, `MeshIO`, `MeshPolygons`,
  `VFMeshMask` and `VFMeshMerge`. Its method names match the core mesh classes
  but the interfaces changed before Meshmixer 3.5.
* **geometry3cpp** (`gradientspace/geometry3cpp`): an in-progress C++ port of
  geometry3Sharp. It ports `DMesh3`, `DMeshAABBTree3`, `Remesher`, `OBJReader`
  and `OBJWriter`; `Remesher.h` has the Botsch-Kobbelt pass structure and the
  `0.66/1.33` edge-length bounds.
* **geometry3Sharp** (`gradientspace/geometry3Sharp`): the open-source C#
  library by the same author. It provides the algorithm reference for
  `MeshBoolean`, `MeshMeshCut`, `MeshStitchLoops`, `MeshPlaneCut`, `Reducer`,
  `Remesher` and `SimpleHoleFiller`.
* **Cotangent2** (`gradientspace/Cotangent2`): the UE5 successor; its tool layer
  (`GSMeshBooleanTool`, `GSRemeshMeshTool`, `GSMakeSolidTool`) documents the
  modern UI parameter mapping, but the geometry kernel is UE5 DynamicMesh, not
  the Meshmixer `rms` classes.
* **mm-api** (`meshmixer/mm-api`): API headers and remote-control wrappers
  (`LiveMesh.h`, `StoredCommands.h`, `BinarySerializer.h`); no kernel source.

## Reproduce

```
python3 tools/extract_rtti.py /data/re/meshmixer/extract/meshmixer.exe /data/re/meshmixer/rtti
# string/xref extraction: see /data/re/meshmixer/string_xref_methods_full.json
/opt/ghidra_12.1.4_PUBLIC/support/analyzeHeadless \
  /data/re/meshmixer/ghidraproj mmxproj -process -noanalysis \
  -scriptPath /data/re/meshmixer/ghidra_scripts -postScript ApplyNames.java
```
