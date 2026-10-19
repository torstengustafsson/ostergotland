class_name TreeGenTree extends MeshInstance3D
## A Weber & Penn procedural tree. The trunk is a tapered, subdivided column
## that can have any number of connected TreeGenBranchSet attached; each branch
## set recursively connects to child branch sets and leaf sets. The tree uses a
## bark `Texture2D` for the trunk and branches; leaf sets bring their own.

var random_seed := 0   ## 0 = a different random tree every generation
var max_depth := 8        ## recursion depth guard for the branch set chain

## -- Trunk -------------------------------------------------------------------
var trunk_height := 6.0
var trunk_radius := 0.35
var trunk_segments := 4   ## subdivisions of the trunk (branch set density is relative to this)
var trunk_tip_taper := 0.55 ## radius fraction kept at the trunk top
var bark_rings := 8       ## vertices per cross-section ring on trunk and branches

## Floor on the radius of every branch, in metres. Radii are otherwise a product
## down the chain (parent x fraction x tip_taper), so the deepest twigs taper to
## sub-millimetre and vanish. Flooring both ends of the taper also makes a twig
## never thicker than the branch it grows out of, since every factor is <= 1.
var min_branch_radius := 0.03

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


## Vertices in the generated mesh, summed over every surface: the bark one plus
## one per leaf texture. 0 before the first `regenerate()`. Counts what was
## built, so it follows the forest LOD applied to `bark_rings` and the leaf
## densities rather than the parameters written here.
func vertex_count() -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface_index in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
		total += vertices.size()
	return total
