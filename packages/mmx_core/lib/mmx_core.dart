/// mmx_core — a cross-platform triangle mesh kernel.
///
/// Reimplements the geometry stack observed in Autodesk Meshmixer 3.5.0
/// (libgeometry + libmeshtools) as portable Dart: topology, spatial indices,
/// repair, remeshing, decimation, implicit solid conversion, fabrication
/// analysis, support generation, packing, slicing and brush sculpting.
library mmx_core;

export 'src/analysis/analysis.dart';
export 'src/fab/packing.dart';
export 'src/fab/slicer.dart';
export 'src/fab/supports.dart';
export 'src/geom/bbox.dart';
export 'src/io/mesh_io.dart';
export 'src/io/mix.dart';
export 'src/io/obj.dart';
export 'src/io/ply.dart';
export 'src/io/stl.dart';
export 'src/io/threemf.dart';
export 'src/io/zip.dart';
export 'src/mesh/topology.dart';
export 'src/mesh/tri_mesh.dart';
export 'src/repair/bridge.dart';
export 'src/repair/holes.dart';
export 'src/repair/inspector.dart';
export 'src/repair/weld.dart';
export 'src/render/camera.dart';
export 'src/render/png.dart';
export 'src/render/rasterizer.dart';
export 'src/remesh/decimate.dart';
export 'src/remesh/isotropic.dart';
export 'src/scene/document.dart';
export 'src/solid/solidifier.dart';
export 'src/solid/mesh_boolean.dart';
export 'src/solid/surface_nets.dart';
export 'src/solid/voxel.dart';
export 'src/spatial/bvh.dart';
export 'src/tools/align.dart';
export 'src/tools/edits.dart';
export 'src/tools/modify.dart';
export 'src/tools/plane_cut.dart';
export 'src/tools/sculpt.dart';
export 'src/tools/stamp.dart';
