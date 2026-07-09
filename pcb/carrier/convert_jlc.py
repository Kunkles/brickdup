#!/usr/bin/env python3
"""Convert the kicad-cli CPL + bom.csv into JLCPCB-ready upload CSVs.

  CPL: Ref,Val,Package,PosX,PosY,Rot,Side  ->  Designator,Mid X,Mid Y,Layer,Rotation
  BOM: bom.csv (with LCSC codes)           ->  Comment,Designator,Footprint,LCSC Part #

DNP parts and bare-copper JP1 are excluded. HDRA/HDRB (THT sockets) are
INCLUDED — their LCSC code is picked interactively in JLC's BOM matcher
(search "2.54 1x18 female header", plastic height 8.5mm, NOT low-profile).

  1) kicad-cli pcb export pos brickdup_carrier.kicad_pcb -o fab/brickdup_carrier-cpl.csv --format csv --units mm
  2) python3 convert_jlc.py
"""
import csv, os
HERE = os.path.dirname(os.path.abspath(__file__))
EXCLUDE = {"JP1", "Cout3", "REN2", "BRK1", "BRK2", "BRK3"}

src = os.path.join(HERE, "fab", "brickdup_carrier-cpl.csv")
out = os.path.join(HERE, "fab", "jlc_cpl.csv")
rows = list(csv.DictReader(open(src)))
with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
    kept = 0
    for r in rows:
        if r["Ref"] in EXCLUDE:
            continue
        w.writerow([r["Ref"], f'{float(r["PosX"]):.4f}', f'{float(r["PosY"]):.4f}',
                    r["Side"].capitalize(), f'{float(r["Rot"]):.2f}'])
        kept += 1
print("wrote", out, f"({kept} placements; excluded {sorted(EXCLUDE)})")

src = os.path.join(HERE, "bom.csv")
out = os.path.join(HERE, "fab", "jlc_bom.csv")
n = 0
with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["Comment", "Designator", "Footprint", "LCSC Part #"])
    for r in csv.DictReader(open(src)):
        des = r["Designator"].strip()
        if des in EXCLUDE:
            continue
        w.writerow([r["Comment"], des, r["Footprint"], r["LCSC Part #"]])
        n += 1
print("wrote", out, f"({n} lines; sockets HDRA/HDRB = pick code in JLC matcher)")
