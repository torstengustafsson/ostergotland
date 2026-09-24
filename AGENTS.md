# AGENTS.md

Godot 4.7.1 (GDScript) 3D terrain demo of Östergötland, Sweden (Kimstad area). No tests, no CI, no linter/formatter.

## Commands

- Godot binary: `/home/torsten/Godot/Godot_v4.7.1-stable_linux.x86_64` (also in `.vscode/settings.json`). Do **not** use the sibling `Godot_v4.6-stable_linux.x86_64` — it would clobber 4.7 features in `project.godot`/`.import`.
- Run: `godot --path .`, or open `main.tscn` in the editor.
- No test suite, so verify with a headless smoke run: `<binary> --headless --quit-after 3`. It boots `main.tscn` and prints load/generation timings. Exit-time noise (`3 resources still in use at exit`, `ObjectDB instances were leaked`) is pre-existing and harmless.
- `<binary> --headless --import` regenerates `.uid`/`.import` files after adding, renaming or duplicating scripts/assets — no need to open the editor.
- `opencode.json` denies `git *` for the bash tool: don't try to run git commands.
- `python3 assets/heightmap/osm_to_json.py` regenerates `ways.json` from `ways.osm` (stdlib only; the current `ways.osm` is ~55 MB and takes a while). Run it from the repo root; paths are resolved relative to the script.

## Scene / runtime wiring

- `main.tscn`: `Main` (Node3D + `scripts/main.gd`, which itself `extends Node`) → `Heightmap` (StaticBody3D running `scripts/load_heightmap.gd`, with `CollisionShape3D` + `MeshInstance3D`), plus `ProtoController` (brackeys addon instance), `WorldEnvironment`, and a HUD `Label`. `sprint_speed`/`freefly_speed` (15 / 500) are set in the scene file, not the addon.
- `main.gd` builds everything else in code (`OsmDataset`, `ForestGen`, `AudioManager`) and is where all test content lives: birdsong at the origin, wind on the camera, and a capped loop over `features["forests"]`. `debug_prints()` at the bottom is leftover scaffolding.
- `load_heightmap.gd` builds mesh *and* `HeightMapShape3D` from the same `HEIGHT_NORMALIZATION` constant; the grid size is read from the EXR (currently 1430×621, not hardcoded anywhere), node scale `Vector3(10, 50, 10)` is set in `_init`, and both mesh and collision are centred on the origin. Physics engine is Jolt (`project.godot`).
- No mask textures are loaded any more — the `viz.hh_aspect*.png` files and the shader-parameter code that used them were removed. `ground.gdshader` still declares `water_texture`/`water_depth`/`roads_texture`/`buildings_texture`/`railways_texture`, and nothing ever sets them; OSM masks are meant to be rasterized at runtime from `ways.json` but aren't wired into the shader yet.
- `assets/heightmap/filter_mask.py` is orphaned: it reads `viz.hh_aspect.png`, which no longer exists. It also needs Pillow, unlike `osm_to_json.py`.

## OSM pipeline (`scripts/osmdataset/`)

- `ways.osm` → `osm_to_json.py` → one `ways.json` (`{bounds, nodes, ways, relations}`). Intermediates are committed; no tag-based splitting, all filtering happens at runtime. **Node ids are strings.**
- Runtime: `OsmDataset` (load, `node_position`/`has_node`, `ways_by_tag*`, `extract_features`) + `OsmFeature` subclasses listed in `OsmDataset.feature_classes` (`OsmRoad`, `OsmWaterArea`, `OsmForestArea`) → `features["roads"|"water"|"forests"]`. Adding a feature kind = subclass `OsmFeature`, append to `feature_classes`, call `extract_features()`. `OsmRaster` paints ways into an `Image` mask (hand-rolled Bresenham/scanline fill — Godot 4.7 has no `Image.draw_line`).
- `OsmLanduseBounds` is the container for a landuse area's bounds in every space: `osm_bounds` (lon/lat), `pixel_rect` (terrain grid), `world_rect` (world XZ, what `ForestGen.add_forest` takes). `from_feature()` needs the terrain bounds, grid size and cell size (see `main.gd`).

## Coordinate spaces (easy to get wrong)

- Projection chain: lon/lat → terrain pixel → world XZ. Pixel→world assumes the grid is centred on the origin with one cell = node scale (`OsmLanduseBounds._grid_rect_to_world`); pixel y maps to world **Z**, and the EXR's row 0 is treated as the low-Z edge.
- `assets/heightmap/coordinates_bounds` (plain text, `Xmin/Ymin/Xmax/Ymax`) records the heightmap's lon/lat extent: 15.7489 / 58.4698 → 16.1465 / 58.6424. **No code reads it yet** — if you need the true terrain extent, parse this file (or hardcode the constant in `OsmBounds`).
- `ways.json`'s own `bounds` (15.75 / 58.47 → 16.1465 / 58.64) now matches that extent, so passing `osm_dataset.bounds` as the terrain bounds (what `main.gd` does) is currently correct. The old "the OSM download is smaller than the terrain" caveat, and the `# approximate` comment on that argument, are obsolete.

## Gotchas

- GDScript uses tabs; the asset-pipeline Python uses 4-space indent. `.gd.uid` and `.import` files are committed (Godot's UID system) — keep them when renaming/duplicating scripts, and regenerate with `--headless --import`.
- `scripts/osmdataset/` is the real package; `scripts/osm_dataset/` (with the underscore) is an empty leftover directory — don't add files there. `osm_to_json.py`'s docstring still names the old one.
- `Image.load_from_file` (rather than loading a Resource) makes Godot warn "this will not work on export" — expected in this demo, not a bug to fix.
- Trees are placed by raycasting the terrain (`ForestGen._ground_height_at`), so anything that changes height normalization or the heightmap's scale/centering makes forests float or sink.
- Startup cost: ~0.5 s per generated forest (100 forests ≈ 56 s). Lower the loop cap in `main.gd` when iterating on placement.
- Free-fly toggle is the `freefly` action in `project.godot`, bound to physical keycode 59 (the `Ö` key on a Swedish layout), not a letter. Remap via the Input Map tab.
