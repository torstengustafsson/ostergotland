#!/usr/bin/env python3
"""Convert an OSM XML dump into the single compact JSON file the runtime loads.

    python3 osm_to_json.py                 # ways.osm -> ways.json
    python3 osm_to_json.py lakes.osm       # lakes.osm -> lakes.json
    python3 osm_to_json.py --all           # every .osm in this directory

The JSON holds every element that has geometry the runtime can use:

    bounds    - the download bbox as floats
    nodes     - all nodes: { id (string): [lon, lat] }
    ways      - all ways:  [{ id (string), nd: [node id strings], tags: {...} }]
    relations - all relations: [{ id, members: [{type, ref, role}], tags }]

Node ids are kept as strings since JSON object keys are strings anyway.

Anything with this shape loads: MapData picks up *every* .json in this directory
(see scripts/osmdataset/map_data.gd), so a new extract is a file here plus one run
of this script, and a hand-written one needs no run at all. A file may add a
"replaces" list of feature ids it supersedes; the prefix "relation:7919" hides
every ring a multipolygon 7919 was stitched into, which is how lakes.json carries
its own shoreline instead of doubling up on ways.json's.

The runtime (scripts/osmdataset) filters ways by tag as needed; no tag-based
splitting happens here.
"""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_SOURCE = "ways.osm"


def convert(src: Path, dst: Path) -> None:
    tree = ET.parse(src)
    root = tree.getroot()

    bounds = {}
    nodes = {}
    ways = []
    relations = []

    for elem in root:
        tag = elem.tag
        if tag == "bounds":
            bounds = {k: float(elem.get(k))
                      for k in ("minlon", "minlat", "maxlon", "maxlat")}
        elif tag == "node":
            nodes[elem.get("id")] = [float(elem.get("lon")), float(elem.get("lat"))]
        elif tag == "way":
            refs, way_tags = [], {}
            for child in elem:
                if child.tag == "nd":
                    refs.append(child.get("ref"))
                elif child.tag == "tag":
                    way_tags[child.get("k")] = child.get("v")
            ways.append({"id": elem.get("id"), "nd": refs, "tags": way_tags})
        elif tag == "relation":
            members, rel_tags = [], {}
            for child in elem:
                if child.tag == "member":
                    members.append({"type": child.get("type"),
                                    "ref": child.get("ref"),
                                    "role": child.get("role")})
                elif child.tag == "tag":
                    rel_tags[child.get("k")] = child.get("v")
            relations.append({"id": elem.get("id"), "members": members, "tags": rel_tags})

    print(f"{src.name}: total ways: {len(ways)}, nodes: {len(nodes)}, "
          f"relations: {len(relations)}, bounds: {bounds}")

    dst.write_text(json.dumps({"bounds": bounds, "nodes": nodes, "ways": ways,
                               "relations": relations},
                              separators=(",", ":")) + "\n")
    print(f"{src.name}: written {dst} ({dst.stat().st_size / 1e6:.2f} MB)")


def main(argv: list[str]) -> int:
    if argv and argv[0] == "--all":
        sources = sorted(HERE.glob("*.osm"))
        if not sources:
            print("no .osm in", HERE)
            return 1
    elif argv:
        sources = [Path(a).resolve() for a in argv]
    else:
        sources = [HERE / DEFAULT_SOURCE]

    for src in sources:
        if not src.is_file():
            print(f"{src}: no such file")
            return 1
        convert(src, src.with_suffix(".json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))