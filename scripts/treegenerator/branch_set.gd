class_name TreeGenBranchSet
## Parameters for one Weber & Penn "branch set": a level of branches grown from
## a parent (the trunk or another branch). A branch set can recursively connect
## to child branch sets and to one or more leaf sets.

var set_name := "branch set"

## -- Nested structure --------------------------------------------------------
var child_branch_sets: Array[TreeGenBranchSet] = []
var leaf_sets: Array[TreeGenLeafSet] = []

## -- Branch size (magnitudes are relative to the parent) --------------------
var branch_length := 0.4          ## branch length, fraction of the parent's length
var branch_length_variation := 0.1
var branch_radius_fraction := 0.35 ## branch base radius, fraction of the parent radius at the attach point
var branch_tip_taper := 0.4       ## radius kept at the branch tip (1 = no taper, 0.3 = thin twig)

## -- Branch angles (radians) -------------------------------------------------
var branch_angle := deg_to_rad(38.0)  ## deviation of the branch from the parent's growth direction
var branch_angle_variation := deg_to_rad(8.0)
var down_angle := 0.0             ## if > 0, the branch is pulled toward hanging down; 0 = deviation measured from parent axis
var down_angle_variation := deg_to_rad(0.0)
var rotate := 0.0                 ## base rotation of the branches around the parent
var rotate_variation := deg_to_rad(12.0)

## -- Growth along the branch length -----------------------------------------
var curve := 0.0                  ## turns the branch toward vertical over its length (negative = droops)
var curve_variation := 0.0
var curve_back := 0.0             ## fraction of the branch near the tip that re-straightens toward its base direction
var spread := 0.0                 ## splays the branch outward toward horizontal along its length
var spread_variation := 0.0

## -- Distribution along the parent -------------------------------------------
var density := 2.0                ## branches spawned per parent segment
var density_variation := 0.15     ## +/- random fraction of `density` per tree, so branch counts (and silhouettes) differ between trees
var max_branches := 0             ## 0 = no cap; otherwise a hard limit on stems for this set
var start_offset := 0.15          ## fraction of the parent length below which no branches grow
var attach_jitter := 0.03         ## random position wobble for each attach point
var length_taper := 1.0           ## each attach point higher up the parent gets length * length_taper^fraction
var angle_taper := 1.0            ## same for the deviation angle (lower = more upright near the top)

## -- Structure ----------------------------------------------------------------
var segments := 3                 ## subdivisions along each branch (meshing resolution + child branch spacing)
var max_child_depth := 6          ## recursion depth guard for `child_branch_sets`