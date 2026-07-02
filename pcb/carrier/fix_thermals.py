#!/usr/bin/env python3
"""Fix starved-thermal DRC errors: read a kicad-cli DRC json, switch each
flagged GND pad to a solid pour connection, refill, save.

  .../python3 fix_thermals.py [board.kicad_pcb] [drc.json]

Run after apply_route.py:
  kicad-cli pcb drc board.kicad_pcb -o /tmp/drc.json --format json --severity-error
  .../python3 fix_thermals.py board.kicad_pcb /tmp/drc.json
  (re-run kicad-cli drc to confirm 0)
"""
import os, sys, re, json, pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
BOARD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "brickdup_carrier.kicad_pcb")
DRC   = sys.argv[2] if len(sys.argv) > 2 else "/tmp/carrier_drc.json"

d = json.load(open(DRC))
starved = set()
for v in d.get("violations", []):
    if v.get("type") != "starved_thermal":
        continue
    for item in v.get("items", []):
        m = re.search(r"Pad (\S+) \[(\S+)\] of (\S+)", item.get("description", ""))
        if m:
            starved.add((m.group(3), m.group(1)))

if not starved:
    print("no starved-thermal pads in", DRC)
    sys.exit(0)

print("starved pads -> solid zone connection:", sorted(starved))
b = pcbnew.LoadBoard(BOARD)
hit = 0
for fp in b.GetFootprints():
    for p in fp.Pads():
        if (fp.GetReference(), p.GetNumber()) in starved:
            p.SetLocalZoneConnection(pcbnew.ZONE_CONNECTION_FULL)
            hit += 1
print("pads updated:", hit)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(BOARD, b)
print("refilled + saved", BOARD)
