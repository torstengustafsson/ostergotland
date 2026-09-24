class_name TreeGenLeafSet
## Parameters for one set of leaves attached to a branch set (Weber & Penn
## "leaf set"). A leaf texture is optional: when `leaf_texture` is null a
## procedural alpha-cutout leaf shape is generated and `leaf_color` tints it.

var set_name := "leaf set"

## -- Leaf density: how many leaves to scatter along each covered branch. ----
var leaf_count := 30
var leaf_count_variation := 0.2 ## +/- random fraction of `leaf_count`

## -- Leaf size and shape -----------------------------------------------------
var leaf_size := 0.3                ## leaf height in world units
var leaf_size_variation := 0.2
var leaf_aspect := 0.7              ## width / height (1 = round, <1 = narrow, >1 = wide)
var leaf_aspect_variation := 0.15
var leaf_shape := 2                 ## 0 = elongated, 1 = heart, 2 = ellipse (procedural texture only)

## -- Distribution along the branch. Leaves only grow from `start_dist` up. --
var start_dist := 0.35              ## fraction of branch length, 0 = from the base
var start_dist_variation := 0.05

## -- Leaf orientation relative to the branch --------------------------------
## NOTE: leaf_angle / leaf_angle_variation are no longer used by the generator;
## leaves point perpendicular to the branch (radially outward) at a random
## azimuth. Kept here only so existing presets still parse; safe to remove.
var leaf_angle := deg_to_rad(35.0)  ## how far the leaf tilts off the branch axis
var leaf_angle_variation := deg_to_rad(10.0)
var leaf_bend := 0.0                ## droop of the leaf tip toward the ground (radians)

## -- Appearance --------------------------------------------------------------
var leaf_texture: Texture2D         ## alpha mask / color map; null uses a procedural shape
var leaf_color := Color(1.0, 1.0, 1.0, 1.0)
var leaf_color_variation := 0.1     ## +/- random tint modulation