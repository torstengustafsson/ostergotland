# AGENTS.md

Godot 4.7.1 (GDScript) 3D terrain demo of Östergötland, Sweden (Kimstad area), driven by a Copernicus DEM and an OSM extract. **No tests, no CI, no linter or formatter, but the scripts are kept free of GDScript warnings** — every warning is a defect to fix, not to silence with `@warning_ignore`. The source carries thorough `##` module docs on every file in `scripts/`; read those first rather than expecting this file to repeat them.

## Commands

- Engine: `/home/torsten/godot/Godot_v4.7.1-stable_linux.x86_64` (also in `.vscode/settings.json`). A 4.6 build sits beside it — do **not** use it, it would rewrite 4.7 features in `project.godot` and the `.import` files.
- Run: `<binary> --path .`, or open `main.tscn`. Physics is Jolt.
- **Verify with a smoke run** — there is nothing else:
  `timeout 30 <binary> --headless --quit-after 3`
  It boots `main.tscn` and prints load time, the heightmap extent/cell size, tile count, and the resolved spawn. The `ObjectDB instances were leaked` / `N resources still in use at exit` errors at shutdown are pre-existing and harmless.
- **No command gets a `timeout` above 30 seconds.** Nearly every check here finishes in seconds, so a ceiling that generous already catches a hang. If something genuinely cannot finish inside it, split the work into shorter steps or say plainly that it needs longer — do not quietly raise the ceiling, because a run that sits for minutes is exactly how a hang goes unnoticed.
- Keep verification runs wrapped in `timeout 30`. A smoke run is ~1.5 s, so a timeout means a hang and is a bug to diagnose, not a number to raise. The usual cause is awaiting a one-shot signal that already fired — `await RenderingServer.frame_post_draw` blocks forever if the frame was presented; capture the viewport from a later `_process` instead.
- **Warnings are checked through the LSP**, because nothing else reports them (see Gotchas): `<binary> --headless --editor --path . --lsp-port 6017`, connect to `127.0.0.1:6017` with LSP framing (`Content-Length` headers), send `initialize` (rootUri `file://` + the project dir) and `initialized`, then one `textDocument/didOpen` per `.gd` file (`languageId: "godot"` plus its text) and collect `textDocument/publishDiagnostics`, whose `message` names the warning (`SHADOWED_VARIABLE_BASE_CLASS`, `INTEGER_DIVISION`, …). Wait until every file has reported once — base-class and cross-file warnings only appear after the project is indexed — then keep reading for a few seconds more. Exit code says nothing; the run is clean at **0 diagnostics**.
- `<binary> --headless --import` regenerates `.uid`/`.import` files after adding, renaming or duplicating scripts or assets — no need to open the editor. `.gd.uid` and `.import` files are committed; do not delete them.
- `opencode.json` denies `git *` and `opencode.json` itself: don't try to run git commands.
- `python3 assets/mapdata/osm_to_json.py` regenerates `ways.json` from `ways.osm` (stdlib only). `ways.osm` is 55 MB and takes ~23 minutes, so treat it as a deliberate, occasional act. It also accepts file names or `--all` to convert every `.osm` in the folder.

## Code style

- **Comments earn their place only by saying something the code does not**: why a sign is flipped, which order two calls must run in, what bounds a number, what breaks silently if it changes. One to three lines per block, or none. No narrating the next line, no `##` on self-explanatory accessors, no post-mortems of bugs already fixed — a comment that only matters because of a decision made elsewhere belongs in that other file.
- Keep it for the things with no other source of truth: the sign and row-order conventions, the "whole ring or nothing" rule, the reach gates, and the uniform-array sizes that must be kept in step by hand.
- **Every text file ends with a newline.** `.editorconfig` sets `insert_final_newline`; binary assets (`.exr`, `.mp3`, `.png`, `.jpg`) are the only exception.
- GDScript uses tabs; the asset-pipeline Python uses 4 spaces.

## Invariants that fail silently

These break without an error message and with the world still looking plausible. They are documented at the relevant code, and listed here so you know they exist.

**Coordinates** — the full rationale is in `osm_projection.gd` and `osm_bounds.gd`.
- **+X is east, +Z is south.** Row 0 of the DEM is its northern edge and sits at the *lowest* world Z. Putting north at +Z mirrors the whole world; every coordinate stays correct and terrain and OSM features still mirror *together*, so nothing catches it but where the player ends up facing.
- `assets/heightmap/coordinates_bounds` is the terrain's extent — `heightmap.gd` reads it, `main.gd` passes `$Heightmap.bounds` to the projection. `ways.json`'s own `bounds` is a different box (~270 m off in latitude) and must not be used for anything that lines up with terrain.
- `OsmBounds.to_pixel()` rounds to int and clamps; `OsmProjection` keeps floats and does not clamp. Ways continue past the heightmap, so the quadtree's `world_bounds()` is bigger than the terrain.

**World scale** — one world unit is one metre on all three axes.
- Horizontal scale comes from `OsmBounds.cell_size_m()` (16.145 × 30.949 m here — a degree of longitude is cos(latitude) times a degree of latitude, so the cell is *not* square). `scale` and `cell_size` are zero until `Heightmap._ready()` has run.
- The EXR holds **millimetres**. `HEIGHT_NORMALIZATION` (1000) is applied in `Heightmap._height()` and nowhere else. Skipping it puts the mesh tens of thousands of metres above its collider, so physics, forests and the player all look right while the terrain is invisible from every direction.
- The DEM is loaded as an **imported resource**, not `Image.load_from_file()`, so it survives an export — which makes the import options part of the terrain's accuracy. `output_hh.exr.import` must stay lossless (`compress/hdr_compression=0`, `detect_3d/compress_to=0`); the defaults say "VRAM Compressed" (BPTC), which quantizes millimetre values by enough to show as banding and steps in the terrain. Compare the loaded image against `Image.load_from_file()`'s `get_data()` before trusting a change here.

**Terrain tiles**
- A tile's mesh spans `TILE_SIZE + 1` columns so neighbours share edge vertices; its collision shape is one cell wider again so shapes overlap. Both must be right or seams appear — as holes in the render, as cracks in the physics.
- Normals come from the analytic height-field gradient, **not** `SurfaceTool.generate_normals()`, which would light shared edges differently and draw the tile grid onto the landscape.
- Triangles are wound **clockwise seen from above**. The reverse renders fully culled, invisible terrain whose collision still works.
- `update_stream()` measures in **world metres**, not source pixels, and `_tile_world_rect()` has to subtract `_grid_origin_offset()` or the disc is measured from the grid's own corner.

**Ground shader / OSM features**
- `OsmGroundData.MAX_LINES` (1408) and `MAX_AREA_EDGES` (512) **must** match the four `uniform vec4 ...[n]` declarations in `ground.gdshader` by hand. A uniform array's size has to be a literal in the shader (godotengine/godot#72087), which is the only reason this is manual, and a half-done resize draws the old number's worth of features with no error anywhere.
- **A filled ring is uploaded whole or not at all.** The shader's even-odd crossing test inverts everywhere a missing side used to close the ring, so a half ring floods to infinity instead of being a smaller mistake. The area layer is **water only** — buildings are geometry now (see `scripts/buildinggenerator/`), and a filled ring is flat paint, so anything that should stand up cannot use it.
- The two uniform arrays put the kind in **different components** (`area_attrs[i].x`, `line_attrs[i].y`) — see the note on `OsmGroundData._fill`.
- `upload()` keeps the **nearest** N, so the caps *are* the visible distance: the horizon is how far the marginal entry reaches, not the cap and not `DETAIL_RADIUS`. Raising the caps without raising `LOAD_RADIUS`/the camera far plane buys nothing.
- `Layer.points` is the unsorted candidate list. To check what the shader actually got, read back `material.get_shader_parameter("area_points")`.
- `type=multipolygon` relations are stitched into ways in `OsmDataset._multipolygon_ways()` *before* the tag filter, and an `inner` chain becomes its own way with the same tags so islands read as land. A lake the size of Roxen is a relation, not a closed way.

**Runtime wiring** — `main.gd` builds everything not in `main.tscn` and is where test content lives.
- Setting the spawn takes two steps in a fixed order: `_place_player_at_lonlat()` in `_ready()` **before** `set_stream_target()` (it decides which tiles load), and `_snap_player_to_ground()` in the **first `_process()`** (a raycast cannot see collision shapes the physics server has not stepped yet — from `_ready()` it comes back empty every time).
- `camera.far` is set from `Heightmap.LOAD_RADIUS * 0.96` in `main.gd` to keep the streamed disc's ragged edge off screen.

## Gotchas

- **GDScript warnings print nowhere.** Not in a smoke run, not under `--headless`, not with `--check-only --script` — the analyzer keeps them in the script editor's warnings panel and writes nothing to the console, so a clean run says nothing about them and `--verbose` does not help. The LSP is the only machine-readable source (Commands). Expect them in the places the style above already answers for: a parameter that shares a member's name (`p_`-prefix it, as `OsmQuadtree` and `OsmGroundData.bind` do), a local named after a `Node3D` property (`position`, `scale`, `basis`, `transform`, `ready`), and a variable named after a global function (`seed`) — those are all renames, not suppressions.
- **The headless renderer never parses a shader.** `--headless` lands on `RendererDummy` where `Shader.set_code` is a no-op, so even broken shader code reports nothing. A clean smoke run says nothing about `ground.gdshader`; compile it windowed (~3 s on `DISPLAY=:0`) and look for `Using Device` plus any `Shader compilation failed`. Shader-language rules that bite: a function may only be called from a function **below** it, and uniform array sizes must be literals.
- **`MultiMesh` instance data is a no-op under `--headless`** — transforms silently stay identity and AABBs are empty, so every tree reads as being at the origin. Only `instance_count` and the mesh's own vertex counts are trustworthy headless; verify placement by rendering and differencing the images.
- There is no display feedback here, so verify visuals by saving `get_viewport().get_texture().get_image().save_png(...)` from a frame counter and probing the PNG. Flat debug colours plus a white `AMBIENT_SOURCE_COLOR`/`TONE_MAPPER_LINEAR` environment make it unambiguous — with the scene's own sky-only ambient (there is **no** `DirectionalLight3D`) a probe on the real albedo is unreliable. Aim the `Camera3D` directly: the brackeys controller owns its yaw/pitch and overwrites `ProtoController.rotation`.
- Trees are placed by raycasting the terrain, which only hits inside the streamed `LOAD_RADIUS`, and hits *anything* in the way (including the player's own capsule). Changing height normalization or the heightmap's scale/centering makes forests float or sink.
- **Buildings ask `Heightmap.height_at_world()` for their ground instead of raycasting** (`BuildingGen`). A raycast here would hit a neighbouring building's collider or the player's capsule and stack one on top of the other; the height map needs no physics and no step order. It rounds to a pixel centre where the collider interpolates, so the walls are sunk by `GROUND_SINK`.
- Free-fly is the `freefly` action bound to **physical keycode 59** (the `Ö` key on a Swedish layout), not a letter. Remap in the Input Map tab.
- Startup: ~0.35 s to index the extracted features, then ~0.5 s per generated forest. Lower the loop cap in `main.gd` when iterating on placement.
