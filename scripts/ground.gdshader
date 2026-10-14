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
uniform vec4 area_points[512];
// (kind, 0, 0), and upload() adds the reach in w. Note that the two arrays put
// the kind in different components, which is the CPU side's problem and not this
// one's: see OsmGroundData._fill.
uniform vec4 area_attrs[512];
uniform int area_count = 0;

// Which feature an entry is, mirrored in OsmGroundData.
const float KIND_ROAD = 0.0;
const float KIND_RAIL = 1.0;
const float KIND_WATERWAY = 2.0;
const float AREA_WATER = 1.0;

// Water parameters
uniform sampler3D water_noise : repeat_enable;

uniform vec3 water_color : source_color = vec3(0.0, 0.0, 1.0);
uniform vec3 ground_color : source_color = vec3(0.25, 0.5, 0.25);
uniform vec3 hill_color : source_color = vec3(0.35, 0.3, 0.2);
uniform vec3 road_color : source_color = vec3(0.4, 0.3, 0.2);
uniform vec3 rail_color : source_color = vec3(0.5, 0.5, 0.5);

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
// The non-water kinds are skipped rather than merely not counted, so the area
// layer can grow a second kind without this function changing. Buildings were
// here and are geometry now; see BuildingGen.
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
		VERTEX.y -= 0.02 + texture(water_noise, TIME * 0.1 + wave_pos).r * 0.1;

		vec3 sample_pos = TIME * 0.1 + wave_pos;
		float sample_px = texture(water_noise, sample_pos + vec3( 0.05, 0, 0)).r;
		float sample_nx = texture(water_noise, sample_pos + vec3(-0.05, 0, 0)).r;
		float sample_pz = texture(water_noise, sample_pos + vec3(0, 0,  0.05)).r;
		float sample_nz = texture(water_noise, sample_pos + vec3(0, 0, -0.05)).r;
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
	if (focus_dist <= area_reach + FEATHER) {
		area_water = area_water_mask(p);
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
		// class_rank() again, this time as colour: a track is duller tarmac than
		// a motorway, which is the same tag that made it narrower.
		float rank = clamp(lines.w / max(lines.x, 0.001), 0.0, 1.0);
		albedo = mix(albedo, road_color * mix(0.85, 1.15, rank), lines.x);
		albedo = mix(albedo, rail_color, lines.y);
	}
	ROUGHNESS = roughness;
	ALBEDO = albedo;
}
