#!/usr/bin/env python3
"""Finish the carrier board: apply the freerouting SES, normalize vias, hide
passive refs (keep connector/socket refs — people plug into this board), fill
GND pours.

  .../python3 apply_route.py [board.kicad_pcb] [route.ses]
"""
import os, sys, pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
BOARD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "brickdup_carrier.kicad_pcb")
SES   = sys.argv[2] if len(sys.argv) > 2 else "/tmp/carrier.ses"

KEEP_REFS = {"J1", "SW1", "BTN1", "BTN2", "JP1", "BRK1", "BRK2", "BRK3", "HDRA", "HDRB"}

b = pcbnew.LoadBoard(BOARD)
try:
    ok = pcbnew.ImportSpecctraSES(b, SES)
except TypeError:
    ok = b.ImportSpecctraSES(SES)
print("ImportSpecctraSES:", ok)

nv = 0
for t in b.GetTracks():
    if t.Type() == pcbnew.PCB_VIA_T:
        t.SetDrill(pcbnew.FromMM(0.3)); t.SetWidth(pcbnew.FromMM(0.6)); nv += 1
print("vias normalized:", nv)

for fp in b.GetFootprints():
    fp.Reference().SetVisible(fp.GetReference() in KEEP_REFS)

# connector GND pads: solid zone connection (no thermal spokes to starve, and
# mechanically stronger for parts that get plugged/unplugged)
for fp in b.GetFootprints():
    if fp.GetReference() in KEEP_REFS:
        for p in fp.Pads():
            if p.GetNetname() == "GND":
                p.SetLocalZoneConnection(pcbnew.ZONE_CONNECTION_FULL)

for z in b.Zones():
    try: z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    except Exception: pass
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
print("zones filled")

# NOTE: starved-thermal DRC errors (routing crowding a GND pad's spokes) are
# fixed by fix_thermals.py, driven by kicad-cli's DRC json — WriteDRCReport
# crashes in standalone pcbnew python, so the loop lives at pipeline level.

pcbnew.SaveBoard(BOARD, b)
print("saved", BOARD)
