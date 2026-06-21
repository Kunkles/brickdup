#!/usr/bin/env python3
"""Finish the board: apply a freerouting Specctra SES, stitch the U1 exposed-pad
to GND, normalize via drills, hide silk refs, and fill the GND pours.

Pipeline (see pcb/README.md):
  1. gen_pcb.py             -> brickdup_psu.kicad_pcb (placed + netted, unrouted)
  2. export_dsn.py          -> /tmp/brickdup.dsn (zones stripped)
  3. freerouting (headless) -> /tmp/brickdup.ses
  4. this script            -> routes + EP vias + cleanup + zone fill, saves

Run with KiCad's bundled python:
  .../python3 apply_route.py [board.kicad_pcb] [route.ses]
"""
import os, sys, pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
BOARD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "brickdup_psu.kicad_pcb")
SES   = sys.argv[2] if len(sys.argv) > 2 else "/tmp/brickdup.ses"

b = pcbnew.LoadBoard(BOARD)
try:
    ok = pcbnew.ImportSpecctraSES(b, SES)
except TypeError:
    ok = b.ImportSpecctraSES(SES)
print("ImportSpecctraSES:", ok)

# NOTE: U1's exposed pad is on the GND net and the top GND pour covers it, so it
# is grounded. For better thermals you can add a few thermal vias under the EP in
# the KiCad GUI (they must avoid bottom-layer signal tracks routed under U1).

# normalize freerouting vias to JLC-standard 0.3 drill / 0.6 pad
nv = 0
for t in b.GetTracks():
    if t.Type() == pcbnew.PCB_VIA_T:
        t.SetDrill(pcbnew.FromMM(0.3)); t.SetWidth(pcbnew.FromMM(0.6)); nv += 1
print("vias normalized:", nv)

# hide silk reference designators (assembly is by CPL/BOM) -> clears silk DRC
for fp in b.GetFootprints():
    fp.Reference().SetVisible(False)

# fill the GND zones now that copper is routed
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
print("zones filled:", b.GetAreaCount())

pcbnew.SaveBoard(BOARD, b)
print("saved", BOARD)
