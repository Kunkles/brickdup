#!/usr/bin/env python3
"""Convert the kicad-cli CPL + the hand BOM into JLCPCB-ready CSVs.

  CPL: Ref,Val,Package,PosX,PosY,Rot,Side  ->  Designator,Mid X,Mid Y,Layer,Rotation
  BOM: pcb/bom.csv (with LCSC codes)       ->  Comment,Designator,Footprint,LCSC Part #
        (DNP parts excluded so JLC doesn't place them)

  python3 convert_jlc.py
"""
import csv, os
HERE = os.path.dirname(os.path.abspath(__file__))
DNP = {"Cff", "Cout3", "REN2"}

# --- CPL ---
src = os.path.join(HERE, "fab", "brickdup_psu-cpl.csv")
out = os.path.join(HERE, "fab", "jlc_cpl.csv")
rows = list(csv.DictReader(open(src)))
with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
    kept = 0
    for r in rows:
        if r["Ref"] in DNP:
            continue
        w.writerow([r["Ref"], f'{float(r["PosX"]):.4f}', f'{float(r["PosY"]):.4f}',
                    r["Side"], f'{float(r["Rot"]):.2f}'])
        kept += 1
print("wrote", out, f"({kept} placements; DNP excluded)")

# --- BOM ---
src = os.path.join(HERE, "bom.csv")
out = os.path.join(HERE, "fab", "jlc_bom.csv")
n = 0
with open(out, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["Comment", "Designator", "Footprint", "LCSC Part #"])
    for r in csv.DictReader(open(src)):
        des = r["Designator"].strip()
        if des in DNP:
            continue
        w.writerow([r["Comment"], des, r["Footprint"], r["LCSC Part #"]])
        n += 1
print("wrote", out, f"({n} populated lines; DNP {sorted(DNP)} excluded)")
