class_name TreeGenPresetsCommon
extends RefCounted

## What the two ages of a tree have in common: the bark and leaf textures the
## species are drawn with, and the helper that starts a tree off.
##
## The trees themselves live next door -- TreeGenPresetsAdult has the grown
## ones and TreeGenPresetsYoung the saplings -- and both extend this, so a
## species is written once for its textures while each age keeps its own
## branches.

## -- Bark ---------------------------------------------------------------------

static var BARK_TEXTURE_OAK: Texture2D = load("res://assets/textures/bark/Bark001_1K-JPG_Color.jpg")
static var BARK_TEXTURE_SPRUCE: Texture2D = load("res://assets/textures/bark/Bark008_1K-JPG_Color.jpg")
static var BARK_TEXTURE_MAPLE: Texture2D = load("res://assets/textures/bark/Bark005_1K-JPG_Color.jpg")
static var BARK_TEXTURE_ASPEN: Texture2D = load("res://assets/textures/bark/Bark009_1K-JPG_Color.jpg")
static var BARK_TEXTURE_BIRCH: Texture2D = load("res://assets/textures/bark/Bark007_1K-JPG_Color.jpg")
static var BARK_TEXTURE_PINE: Texture2D = load("res://assets/textures/bark/Bark004_1K-JPG_Color.jpg")

## -- Leaves -------------------------------------------------------------------

static var LEAF_TEXTURE_OAK: Texture2D = load("res://assets/textures/leaves/leaf-oak.png")
static var LEAF_TEXTURE_SPRUCE: Texture2D = load("res://assets/textures/leaves/leaf-spruce-three.png")
static var LEAF_TEXTURE_MAPLE: Texture2D = load("res://assets/textures/leaves/leaf-maple.png")
static var LEAF_TEXTURE_ASPEN: Texture2D = load("res://assets/textures/leaves/leaf-aspen.png")
static var LEAF_TEXTURE_BIRCH: Texture2D = load("res://assets/textures/leaves/leaf-birch.png")
static var LEAF_TEXTURE_PINE: Texture2D = load("res://assets/textures/leaves/leaf-pine.png")


## A tree with a trunk and a bark, and nothing else on it yet.
static func base_tree(trunk_height: float, trunk_radius: float, bark_texture: Texture2D) -> TreeGenTree:
	var tree := TreeGenTree.new()
	tree.trunk_height = trunk_height
	tree.trunk_radius = trunk_radius
	tree.bark_texture = bark_texture
	return tree
