# Tool and action coverage

This matrix maps every named tool recovered from the shipped Meshmixer 3.5.0
binary to the mmx implementation and its user-facing exposure. Status values:

- **implemented** - kernel and Studio action exist; tests cover the main path.
- **kernel only** - the operator exists in `mmx_core`/CLI but has no Studio UI.
- **partial** - a usable implementation exists, but a documented mode or
  parameter is missing.
- **out of scope** - deliberately not reproduced; the reason is recorded.

Evidence is from `docs/REVERSE-ENGINEERING.md` (tool help XML, Qt meta-object
strings and RTTI), `docs/METHODS.md` and `docs/RTTI.md`.

## Named tools

| Tool | Kernel | Studio | Status | Notes |
|---|---|---|---|---|
| AlignTool | `tools/align.dart` ICP | Align to target | implemented | Rigid ICP; no manual point-pair alignment UI. |
| CloseCracksTool | `repair/bridge.dart` | Stitch cracks | implemented | Nearest-boundary stitching. |
| ConvertToPartTool | `ComplexTools.extract` | Extract | implemented | Extracts selected faces into a new object. |
| ConvertToSolidTool | `ComplexTools.makeSolidPart` | Make Part | implemented | Solidifies the selected region. |
| ConvertToStampTool | `tools/stamp.dart` | Stamp | partial | Procedural height fields; image-to-stamp conversion is not exposed. |
| DeformTool | `tools/deform.dart` | none | kernel only | Soft move/bend; no manipulator UI yet. |
| DropTool | `tools/modify.dart` | Drop to bed | implemented | Places the object on the bed. |
| DuplicateTool | `scene/document.dart` | Duplicate | implemented | Copies the selected object. |
| EditPlaneCutTool | `tools/plane_cut.dart` | Plane Cut | implemented | Cut, fill modes and slice groups; attach modes are partial. |
| ExtractTool | `ComplexTools.extract` | Extract | implemented | Same path as ConvertToPart. |
| ExtrudeTool | `tools/edits.dart` | Extrude | implemented | Selection extrusion with skirt. |
| FaceSelectionTool | `mesh/topology.dart`, selection sets | Select | implemented | Brush selection, expand/contract. |
| FaceTransformTool | `tools/deform.dart` | none | partial | Kernel transforms exist; no dedicated face-transform panel. |
| FaceVariationalMoveTool | `tools/deform.dart` | none | kernel only | Soft move/bend approximation. |
| FitPrimitiveTool | `tools/modify.dart` | Replace with primitive | implemented | Box/cylinder/sphere fitting. |
| FlipNormalsTool | `tools/modify.dart` | Flip normals | implemented | Whole mesh or selection. |
| GenerateFaceGroupsTool | `mesh/topology.dart` | Face groups | implemented | Angle-threshold grouping. |
| HandleTool | none | none | out of scope | Curve/rod handles are not needed by the current workflows. |
| InspectorTool | `repair/inspector.dart` | Inspector | implemented | Reports holes, non-manifold edges and small shells. |
| JoinTool | `ComplexTools.join` | Combine all | implemented | Joins scene objects. |
| MakePartTool | `ComplexTools.extract` | Make Part | implemented | Extract plus optional solidification. |
| MakePatternTool | `tools/modify.dart` | Make pattern | implemented | Grid array; other pattern modes are partial. |
| MakeSolidTool | `solid/solidifier.dart` | Make Solid | implemented | Blocky/fast/accurate modes and offsets. |
| MeasuringTool | `tools/modify.dart` | Measure | implemented | Dimensions, area, volume, shells. |
| MirrorTool | `tools/edits.dart` | Mirror | implemented | Seam welding. |
| OverhangTool | `analysis/analysis.dart` | Analysis overlay | implemented | Angle-based heat map. |
| ReduceTool | `remesh/decimate.dart` | Reduce | implemented | Percentage, uniform and max-deviation modes; triangle budget is partial. |
| RemeshTool | `remesh/isotropic.dart` | Remesh | implemented | Isotropic, adaptive, group-aware; transition widths are approximated. |
| ReplaceTool | `tools/modify.dart` | Replace with primitive | implemented | Fit primitive and replace. |
| SelectPlaneCutTool | `tools/plane_cut.dart` | Plane Cut | partial | Selection-limited cut is not exposed in the panel. |
| SmoothBoundaryTool | `repair/holes.dart` | none | partial | Hole-fill relaxation exists; no standalone boundary smooth action. |
| SmoothingBrushTool | `tools/sculpt.dart` | Sculpt (smooth) | implemented | Taubin-style brush. |
| SmoothTool | `tools/modify.dart` | Smooth | implemented | Whole-mesh Taubin smoothing. |
| SoftTransformTool | `tools/deform.dart` | none | kernel only | Soft move/bend. |
| StabilityTool | `analysis/analysis.dart` | Analysis overlay | implemented | COM, support polygon and tip angle. |
| StampTool | `tools/stamp.dart` | Stamp | partial | Analytic height fields; image stamps are not decoded. |
| StitchBoundaryTool | `repair/bridge.dart` | Stitch cracks | implemented | Boundary-loop bridge/stitch. |
| StrengthTool | none | none | out of scope | Material-strength simulation is not part of the core workflow. |
| SurfaceBrushTool | `tools/sculpt.dart` | Sculpt | implemented | Draw/inflate/flatten/pinch/crease/twist/move. |
| TransformTool | `scene/document.dart` transform | none | partial | Object transforms exist; no on-canvas manipulator. |
| UnitsTool | none | none | out of scope | mmx is unit-agnostic; import/export preserves numeric units. |
| VolumeBrushTool | `tools/sculpt.dart` | Sculpt | partial | Volume-like inflate/draw; no separate volume brush UI. |

## Recovered action handlers

| Action | Kernel | Studio | Status |
|---|---|---|---|
| Meshmix | `ComplexTools`/primitives | none | partial (library browser not reproduced) |
| Import | `io/*` | Import | implemented |
| Select | selection sets | Select | implemented |
| Sculpt | `tools/sculpt.dart` | Sculpt | implemented |
| Stamp | `tools/stamp.dart` | Stamp | partial |
| Edits | `tools/*` | Modify | implemented |
| Analysis | `analysis/*` | Analysis | implemented |
| Shaders | `render/rasterizer.dart` | viewport | partial (one software shader) |
| SeparateShells | `tools/edits.dart` | Separate shells | implemented |
| Export | `io/*` | Export | implemented |
| Print | `fab/*` | Print | implemented |
| Mirror | `tools/edits.dart` | Mirror | implemented |
| Duplicate | document | Duplicate | implemented |
| Transform | document transform | none | partial |
| CreatePivot | `tools/pivot.dart` | Pivot | implemented (stored; no viewport gizmo) |
| Align / AlignToTarget | `tools/align.dart` | Align to target | implemented |
| PlaneCut | `tools/plane_cut.dart` | Plane Cut | implemented |
| Combine | `ComplexTools.join` | Combine all | implemented |
| Union / Intersection / Difference | `solid/mesh_boolean.dart` | none | kernel only |
| WeldCracks | `repair/bridge.dart` | Stitch cracks | implemented |
| MakeSolid | `solid/solidifier.dart` | Make Solid | implemented |
| CreateInteriorSurface | `solid/solidifier.dart` | Hollow | partial |
| ExtractExteriorSurface | `ComplexTools.extract` | Extract | partial |
| SplitNonManifoldSurface | `repair/inspector.dart` | Auto repair | implemented |
| MakePattern | `tools/modify.dart` | Make pattern | implemented |
| Hollow | `solid/solidifier.dart` | Hollow | implemented |
| VariationalRemesh | `remesh/isotropic.dart` | Remesh (group-aware) | implemented |

## Highest-value gaps

1. Boolean UI (union/intersection/difference) and the remaining boolean modes.
2. A transform/pivot manipulator and viewport gizmo.
3. Image stamps and the stamp/texture semantics.
4. UV storage and export, or an explicit "preview only" label for Unwrap.
5. Selection-limited plane cuts and the remaining plane-cut attach modes.
6. Face transform / variational move UI.
