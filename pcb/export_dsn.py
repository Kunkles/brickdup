#!/usr/bin/env python3
"""Export a Specctra DSN for freerouting, with the GND zones stripped so the
router treats GND as a normal net and routes it with traces (avoids top-pour
island problems). The zones are re-added by apply_route.py after import.

  .../python3 export_dsn.py [board.kicad_pcb] [out.dsn]
"""
import os, sys, pcbnew
HERE = os.path.dirname(os.path.abspath(__file__))
BOARD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "brickdup_psu.kicad_pcb")
DSN   = sys.argv[2] if len(sys.argv) > 2 else "/tmp/brickdup.dsn"
b = pcbnew.LoadBoard(BOARD)
for z in list(b.Zones()):
    b.Remove(z)
pcbnew.ExportSpecctraDSN(b, DSN)
print("DSN exported (zones stripped):", DSN)
