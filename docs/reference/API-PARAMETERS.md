# Meshmixer tool and parameter reference

Extracted from the official `StoredCommands.h` shipped in the Autodesk
`meshmixer/mm-api` repository (Copyright 2016 Autodesk, Inc.; see
`StoredCommands.h` for the license notice). The header documents the
remote-control command stream; its parameter names and enum values match the
tool parameters in the desktop application.

## Tools accepted by `BeginTool`

- `select`: start face selection tool
- `volumeBrush`: start volume brush tool
- `surfaceBrush`: start surface brush tool
- `stamp`: start stamp tool
- `replace`: Replace tool
- `erase`: Erase/Fill tool
- `discard`: Discard tool
- `reduce`: Reduce tool
- `remesh`: Remesh tool
- `extrude`: Extrude tool
- `extract`: Extract tool
- `offset`: Offset tool
- `handle`: Handle tool
- `bridge`: Bridge tool
- `join`: Join tool
- `weldBoundaries`: Weld Boundaries tool
- `separate`: Separate tool
- `planeCut`: Plane Cut tool (with or without selection)
- `attractToTarget`: Attract tool
- `alignToTarget`: Align to Target tool
- `flipNormals`: Flip Normals tool
- `fitPrimitive`: Fit Primitive tool
- `makePart`: Convert (selection) To Open Part
- `makeSolidPart`: Convert (selection) To Solid Part
- `makePolygon`: Convert (selection) to Stamp polygon
- `smooth`: Smooth tool
- `faceTransform`: Transform tool
- `softTransform`: Soft Transform tool
- `warp`: Warp tool
- `createFaceGroup`: Create new FaceGroup for selection
- `clearFaceGroup`: Clear FaceGroup for selection
- `smoothBoundary`: Smooth Boundary tool
- `mirror`: Mirror tool
- `duplicate`: Duplicate tool
- `transform`: Transform tool
- `align`: Align tool
- `closeCracks`: Close Cracks tool
- `generateFaceGroups`: Generate Face Groups tool
- `makeSolid`: Make Solid tool
- `hollow`: Hollow tool
- `makePattern`: Make pattern tool
- `makeSlices`: Make Slices tool
- `separateShells`: Separate Shells tool
- `addTube`: Add Tube tool
- `createPivot`: Create Pivot tool
- `unwrap`: Unwrap tool
- `generateComplex`: Generate Complex tool
- `splitComplex`: Split Complex tool
- `filterComplex`: Filter Complex tool
- `combine`: Combine tool (multiple selected objects)
- `union`: Boolean Union
- `difference`: Boolean Difference
- `intersection`: Boolean Intersection
- `inspector`: Inspector tool
- `units`: Units/Dimensions tool
- `measure`: Measure tool
- `stability`: Stability analysis tool
- `strength`: Strength analysis tool
- `overhangs`: Overhangs/Support-Generation tool
- `slicing`: Slicing analysis tool
- `thickness`: Thickness analysis tool
- `orientation`: Orientation optimization tool
- `layout`: Print Bed layout/packing tool
- `deviation`: Deviation measurement between two selected meshes
- `clearance`: Clearance measurement between two selected meshes
- `meshQuery`: display/measure various properties of selected mesh
- `exportSVG`: export selected objects as SVG

## Parameters by tool

### `select` - start face selection tool
- `size`: float
- `radiusWorld`: float
- `creaseAngleThreshold`: float
- `brushType`: integer SphereVolume = 0, SphereDisc = 1, SurfaceUV = 2
- `expandMode`: integer GeodesicDistance = 0, LocalCreaseAngleDeviation = 1, ColorSimilarity = 2
- `symmetry`: boolean
- `allowBackFaces`: boolean
- `restrictToExterior`: boolean

### `volumeBrush` - start volume brush tool
- `strength`: float range [0,1]
- `size`: float
- `depth`: float range [-1,1]
- `lazyness`: float range [0,1]
- `refine`: float range [0,1]
- `reduce`: float range [0,1]
- `refineSmooth`: float range [0,1]
- `refineAdaptive`: float range [0,1]
- `attractStrength`: float
- `volumetric`: boolean
- `symmetric`: boolean
- `surfSnap`: boolean
- `continuous`: boolean
- `enableRefinement`: boolean
- `restrictToGroup`: boolean
- `holdBoundary`: boolean
- `preserveGroups`: boolean
- `brushOnTarget`: boolean

### `surfaceBrush` - start surface brush tool
- `restrictToGroup`: boolean
- `holdBoundary`: boolean
- `preserveGroups`: boolean

### `stamp` - start stamp tool
- `snapDimension`: boolean

### `erase` - Erase/Fill tool
- `density`: float
- `smooth`: float
- `scale`: float
- `boundaryRotate`: float
- `replaceType`: integer values: MinimalFill = 0, FlatRefinedMesh = 1, MVCPlanarDeformation = 2
- `createNewGroups`: boolean

### `discard` - Discard tool
_No parameters documented._

### `reduce` - Reduce tool
- `percentage`: float
- `maxDeviation`: float
- `maxDeviationWorld`: float
- `smooth`: float
- `normalThreshold`: float
- `goalType`: integer Percentage = 0, TriangleBudget = 1, MaxDeviation = 2
- `triangleCount`: integer
- `reduceMetric`: integer Uniform = 0, QuadricError = 1
- `preserveGroups`: boolean
- `preserveBoundary`: boolean
- `adaptive`: boolean

### `remesh` - Remesh tool
- `density`: float
- `edgeLength`: float
- `edgeLengthWorld`: float
- `smooth`: float
- `transitionWidth`: float
- `transitionWidthWorld`: float
- `normalThreshold`: float
- `sharpThreshold`: float
- `goalType`: integer
- `iterations`: integer
- `boundaryMode`: integer
- `preserveGroups`: boolean
- `smoothAcrossGroups`: boolean
- `findSharpEdges`: boolean

### `extrude` - Extrude tool
- `offset`: float range [-inf, inf]
- `harden`: float range [0,1]
- `density`: float range [0,1]
- `endType`: integer values: Offset = 0, Flat = 1
- `directionType`: integer values: Normal = 0, Constant = 1, XAxis = 2, YAxis = 3, ZAxis = 4
- `preserveGroups`: boolean

### `extract` - Extract tool
- `offset`: float
- `endType`: integer values: OffsetDistance = 0, PlanarFlat = 1
- `directionType`: integer values: NormalDirection = 0, ConstantDirection = 1, UnitXDirection = 2, UnitYDirection = 3, UnitZDirection = 4

### `offset` - Offset tool
- `offset`: float
- `offsetWorld`: float
- `soften`: float
- `softenWorld`: float
- `connected`: boolean
- `fixedBoundary`: boolean
- `preserveGroups`: boolean

### `handle` - Handle tool
- `smooth`: float
- `refine`: float
- `flip`: boolean

### `bridge` - Bridge tool
- `refine`: float

### `join` - Join tool
_No parameters documented._

### `weldBoundaries` - Weld Boundaries tool
_No parameters documented._

### `separate` - Separate tool
_No parameters documented._

### `planeCut` - Plane Cut tool (with or without selection)
- `cutType`: integer values: PreciseGeometricCut = 0, PreciseGeometricSlice = 1, NearestPointAttach = 2, RefinedICPAttach = 3 (default=0)
- `fillType`: integer values: NoFill = 0, CentroidRefinedFill = 1, DelaunayFill = 2, DelaunayRefinedFill = 3 (default=3)
- `hardEdge`: boolean
- `origin`: vector3f
- `normal`: vector3f
- `rotation`: matrix3f

### `attractToTarget` - Attract tool
- `density`: float
- `smooth`: float
- `offset`: float
- `offsetWorld`: float
- `normalThreshold`: float
- `enableRefinement`: boolean
- `preserveGroups`: boolean
- `preserveBoundary`: boolean
- `findSharpEdges`: boolean

### `alignToTarget`
- `toleranceWorld`: float
- `sourceType`: integer
- `transformMode`: integer
- `maxIterations`: integer

### `flipNormals` - Flip Normals tool
_No parameters documented._

### `fitPrimitive` - Fit Primitive tool
- `primitiveType`: integer
- `singlePrimitive`: boolean
- `createNewObjects`: boolean
- `meshDensity`: integer

### `makePart` - Convert (selection) To Open Part
_No parameters documented._

### `makeSolidPart` - Convert (selection) To Solid Part
_No parameters documented._

### `makePolygon` - Convert (selection) to Stamp polygon
_No parameters documented._

### `smooth` - Smooth tool
- `smooth`: float
- `scale`: float
- `smoothType`: integer Cotan = 0, Uniform = 1, Membrane = 2
- `constraintRings`: integer

### `faceTransform` - Transform tool
- `harden`: float
- `pivotFrameMode`: integer
- `sharedFrame`: boolean
- `origin`: vector3f
- `translation`: vector3f
- `scale`: vector3f
- `rotation`: matrix3f

### `softTransform` - Soft Transform tool
- `falloffDistance`: float
- `falloffDistanceWorld`: float
- `pivotFrameMode`: integer
- `boundaryContinuity`: integer
- `transitionType`: integer
- `sharedFrame`: boolean
- `refineMesh`: boolean
- `holdBoundary`: boolean
- `falloffFixed`: boolean
- `origin`: vector3f
- `translation`: vector3f
- `scale`: vector3f
- `rotation`: matrix3f

### `warp` - Warp tool
_No parameters documented._

### `createFaceGroup` - Create new FaceGroup for selection
_No parameters documented._

### `clearFaceGroup` - Clear FaceGroup for selection
_No parameters documented._

### `smoothBoundary` - Smooth Boundary tool
- `smoothness`: float
- `preserveShape`: float
- `iterations`: integer
- `expandLoops`: integer
- `preserveBoundary`: boolean
- `preserveGroupBorders`: boolean
- `projectToTarget`: boolean
- `createNewGroups`: boolean

### `mirror` - Mirror tool
- `origin`: vector3f
- `normal`: vector3f
- `rotation`: matrix3f

### `duplicate` - Duplicate tool
_No parameters documented._

### `transform` - Transform tool
- `pivotFrameMode`: integer
- `origin`: vector3f
- `originWorld`: vector3f
- `translation`: vector3f
- `translationWorld`: vector3f
- `scale`: vector3f
- `dimensions`: vector3f
- `rotation`: matrix3f
- `enableSnapping`: boolean
- `absoluteSnapping`: boolean
- `snapStepSize`: float
- `initialFrameOrigin`: vector3f
- `initialFrameOrientation`: matrix3f

### `align` - Align tool
- `sourceType`: integer
- `targetType`: integer
- `transformMode`: integer
- `flip`: boolean
- `origin`: vector3f
- `rotation`: matrix3f
- `sourceFrame`: frame3f
- `targetFrame`: frame3f

### `closeCracks` - Close Cracks tool
_No parameters documented._

### `generateFaceGroups` - Generate Face Groups tool
- `angleThreshold`: float
- `mode`: integer OpeningAngle = 0, NormalDeviation = 1
- `smallGroupThreshold`: integer

### `makeSolid` - Make Solid tool
- `solidCellSize`: float
- `meshCellSize`: float
- `offsetDistance`: float
- `offsetDistanceWorld`: float
- `minThickness`: float
- `minThicknessWorld`: float
- `edgeCollapseThresh`: float
- `solidType`: integer Blocky = 0, Fast = 1, Accurate = 2, FastSharp = 3
- `solidResolution`: integer
- `meshResolution`: integer
- `colorTransferMode`: integer NoColorTransfer = 0, AutoColorTransfer = 1, TransferVertexColors = 2, TransferMaterials = 3
- `closeHoles`: boolean
- `autoRepair`: boolean
- `transferFaceGroups`: boolean

### `hollow` - Hollow tool
- `offsetDistance`: float
- `offsetDistanceWorld`: float
- `holeRadiusWorld`: float
- `holeTaperWorld`: float
- `hollowType`: integer
- `solidResolution`: integer
- `meshResolution`: integer
- `holesPerComponent`: integer

### `makePattern` - Make pattern tool
- `gridResolutionScale`: float
- `meshResolutionScale`: float
- `dimension1`: float
- `spacing1`: float
- `offsetDistance`: float
- `offsetDistanceWorld`: float
- `edgeCollapseThresh`: float
- `gradientValue0`: float
- `gradientValue1`: float
- `pattern`: integer
- `tiling`: integer
- `compositionMode`: integer
- `smoothingIters`: integer
- `dimensionGradient`: integer
- `clipToSurface`: boolean
- `gradientPosition0`: vector3f
- `gradientPosition1`: vector3f
- `origin`: vector3f
- `translation`: vector3f
- `rotation`: matrix3f

### `makeSlices` - Make Slices tool
_No parameters documented._

### `separateShells` - Separate Shells tool
_No parameters documented._

### `addTube` - Add Tube tool
- `startRadius`: float
- `startRadiusWorld`: float
- `endRadius`: float
- `endRadiusWorld`: float
- `startTanLenFactor`: float
- `lengthScale`: float
- `collisionRadius`: float
- `collisionRadiusWorld`: float
- `curveType`: integer
- `operationType`: integer
- `directionConstraint`: integer
- `solveIterations`: integer
- `startPosition`: vector3 (read-only, in scene coordinates - use utility command to modify)
- `endPosition`: vector3 (read-only, in scene coordinates - use utility command to modify)

### `createPivot` - Create Pivot tool
- `offset`: float
- `offsetWorld`: float
- `positionMode`: integer
- `frameMode`: integer
- `symmetric`: boolean
- `linkToTarget`: boolean

### `combine` - Combine tool (multiple selected objects)
_No parameters documented._

### `union` - Boolean Union
_No parameters documented._

### `difference` - Boolean Difference
_No parameters documented._

### `intersection` - Boolean Intersection
- `targetLengthScale`: float
- `robustModeDelta`: float
- `operationType`: integer Union = 0, Difference = 1, Intersection = 2
- `solutionType`: integer FastApproximate = 0, Precise = 1, ExtraPrecise = 2
- `maxRefineDepth`: integer
- `previewIterations`: integer
- `mergeRings`: integer
- `preserveGroupBoundaryEdges`: boolean
- `postReduce`: boolean
- `useIntersectionCurves`: boolean
- `robustMode`: boolean

### `inspector` - Inspector tool
- `smallComponentThreshold`: float
- `replaceType`: integer

### `units` - Units/Dimensions tool
- `units`: int Centimeters = 1, Inches = 2, Millimeters = 3, Meters = 4, Feet = 5
- `worldX`: float
- `worldY`: float
- `worldZ`: float
- `activeDimensionWorld`: float
- `activeDimensionTarget`: float
- `averageDeviation`: float
- `maxDeviation`: float

### `measure` - Measure tool
- `snapMode`: integer SnapNone = 0, SnapToVertices = 1, SnapToEdges = 2, SnapToFacegroupBorders = 3
- `dimensionValid`: boolean
- `dimension`: float
- `minDimension`: float
- `maxDimension`: float
- `queryPosition`: vector3f

### `stability` - Stability analysis tool
- `contactTolerance`: float
- `isStable`: boolean
- `volume`: float
- `surfaceArea`: float
- `centerOfMassWorld`: vector3f

### `strength` - Strength analysis tool
- `showSections`: boolean

### `overhangs` - Overhangs/Support-Generation tool
- `overhangPreset`: integer
- `overhangAngleTolerance`: float
- `contactTolerance`: float
- `verticalOffset`: float
- `maxDraftAngle`: float
- `density`: float
- `layerHeight`: float
- `postBaseSize`: float
- `postTopSize`: float
- `postTipSize`: float
- `postTipHeight`: float
- `postDiscSize`: float
- `postDiscHeight`: float
- `strutDensity`: float
- `solidMinOffset`: float
- `postResolution`: integer
- `optimizeRounds`: integer
- `allowTopSupport`: boolean

### `slicing` - Slicing analysis tool
- `sliceHeight`: float
- `minFeatureSize`: float

### `thickness` - Thickness analysis tool
- `minThickness`: float
- `minThicknessWorld`: float
- `minFeatureSize`: float
- `minFeatureSizeWorld`: float
- `coneAngle`: float
- `grazingThresh`: float
- `wallThresh`: float
- `coneSamples`: integer
- `wallsOnly`: boolean
- `bakeVertexColors`: boolean

### `orientation` - Orientation optimization tool
- `overhangAngleDeg`: float
- `strengthWeight`: float
- `supportVolumeWeight`: float
- `supportSurfaceAreaWeight`: float
- `selectedOrientation`: integer
- `origin`: vector3f
- `translation`: vector3f
- `rotation`: matrix3f
- `containInPrintVolume`: boolean

### `layout` - Print Bed layout/packing tool
- `borderWidth`: float
- `transformationType`: integer Translate2D=0, Translate2D_Rotate2D=1
- `packingQuality`: integer Fastest = 0, Medium_Quality = 1, Max_Quality = 2
- `bedOrigin`: integer RearLeftCorner = 0, Centered = 1
- `packMetric`: integer Circular=0, Square=2, Left-to-Right=3

### `deviation` - Deviation measurement between two selected meshes
- `maxDeviation`: float
- `maxDeviationWorld`: float
- `measuredMaxDeviationWorld`: float
- `symmetric`: bool

### `clearance` - Clearance measurement between two selected meshes
- `minClearance`: float
- `minClearanceWorld`: float
- `measuredMinClearanceWorld`: float
- `symmetric`: bool

### `meshQuery`
- `snapMode`: integer
- `colorMode`: integer
- `triAspectRatio`: float
- `triMinAngle`: float
- `triMaxAngle`: float
- `vertexGaussCurvature`: float
- `vertexMeanCurvature`: float
- `colorMinInteriorAngle`: float
- `colorMaxInteriorAngle`: float
- `colorMinCurvature`: float
- `colorMaxCurvature`: float
- `colorInvalidRange`: float
- `vertexID`: integer
- `edgeID`: integer
- `triangleID`: integer
- `groupID`: integer

### `generateComplex`
- `postSmoothAlpha`: float
- `offsetDistance`: float
- `offsetDistanceWorld`: float
- `mode`: integer
- `refineIters`: integer
- `remesh`: boolean
- `projectToFlat`: boolean

### `exportSVG`
- `svgType`: integer
- `boundaryMode`: integer
- `faceFillColorMode`: integer
- `boundaryFillColorMode`: integer
- `includeEdges`: boolean
- `includeFaces`: boolean

### `unwrap`
- `elementMode`: integer UnwrapByComponents = 0, UnwrapByGroups = 1
- `algorithm`: integer AsRigidAsPossible = 0, DiscreteConformal = 1
- `packingMode`: integer Centered = 0, Linear = 1, AutoPack = 2
- `packingWidth`: float
- `packingHeight`: float
- `packingBorder`: float

### `dropPart` - (start with AppendActionCommand_DropPartAtPoint)
- `radius`: float range [0, inf] (IN SCENE COORDINATES!!)
- `radiusWorld`: float
- `angle`: float range [0, 2pi]
- `bend`: float range [0, inf]
- `bulge`: float range [-180,180]
- `offset`: float range [-inf, inf]
- `scale`: float range [0.0001, inf]
- `scaleFalloff`: float range [0.0001, 1]
- `smoothRadius`: float range [0, inf]
- `tweakRaduis`: float range [0.0001, inf]
- `deformType`: integer COILS = 0, RotInvCoord = 1 (default=0)
- `optimize`: boolean
- `flip`: boolean
- `createVolume`: boolean
- `position`: vector3f *** must be point on surface ***

### `dropSolidPart` - (start with AppendActionCommand_DropSolidPartAtPoint)
- `radius`: float
- `radiusWorld`: float
- `angle`: float
- `offset`: float
- `offsetWorld`: float
- `operationType`: integer AppendToMesh = 0, CreateNewObject = 1, BooleanUnion = 2, BooleanSubtract = 3
- `flip`: boolean
- `position`: vector3f
- `initialFrameX`: vector3f
