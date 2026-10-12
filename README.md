# Östergötland

A mostly vibe-coded project that allows the player to explore Östergötland, with a focus on Kimstad area.

Built with Godot 4.7. 

Heightmap downloaded from opentopography.org, using Copernicus dataset, with resolution of 30x30 meters.

Vector map data (roads, fields, forests, etc.) are downloaded from openstreetmap.org.

## Adding map data

Every `.json` in `assets/mapdata/` is a vector source, and all of them are merged
into one dataset at startup — so adding data is dropping a file in. The format is
what `assets/mapdata/osm_to_json.py` writes, which converts any `.osm` dump in
that folder (`python3 osm_to_json.py mydata.osm`) and is also what a hand-written
file may use. A source may list `"replaces": ["<id>"]` to supersede another
source's features, which is what `lakes.json` does for two lake relations from the
OSM extract. See `scripts/osmdataset/map_data.gd`.

Trees are procedurally generated using an implementation of Weber & Penn (Creation and Rendering of Realistic Trees)
