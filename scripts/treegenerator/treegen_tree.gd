class_name TreeGenTree extends MeshInstance3D
## A Weber & Penn procedural tree. The trunk is a tapered, subdivided column
## that can have any number of connected TreeGenBranchSet attached; each branch
## set recursively connects to child branch sets and leaf sets. The tree uses a
## bark `Texture2D` for the trunk and branches; leaf sets bring their own.

var seed := 0             ## 0 = a different random tree every generation
var max_depth := 8        ## recursion depth guard for the branch set chain

## -- Trunk -------------------------------------------------------------------
var trunk_height := 6.0
var trunk_radius := 0.35
var trunk_segments := 4   ## subdivisions of the trunk (branch set density is relative to this)
var trunk_tip_taper := 0.55 ## radius fraction kept at the trunk top
var bark_rings := 8       ## vertices per cross-section ring on trunk and branches

## -- Bark appearance ---------------------------------------------------------
var bark_texture: Texture2D
var bark_color := Color(0.4, 0.27, 0.16) ## used when `bark_texture` is null

## -- Connected structure -----------------------------------------------------
var branch_sets: Array[TreeGenBranchSet] = []

## The last generated skeleton (TreeGenSkeleton.BranchNode). Left untyped so
## scripts outside this file can read it (inner-class type hints don't resolve
## across scripts reliably in GDScript). Named `tree_skeleton` because
## MeshInstance3D already owns a native `skeleton` property.
var tree_skeleton = null
var _configured := false


static func create() -> TreeGenTree:
	return TreeGenTree.new()


func _ready() -> void:
	if not _configured:
		regenerate()


## Regenerates the skeleton and mesh from the current parameters.
func regenerate() -> void:
	tree_skeleton = TreeGenGenerator.generate_skeleton(self)
	mesh = TreeGenMesher.build_mesh(tree_skeleton, self)
	_configured = true