# Autodesk help notes (algorithm-relevant)

These notes summarize the official Meshmixer 2019 help pages that describe how
the tools work internally. They are the strongest public source for the
algorithms, because the help text was written by the Meshmixer team and names
the actual processing steps. URLs are given per tool.

## Make Solid

Source: <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-F8C64203-AFB7-449C-A395-2C029A80BB6C.htm>

- Voxelizes the input at the **Solid Accuracy** sampling rate, then uses a
  **second voxelization at the Mesh Density rate** to mesh the first voxel
  approximation. Both are editable as cell sizes for repeatable results.
- **Fast**: meshes the voxel approximation, then reprojects the vertices back
  onto the input surface.
- **Accurate**: computes a signed distance field approximating the input and
  meshes that field; the smoothing is done by a linear filter.
- **Block**: meshes the voxel cubes directly; can contain non-manifold
  junctions.
- **Sharp Edge Preserve**: Fast mode plus a sharp-edge recovery step similar to
  the multi-step Attract to Target workflow.
- **Offset Distance** (Accurate only): offsets the signed distance field,
  positive for outer shells, negative for inner shells; accuracy on the order
  of one cell width.
- **Min Thickness** (Accurate only): thickens thin regions by adding spheres
  with the requested diameter, which can produce bumpy artifacts.
- **Cull Edges Threshold**: discards edges shorter than a fraction of the voxel
  edge length; 100 means 25% of the edge length.
- **Close Open Boundaries**: fills holes first with the Minimal mode of
  Edit > Erase & Fill.
- Color transfer supports vertex colors and bakes UV textures to vertex colors.

## Hollow

Source: <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-4092B330-FF8D-4523-BB43-9453F60BCF4E.htm>

- Built on the same infrastructure as Make Solid: the internal shell is Make
  Solid in Accurate mode with a **negative offset** equal to the wall
  thickness.
- Escape holes are added by boolean subtraction of cylinder/sphere geometry
  from the hollowed result.
- Holes per hollow cavity can be generated automatically.

## Boolean

Source: <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-355503DE-889B-4168-8398-084F9BBD508B.htm>

- Meshmixer does **not cut** the meshes. It first remeshes around the
  intersecting region, then deletes strips of triangles from each object to
  create clean boundary loops, then grows the open boundaries together until
  they match, sliding the boundaries on the underlying input surfaces. The
  growing step is nearly identical to Edit > Join.
- **Search Depth** controls remesh-and-retry iterations when loop matching
  fails; each retry uses a higher density.
- **Solution Mode**: **Precise** solves for the precise intersection curve;
  **Max Quality** raises internal thresholds (density, merge iterations);
  **Fast Approximate** does not constrain the merge loops to the input
  surfaces and is essentially the Join tool inside the boolean framework.
- Preserve Group Borders improves sharp-edge results, because remeshing is the
  weak point.

## Plane Cut

Source: <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-C36CDABA-05F7-44B0-9529-C33D9E435220.htm>

- Cut types: **Cut**, **Slice** (keeps both sides, still one object), and
  **Slice Groups** (assigns face groups instead of changing shape).
- Fill types: **No Fill**, **Minimal Fill** (constrained Delaunay
  triangulation), **Remeshed Fill** (remeshes the minimal fill, density
  inferred from the boundary), **Fixed Fill** (clips a fixed triangle pattern
  against the hole).
- Cutting exactly through a vertex or edge can make the fill fail; remedies are
  to fill later or remesh around the cut.

## Make Pattern

Source: <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-DFDE32B6-40A7-4237-AE07-45334A464663.htm>

- Operates on a grid representation: constructs a voxel version of the object
  and of the chosen primitives, performs the boolean on the grid, then extracts
  a surface mesh.
- Pattern types: mesh edges, dual edges, mesh + Delaunay edges, mesh + Delaunay
  dual edges, tiled tubes, tiled spheres, lattice, random spheres in volume,
  random spheres on the surface, face-group borders.
- Tiling: regular grid or hex grid. Composition: subtract or intersect. Clip to
  Surface flattens the result against the input. Grid smoothing erodes the
  primitives.

## Remesh

Source: <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-6EF8ABD4-AB4A-426F-A0C4-DE96FAABF520.htm>

- Iterative remeshing with rounds of **edge splits, collapses, and flips**,
  interleaved with smoothing where each vertex moves toward the center of its
  neighborhood, then reprojection onto the input surface.
- **Regularity** controls the amount of smoothing (higher means more equilateral
  triangles and more shape change).
- Modes: **Relative Density**, **Target Edge Length**, **Adaptive Density**
  (non-uniform edge lengths to preserve detail; the threshold maps to an angle
  constraint), and **Linear Subdivision** (splits edges only, preserving the
  surface exactly).
- **Transition** widens the band over which density blends from the selection
  border to the target.
- **Preserve Group Borders**, **Smooth Group Boundaries**, **Preserve Sharp
  Edges** (opening-angle threshold), and boundary modes **Fixed**, **Free**,
  **Refined** (splits but does not collapse/smooth).
- geometry3Sharp's `Remesher`, written by the same author, is described as an
  implementation of Botsch and Kobbelt, "A Remeshing Approach to Multiresolution
  Modeling", SGP 2004, and uses the same split/collapse/flip plus Laplacian
  smoothing and projection structure.

## Reduce

Source: <https://help.autodesk.com/cloudhelp/2019/ENU/MSHMXR/files/GUID-54087649-E962-409E-8565-F646BDA80B33.htm>

- Targets: **Percentage**, **Triangle Budget**, **Max Deviation** (deviation
  checked at vertices only).
- Types: **Uniform** uses a shortest-edges-first criterion to make regularly
  shaped triangles; **Shape Preserving** incrementally collapses edges with the
  smallest effect on the overall shape (quadric error).
- Preserve Boundaries and Preserve Group Boundaries constrain boundary loops;
  unchecking boundaries on a sub-selection creates holes.

## Other notes

- The API headers (`StoredCommands.h`) document the parameter names and enum
  values for all of these tools; see `API-PARAMETERS.md`.
- The Autodesk Research project page is thin:
  <https://www.research.autodesk.com/projects/meshmixer/>. The SIGGRAPH 2010
  sketch and the help pages carry the algorithm detail.
