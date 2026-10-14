# Builds FreshFixes/Modules/MapData.lua from Blizzard's own DB2 tables for the
# WoW Forever build (CSV exports from wago.tools). Re-run after a game patch:
#   python gen.py <csv dir> <output lua> <build>
import csv, sys, collections, math

src, out, build = sys.argv[1], sys.argv[2], sys.argv[3]

def rows(name):
    return list(csv.DictReader(open(f"{src}/{name}.csv", encoding="utf-8")))

# ---------------------------------------------------------------- reveal
tiles = collections.defaultdict(list)
for t in rows("WorldMapOverlayTile"):
    if t["LayerIndex"] == "0":
        tiles[t["WorldMapOverlayID"]].append((int(t["RowIndex"]), int(t["ColIndex"]), int(t["FileDataID"])))

art = collections.defaultdict(list)
skipped = 0
for o in rows("WorldMapOverlay"):
    if o["PlayerConditionID"] != "0":
        skipped += 1          # phase/quest specific overlays: let Blizzard decide
        continue
    ts = sorted(tiles.get(o["ID"], []))
    if not ts:
        continue
    ids = ",".join(str(fid) for _, _, fid in ts)
    art[int(o["UiMapArtID"])].append(f'{o["TextureWidth"]}:{o["TextureHeight"]}:{o["OffsetX"]}:{o["OffsetY"]}={ids}')

# ---------------------------------------------------------------- icons
icons = []
for n in rows("TaxiNodes"):
    flags = int(n["Flags"])
    if flags & 3 == 0:
        continue              # not shown on either faction's map
    a, h = int(n["MountCreatureID_0"]) != 0, int(n["MountCreatureID_1"]) != 0
    kind = "FlightN" if (a and h) or (flags & 3) == 3 else ("FlightA" if flags & 1 else "FlightH")
    icons.append((kind, int(n["ContinentID"]), float(n["Pos_0"]), float(n["Pos_1"]), n["Name_lang"], "Flight point"))

# Instance entrances come from Leatrix's hand-placed list (import_leatrix_icons.py),
# which also covers Forever's new instances. Set INSTANCES = True to emit Blizzard's corpse points instead.
INSTANCES = False
for m in (rows("Map") if INSTANCES else []):
    if m["InstanceType"] in ("1", "2") and m["CorpseMapID"] not in ("-1", "") and (float(m["Corpse_0"]) or float(m["Corpse_1"])):
        name = m["MapName_lang"]
        if name.startswith("<"):
            continue
        kind = "Raid" if m["InstanceType"] == "2" else "Dungeon"
        icons.append((kind, int(m["CorpseMapID"]), float(m["Corpse_0"]), float(m["Corpse_1"]), name, kind))

def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write("local _, FF = ...\n\n")
    f.write(f"-- Generated from Blizzard DB2 tables (WorldMapOverlay, WorldMapOverlayTile,\n")
    f.write(f"-- TaxiNodes, Map) for build {build}. Do not edit by hand - re-run gen.py.\n\n")
    f.write("-- [uiMapArtID] = \"width:height:offsetX:offsetY=fileID,fileID,...;...\" (tiles row by row)\n")
    f.write("FF.MapReveal = {\n")
    for a in sorted(art):
        f.write(f"    [{a}] = {q(';'.join(art[a]))},\n")
    f.write("}\n\n")
    f.write("-- { kind, continentID, worldX, worldY, name, description }\n")
    f.write("FF.MapIcons = {\n")
    for k, c, x, y, name, desc in icons:
        f.write(f"    {{ {q(k)}, {c}, {x:.1f}, {y:.1f}, {q(name)}, {q(desc)} }},\n")
    f.write("}\n")

print(f"maps with reveal data: {len(art)}, overlays: {sum(len(v) for v in art.values())}, "
      f"skipped (conditional): {skipped}, icons: {len(icons)}")
