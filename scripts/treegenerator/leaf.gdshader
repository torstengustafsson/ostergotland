shader_type spatial;
render_mode cull_disabled;

// The leaf material: albedo is the vertex colour times the leaf texture, with
// the texture's alpha scissored. It is a shader rather than a
// StandardMaterial3D for one reason only -- underside_tint, which tints one
// face of a double-sided strip. A StandardMaterial3D has no per-facing albedo,
// and the strips (leaf, pinna, blade) are one quad seen from both sides.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
// Multiplied into the albedo of the pale face only, which is the front face --
// see the note in fragment(). White leaves it exactly as it was.
// See TreeGenMaterialLibrary.UNDERSIDE_TINT.
uniform vec4 underside_tint : source_color = vec4(1.0);


void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 albedo = tex.rgb * COLOR.rgb;
	// The tint goes on the FRONT face, which reads backwards until you know how
	// these strips are lit: each is one double-sided quad carrying a single
	// up-tilted normal, and the engine flips that normal for the back face, so
	// the back face is the dark one. The pale side -- the underside of a fern
	// pinna, the side a grass blade leans toward -- is therefore the front
	// face. No normal is written here: the engine's own flip for a
	// double-sided material is what lights the two faces differently, and
	// overriding it makes both faces identical.
	ALBEDO = FRONT_FACING ? albedo * underside_tint.rgb : albedo;
	ROUGHNESS = 1.0;
	ALPHA = tex.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
}
