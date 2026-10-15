shader_type spatial;

// Ground features are drawn from the OSM geometry itself rather than from mask
// textures: OsmGroundData uploads the ways near the player as line segments and
// area edges in *metres*, and the shader measures how far each fragment is from
// them, so road widths come from the tags.
//
// The arrays are also the shader's cost: every fragment inside the reach gate runs
// one distance test per uploaded segment, so OsmGroundData keeps them capped and
// filled with whatever is nearest -- and since it keeps the nearest N, the cap is
// what the visible distance is.

// **The four sizes below are the only numbers to keep in step with
// OsmGroundData.MAX_LINES / MAX_AREA_EDGES.** The loops bound themselves on
// line_count and area_count rather than repeating the literal, which is the only
// reason any of this is by hand: a uniform array's size has to be a literal in
// the declaration. A half-done resize draws the old number's worth of features
// with no error anywhere.

// (ax, az, bx, bz) in metres: a stroked feature's two ends, or one side of a
// filled area's ring.
uniform vec4 line_points[1408];
// (half_width, kind, rank) for a line entry, and upload() adds the reach in w.
uniform vec4 line_attrs[1408];
uniform int line_count = 0;
uniform vec4 area_points[576];
// (kind, 0, 0), and upload() adds the reach in w. Note that the two arrays put
// the kind in different components, which is the CPU side's problem and not this
// one's: see OsmGroundData._fill.
uniform vec4 area_attrs[576];
uniform int area_count = 0;

// Which feature an entry is, mirrored in OsmGroundData.
//
// **The four cover kinds are consecutive and this is their channel order**: they
// are held as the components of a vec4 below and picked by counting down from
// AREA_FARMLAND, so reordering these means reordering area_masks() and
// OsmGroundData.COVER with them. AREA_FOREST is outside that run on purpose -- it
// is the one kind with no texture of its own and gets its own out value.
const float KIND_ROAD = 0.0;
const float KIND_RAIL = 1.0;
const float KIND_WATERWAY = 2.0;
const float AREA_WATER = 1.0;
const float AREA_FARMLAND = 2.0;
const float AREA_MEADOW = 3.0;
const float AREA_GRASS = 4.0;
const float AREA_BEACH = 5.0;
const float AREA_FOREST = 6.0;

// The wave noise. Sampled by world position rather than by uv, so the waves do
// not swim when the camera moves.
uniform sampler3D ground_noise : repeat_enable;
// The forest floor's patch noise, built by OsmGroundData rather than shared with
// the waves: the two want different things out of one volume, and sharing one is
// what left the patch blend with nowhere to put its ramp edges.
//
// **One volume per patch.** Decoupling the two samples is only half of what the
// patches need; an offset into one volume leaves both the same patch *size*, and
// that is the half no offset can reach. Bare earth shows in small scattered spots
// where the litter thins and grass comes in broad sweeps, so each patch is its own
// FastNoiseLite, at its own frequency and seeded apart. See OsmGroundData.
uniform sampler3D forest_soil_noise : repeat_enable;
uniform sampler3D forest_grass_noise : repeat_enable;

// One ground scan per cover kind, sampled by ground.gdshader's own uv scale below
// rather than by anything the tiles provide. Bound from OsmGroundData.COVER.
uniform sampler2D soil_texture : source_color, repeat_enable;
uniform sampler2D meadow_texture : source_color, repeat_enable;
uniform sampler2D grass_texture : source_color, repeat_enable;
uniform sampler2D beach_texture : source_color, repeat_enable;

uniform vec3 water_color : source_color = vec3(0.0, 0.0, 1.0);
uniform vec3 ground_color : source_color = vec3(0.25, 0.5, 0.25);
uniform vec3 hill_color : source_color = vec3(0.35, 0.3, 0.2);
uniform vec3 road_color : source_color = vec3(0.4, 0.3, 0.2);
uniform vec3 rail_color : source_color = vec3(0.5, 0.5, 0.5);

// Metres one ground scan covers, per cover kind, in the channel order above.
// Small enough that a scan keeps its own sense of scale on the ground, large
// enough that a 40 m field is not the same picture as its neighbour. The uv is
// world position over this, so the tiling is anchored to the world: it does not
// swim as the camera moves and it does not restart when the arrays are repacked.
uniform vec4 cover_tile_m = vec4(8.0, 8.0, 8.0, 8.0);
// What each scan is multiplied by, same order again. The scans are photographs
// and the terrain ramp beside them is a flat colour, so at face value a beach
// reads about 1.6x and a meadow 1.4x brighter than the ground they sit in, a
// lawn and a ploughed field darker, which looks like a patch pasted on rather
// than a surface. These are the per-kind corrections that put all four on the
// ramp's own brightness.
uniform vec4 cover_tint = vec4(1.50, 0.72, 1.29, 0.64);
// Metres over which a cover texture fades out at its edge, per kind and in the
// same order again: half of it is spent inside the ring and half outside, so a
// field is at full strength this far from its own boundary and gone this far
// past it, melting into whatever is next to it.
//
// **Two of the three seams this fixes are already invisible**: the uv is world
// position, so two neighbours of the *same* kind tile continuously across their
// shared boundary and have nothing to blend. What is left is where farmland
// meets meadow, and where cover meets untagged terrain, and the second is the
// common one -- a hard edge against a flat colour is what reads as a texture
// pasted onto the map.
//
// Water keeps FEATHER instead: it is a colour rather than a scan, and the vertex
// stage's test that sinks the ground has no distance to fade over.
uniform vec4 cover_fade_m = vec4(12.0, 12.0, 12.0, 12.0);

// Forest floor: not a texture of its own but the same three scans the cover kinds
// already sample, blended by noise so a wood is mossy litter with grass and bare
// soil in it rather than one flat green. It reuses farmland/meadow/grass below
// at their own cover_tile_m scales -- they are the same scans on the same ground,
// and a second set of samplers would only buy a second copy of them.
//
// Metres per repeat of the patch noises, i.e. how big the patches are. Sampled by
// world position, so a wood does not shuffle as you walk through it. Both noises
// are seamless, so a repeat does not end in a seam.
uniform float forest_patch_m = 512.0;
// As cover_fade_m is for the cover kinds, for the woods.
uniform float forest_fade_m = 16.0;
// Shading for the wood as a whole, on top of the per-kind cover_tint the three
// scans already get. Without it a wood is no darker than the field beside it,
// which is the one thing a canopy always is; the cooler green is what shade
// under leaves looks like.
uniform vec3 forest_tint : source_color = vec3(0.72, 0.78, 0.70);

// How much of its own sample a patch needs before it shows. Ground037 is the
// floor they both blend into, so the default is what is left when neither does.
//
// **These are placed on the noise's measured distribution, not on 0..1.**
// NoiseTexture3D maps FastNoiseLite's signed output onto 0..1, and a three-octave
// simplex lands in about 0.10..0.89 with half of it inside 0.40..0.60 -- so both
// pairs sit on that median. Anything below 0.10 is the failure worth naming: it is
// under the whole volume, so smoothstep returns 1 for every fragment and the
// patches come out as one flat blend instead of patches at all.
uniform vec2 forest_soil_edge = vec2(0.40, 0.60);
uniform vec2 forest_grass_edge = vec2(0.40, 0.60);

// Metres per world unit on X and Z, from the projection (see
// OsmProjection.metres_per_unit). The world is in metres, so this arrives as
// (1, 1); it stays a uniform because it is the one place that knows how to
// convert, and the terrain is free to stop being metres.
uniform vec2 metres_per_unit = vec2(1.0, 1.0);
// Where the features below were gathered from, and how far the furthest one of
// them reaches, both in metres. Nothing the arrays describe is ever drawn past
// its reach, so a fragment or vertex beyond it can skip the loops outright. Past
// 1393 m that is all of them, against a 1440 m far plane.
uniform vec2 focus_metres = vec2(0.0, 0.0);
// The line loops also test this per entry (line_attrs.w), which is tighter, but a
// single gate before the loop is what stops the loop at all.
uniform float line_reach = 0.0;
uniform float area_reach = 0.0;
// Terrain height in metres over which ground_color fades into hill_color.
uniform float min_height = 0.0;
uniform float max_height = 160.0;

// How far past its own width a line still counts, and how wide the fade is at an
// area's edge, in metres. Without it every feature would end in a hard line.
const float FEATHER = 0.6;
// Noise units per world unit for the water waves.
const float WAVE_SCALE = 0.005;

// Fragment position in world space, which the features are measured against.
varying vec3 world_pos;
// World Y, for the ground/hill ramp.
varying float terrain_height;
// Water coverage at this vertex: the filled water areas only, i.e. what sinks the
// ground and makes it ripple. Watercourses are thinner than a terrain cell, so a
// per-vertex test would mostly miss them; the fragment stage finds them.
varying float water_value;


bool is_water(float value) {
	return value > 0.5;
}


float segment_distance_sq(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float length_sq = dot(ab, ab);
	float t = 0.0;
	if (length_sq > 0.0) {
		t = clamp(dot(p - a, ab) / length_sq, 0.0, 1.0);
	}
	vec2 d = p - (a + ab * t);
	return dot(d, d);
}


// How much of each kind of line covers `p`, in (roads, railways, watercourses,
// road rank). Overlapping features take the strongest coverage rather than adding
// up, so a footway crossing a motorway leaves a motorway.
//
// `focus_dist` is how far `p` is from focus_metres and attr.w is how far the
// segment reaches from the same point, so `focus_dist > attr.w + reach` proves the
// fragment cannot be within reach of any point on the segment. That is a compare
// and a subtract against a known distance, where segment_distance_sq below is a
// dot product, a divide and a lerp: worth doing per entry, since it rejects
// nearly all of them for nearly every fragment.
vec4 line_masks(vec2 p, float focus_dist) {
	vec4 masks = vec4(0.0);
	for (int i = 0; i < line_count; i++) {
		vec4 attr = line_attrs[i];
		float half_width = attr.x;
		float feather = max(min(FEATHER, half_width * 0.5), 0.001);
		float reach = half_width + feather;
		if (focus_dist > attr.w + reach) {
			continue;
		}
		float distance_sq = segment_distance_sq(p, line_points[i].xy, line_points[i].zw);
		if (distance_sq > reach * reach) {
			continue;
		}
		float coverage = 1.0 - smoothstep(half_width, reach, sqrt(distance_sq));
		float kind = attr.y;
		if (kind == KIND_ROAD) {
			masks.x = max(masks.x, coverage);
			masks.w += coverage * attr.z;
		} else if (kind == KIND_RAIL) {
			masks.y = max(masks.y, coverage);
		} else {
			masks.z = max(masks.z, coverage);
		}
	}
	return masks;
}


// The filled water areas covering `p`, without the antialiasing the fragment
// stage adds: the value is interpolated across a triangle anyway, so the crossing
// count on its own is enough here, and skipping the non-water entries keeps this
// cheap enough to run per vertex.
float water_area_mask(vec2 p) {
	float inside = 0.0;
	for (int i = 0; i < area_count; i++) {
		if (area_attrs[i].x != AREA_WATER) {
			continue;
		}
		vec2 a = area_points[i].xy;
		vec2 b = area_points[i].zw;
		if ((a.y > p.y) != (b.y > p.y)) {
			float t = (p.y - a.y) / (b.y - a.y);
			if (p.x < a.x + t * (b.x - a.x)) {
				inside = 1.0 - inside;
			}
		}
	}
	return inside;
}


// The filled water areas covering `p`: every area edge is one crossing test, so
// the count is the even-odd inside test, and the distance to the nearest edge
// antialiases it. The sign of that distance is the crossing test's, which is why
// no signed distance is needed: a fragment inside an area is on the inner side of
// its nearest edge. Overlapping rings of the same kind cancel out.
//
// The non-water kinds are skipped rather than merely not counted, which is what
// keeps the ground cover below out of a lake's fill. Buildings were here and are
// geometry now; see BuildingGen.
float area_water_mask(vec2 p) {
	float inside = 0.0;
	float nearest_sq = 1000000000.0;
	for (int i = 0; i < area_count; i++) {
		if (area_attrs[i].x != AREA_WATER) {
			continue;
		}
		vec2 a = area_points[i].xy;
		vec2 b = area_points[i].zw;
		if ((a.y > p.y) != (b.y > p.y)) {
			float t = (p.y - a.y) / (b.y - a.y);
			if (p.x < a.x + t * (b.x - a.x)) {
				inside = 1.0 - inside;
			}
		}
		nearest_sq = min(nearest_sq, segment_distance_sq(p, a, b));
	}
	return smoothstep(-FEATHER, FEATHER, (inside * 2.0 - 1.0) * sqrt(nearest_sq));
}


// The ground cover covering `p`, one channel per kind in the order the kinds are
// declared at the top: farmland, meadow, grass, beach. The same crossing test and
// nearest-edge antialiasing as area_water_mask, and the fragment stage turns each
// channel into a texture of its own.
//
// **The parity is kept per kind rather than across every filled area at once**,
// which is why this is a separate function from area_water_mask and not a second
// call into it: farmland rings overlap meadow rings constantly, and one crossing
// parity shared between them cancels both to nothing over the whole overlap.
// Keeping them apart only leaves the case that is genuinely wrong -- two rings of
// the *same* kind overlapping, a lake inside a lake -- which is the same trade
// water already makes and the reason it has its own function.
//
// The edge fade is each kind's own cover_fade_m rather than the shared FEATHER,
// which is what makes a cover texture reach out past its own ring. Half of that
// distance is spent on each side of the boundary, because the nearest edge is
// measured from wherever the fragment is: the sign is the crossing test's, the
// size is how far it is. Where two kinds have a strip of bare ground between
// them -- farmland next to meadow is the common case -- each fades into that
// strip from its own side and the two overlap, so the strip goes rather than
// showing as a seam.
//
// The distance is a min over every edge of that kind in the upload rather than
// over one ring's, which is right where it is used -- at a boundary the nearest
// edge of that kind *is* the boundary. Away from one it means a fragment deep
// inside a field also answers to a neighbouring field's edge, and goes slightly
// translucent near it; a ring id per edge would fix that and the uniform budget
// has no room for it.
void area_masks(vec2 p, out vec4 cover, out float forest) {
	vec4 inside = vec4(0.0);
	vec4 nearest_sq = vec4(1000000000.0);
	float forest_inside = 0.0;
	float forest_nearest_sq = 1000000000.0;
	for (int i = 0; i < area_count; i++) {
		float kind = area_attrs[i].x;
		if (kind < AREA_FARMLAND || kind > AREA_FOREST) {
			continue;
		}
		vec2 a = area_points[i].xy;
		vec2 b = area_points[i].zw;
		bool crossing = false;
		if ((a.y > p.y) != (b.y > p.y)) {
			float t = (p.y - a.y) / (b.y - a.y);
			crossing = p.x < a.x + t * (b.x - a.x);
		}
		// One component per kind, in the order the kinds are declared at the top,
		// written out rather than steered by a one-hot vec4: **mix() against the
		// 1e9 sentinel left it in place instead of overwriting it**, so the
		// distance came out huge for every fragment and the mask collapsed to a
		// bare parity step -- the edges stayed hard however cover_fade_m was set.
		// A min against what the component already holds is what was wanted.
		float d_sq = segment_distance_sq(p, a, b);
		if (kind == AREA_FARMLAND) {
			inside.x = crossing ? 1.0 - inside.x : inside.x;
			nearest_sq.x = min(nearest_sq.x, d_sq);
		} else if (kind == AREA_MEADOW) {
			inside.y = crossing ? 1.0 - inside.y : inside.y;
			nearest_sq.y = min(nearest_sq.y, d_sq);
		} else if (kind == AREA_GRASS) {
			inside.z = crossing ? 1.0 - inside.z : inside.z;
			nearest_sq.z = min(nearest_sq.z, d_sq);
		} else if (kind == AREA_BEACH) {
			inside.w = crossing ? 1.0 - inside.w : inside.w;
			nearest_sq.w = min(nearest_sq.w, d_sq);
		} else {
			forest_inside = crossing ? 1.0 - forest_inside : forest_inside;
			forest_nearest_sq = min(forest_nearest_sq, d_sq);
		}
	}
	vec4 half_fade = cover_fade_m * 0.5;
	vec4 signed_nearest = (inside * 2.0 - 1.0) * sqrt(nearest_sq);
	cover = smoothstep(-half_fade, half_fade, signed_nearest);
	float forest_signed = (forest_inside * 2.0 - 1.0) * sqrt(forest_nearest_sq);
	forest = smoothstep(-forest_fade_m * 0.5, forest_fade_m * 0.5, forest_signed);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_height = world_pos.y;
	vec2 p = world_pos.xz * metres_per_unit;
	// Gated on the reach of the uploaded rings, which is exact: OsmGroundData
	// skips a ring whose farthest side is past it, so a vertex further from the
	// focus than that is outside every one of them.
	//
	// The zero is not decoration: a varying written only inside the branch is
	// left *unwritten* for every vertex that skips it, and the vertex output
	// buffer is pooled across draws, so what the fragment stage interpolates is
	// whatever the previous draw happened to leave in that slot. Written first,
	// then gated on, like `lines` and `areas` below.
	water_value = 0.0;
	float focus_dist = distance(p, focus_metres);
	if (focus_dist <= area_reach + FEATHER) {
		water_value = water_area_mask(p);
	}

	if (is_water(water_value)) {
		// Sunk in the terrain's own local units, so the node's Y scale still
		// applies. Sampled in world space, unlike the vertex positions: the noise
		// would otherwise repeat exactly once per streamed tile.
		vec3 wave_pos = vec3(world_pos.x, 0.0, world_pos.z) * WAVE_SCALE;
		VERTEX.y -= 0.02 + texture(ground_noise, TIME * 0.1 + wave_pos).r * 0.1;

		vec3 sample_pos = TIME * 0.1 + wave_pos;
		float sample_px = texture(ground_noise, sample_pos + vec3( 0.05, 0, 0)).r;
		float sample_nx = texture(ground_noise, sample_pos + vec3(-0.05, 0, 0)).r;
		float sample_pz = texture(ground_noise, sample_pos + vec3(0, 0,  0.05)).r;
		float sample_nz = texture(ground_noise, sample_pos + vec3(0, 0, -0.05)).r;
		vec3 wave_normal = normalize(vec3(sample_nx - sample_px, 2.0, sample_nz - sample_pz));
		NORMAL = (VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz;
	}
}


void fragment() {
	vec2 p = world_pos.xz * metres_per_unit;
	float focus_dist = distance(p, focus_metres);
	// One gate each, for the same reason as in vertex(): the features reach a few
	// hundred metres and the view is four kilometres, so most fragments are past
	// all of them and can skip the loops entirely.
	vec4 lines = vec4(0.0);
	if (focus_dist <= line_reach + FEATHER) {
		lines = line_masks(p, focus_dist);
	}
	float area_water = 0.0;
	vec4 cover = vec4(0.0);
	float forest = 0.0;
	// One gate for both, because they come out of the same arrays and the same
	// reach; only the loop inside differs.
	//
	// The margin is the widest cover fade rather than FEATHER, because a cover
	// texture is still partly opaque this far *past* its own ring: gating on
	// FEATHER would slice the fade off at the edge of the detail radius and put
	// a hard arc back exactly where the margin exists to avoid one.
	float fade_gate = max(max(cover_fade_m.x, cover_fade_m.y),
			max(cover_fade_m.z, max(cover_fade_m.w, forest_fade_m))) * 0.5;
	if (focus_dist <= area_reach + max(FEATHER, fade_gate)) {
		area_water = area_water_mask(p);
		area_masks(p, cover, forest);
	}

	// The vertex stage knows about the filled water; the watercourses it cannot
	// see between two vertices are added here.
	float water_here = clamp(max(water_value, max(area_water, lines.z)), 0.0, 1.0);

	vec3 albedo;
	float roughness = 1.0;
	if (is_water(water_here)) {
		albedo = water_color;
		roughness = 0.05;
	} else {
		float terrain = clamp((terrain_height - min_height)
			/ max(max_height - min_height, 0.001), 0.0, 1.0);
		albedo = mix(ground_color, hill_color, terrain);
		// Cover paints over the terrain ramp and under the lines: a field is a
		// field on a hillside, and a road runs through it rather than under it.
		//
		// Gated on the masks as well as on the reach, because inside the reach
		// most fragments are in open country with no polygon anywhere near them
		// and would otherwise pay four texture fetches for nothing. The uv is
		// world metres over the per-kind tile size, so a scan does not swim or
		// restart when the arrays are repacked around the player.
		if (cover.x + cover.y + cover.z + cover.w > 0.0) {
			albedo = mix(albedo, texture(soil_texture, p / cover_tile_m.x).rgb * cover_tint.x, cover.x);
			albedo = mix(albedo, texture(meadow_texture, p / cover_tile_m.y).rgb * cover_tint.y, cover.y);
			albedo = mix(albedo, texture(grass_texture, p / cover_tile_m.z).rgb * cover_tint.z, cover.z);
			albedo = mix(albedo, texture(beach_texture, p / cover_tile_m.w).rgb * cover_tint.w, cover.w);
		}
		// The forest floor, after the cover and for the same reason: a wood sits
		// on the ground rather than under it, and where the two overlap in the
		// data the canopy is what should be seen.
		//
		// Three fetches and two noise taps, all of them gated on the mask, so only
		// fragments actually under trees pay for a wood.
		if (forest > 0.0) {
			vec3 np = vec3(p.x, 0.0, p.y) / forest_patch_m;
			float n_soil = texture(forest_soil_noise, np).r;
			float n_grass = texture(forest_grass_noise, np).r;
			float soil = smoothstep(forest_soil_edge.x, forest_soil_edge.y, n_soil);
			float grass = smoothstep(forest_grass_edge.x, forest_grass_edge.y, n_grass);
			// Each scan keeps the cover_tint it has outside a wood, so the three
			// arrive at the blend already level with each other and the patches
			// read as a change of surface rather than a change of brightness.
			vec3 moss_albedo = texture(meadow_texture, p / cover_tile_m.y).rgb * cover_tint.y;
			vec3 soil_albedo = texture(soil_texture, p / cover_tile_m.x).rgb * cover_tint.x;
			vec3 grass_albedo = texture(grass_texture, p / cover_tile_m.z).rgb * cover_tint.z;
			// Weighted rather than one mixed over the other, because which patch
			// is on top is not a thing here: the stronger one shows, and where
			// they overlap they mix. The clamp keeps the moss underneath from
			// being blended twice over.
			vec3 patches = (soil_albedo * soil + grass_albedo * grass)
					/ max(soil + grass, 0.0001);
			vec3 floor_albedo = mix(moss_albedo, patches, clamp(soil + grass, 0.0, 1.0));
			albedo = mix(albedo, floor_albedo * forest_tint, forest);
		}
		// class_rank() again, this time as colour: a track is duller tarmac than
		// a motorway, which is the same tag that made it narrower.
		float rank = clamp(lines.w / max(lines.x, 0.001), 0.0, 1.0);
		albedo = mix(albedo, road_color * mix(0.85, 1.15, rank), lines.x);
		albedo = mix(albedo, rail_color, lines.y);
	}
	ROUGHNESS = roughness;
	ALBEDO = albedo;
}
