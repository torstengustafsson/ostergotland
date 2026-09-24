#!/usr/bin/env python3
"""Convert ways.osm (XML) into a single compact JSON file for use in Godot.

- ways.json: every element that has geometry usable by the runtime loader:
    bounds   - the download bbox as floats
    nodes    - all nodes: { id (string): [lon, lat] }
    ways     - all ways:  [{ id (string), nd: [node id strings], tags: {...} }]
    relations - all relations: [{ id, members: [{type, ref, role}], tags }]

Node ids are kept as strings since JSON object keys are strings anyway.
The runtime side (scripts/osm_dataset) filters ways by tag as needed; no
tag-based splitting happens here anymore.
"""
import json
import xml.etree.ElementTree as ET
from pathlib import Path

SRC = Path(__file__).resolve().parent / "ways.osm"
DST = SRC.with_name("ways.json")


def save(data: dict, dst: Path, label: str) -> None:
    dst.write_text(json.dumps(data, separators=(",", ":")))
    print(f"{label}: written {dst} ({dst.stat().st_size / 1e6:.2f} MB)")


def main():
    tree = ET.parse(SRC)
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

    print(f"total ways: {len(ways)}, nodes: {len(nodes)}, "
          f"relations: {len(relations)}, bounds: {bounds}")

    save({"bounds": bounds, "nodes": nodes, "ways": ways, "relations": relations}, DST,
         f"{len(ways)} ways, {len(nodes)} nodes, {len(relations)} relations")


if __name__ == "__main__":
    main()