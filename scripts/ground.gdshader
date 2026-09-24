shader_type spatial;

// Water parameters
uniform sampler3D water_noise : repeat_enable;
uniform sampler2D water_depth : hint_depth_texture, repeat_disable, filter_nearest;

uniform sampler2D water_texture : source_color;
uniform sampler2D roads_texture : source_color;
uniform sampler2D buildings_texture : source_color;
uniform sampler2D railways_texture : source_color;
uniform vec3 water_color : source_color = vec3(0.0, 0.0, 1.0);
uniform vec3 ground_color : source_color = vec3(0.25, 0.5, 0.25);
uniform vec3 hill_color : source_color = vec3(0.35, 0.3, 0.2);
uniform vec3 road_color : source_color = vec3(0.4, 0.3, 0.2);
uniform vec3 building_color : source_color = vec3(0.8, 0.1, 0.1);
uniform vec3 rail_color : source_color = vec3(0.5, 0.5, 0.5);

// Height goes between 0.0 and 1.0
varying float height;

// Water value is smoothed 0.0 and 1.0, where 0.0 means water
varying float water_value;

bool is_water(float value) {
	return value < 0.7; // Arbitrarily chosen to a value that looks good
}

void vertex() {
	water_value = texture(water_texture, UV).y;
	height = VERTEX.y;

	if (is_water(water_value)) {
		// vec2 pos = VERTEX.xz - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
		vec3 sample_pos = TIME * 0.1 + vec3(VERTEX.x, 0, VERTEX.z) * 0.05;
		float sample = texture(water_noise, sample_pos).r;
		VERTEX.y -= 0.02 + sample * 0.1;

		float sample_px = texture(water_noise, sample_pos + vec3( 0.05, 0, 0)).r;
		float sample_nx = texture(water_noise, sample_pos + vec3(-0.05, 0, 0)).r;
		float sample_pz = texture(water_noise, sample_pos + vec3(0, 0,  0.05)).r;
		float sample_nz = texture(water_noise, sample_pos + vec3(0, 0, -0.05)).r;
		NORMAL = vec3((sample_nx - sample_px) / 2.0, 1.0, (sample_nz - sample_pz) / 2.0);
	}
}

void fragment() {
	if (is_water(water_value)) {
		ALBEDO = water_color;
		METALLIC = 0.0;
		SPECULAR = 1.0;
		ROUGHNESS = 0.0;
	}
	else if (height > 0.25) {
		ALBEDO = hill_color + vec3(height - 0.25);
	}
	else {
		ALBEDO = ground_color;
	}

	// Roads: blend brown over land only (not under water)
	float road_value = texture(roads_texture, UV).r;
	ALBEDO = mix(ALBEDO, road_color, smoothstep(0.5, 0.6, road_value) * step(0.5, water_value));

	// Buildings: blend red over land only (not under water)
	float building_value = texture(buildings_texture, UV).r;
	ALBEDO = mix(ALBEDO, building_color, smoothstep(0.5, 0.6, building_value) * step(0.5, water_value));

	// Railways: blend gray over land only (not under water)
	float rail_value = texture(railways_texture, UV).r;
	ALBEDO = mix(ALBEDO, rail_color, smoothstep(0.5, 0.6, rail_value) * step(0.5, water_value));
}
