#!/usr/bin/env python3
"""Electrical-layout rule asserts for brickdup_carrier — the v0.1 README's
buck layout rules, encoded as hard failures instead of prose.

Born from a real regression: the placement solver (which optimizes overlap,
not net length) once scattered the SW node across ~23mm before it was caught
by eye. These rules make that class of mistake impossible to regenerate.

Usage:
  standalone:  .../python3 check_layout.py [board.kicad_pcb]
  in-pipeline: gen_pcb.py imports and calls check(board) before saving.
"""
import math, os, sys

RULES_DOC = """
  R1  hot loop      : U1.SW, D1 anode, L1 SW-pad pairwise <= 10mm
  R2  bootstrap     : Cbst's BST pad within 3.5mm of U1's BST pin
  R3  sense divider : R1/R2/C1 all >= 10mm from every SW-node pad
  R4  input HF cap  : Cin3's VBAT pad within 6mm of U1's VIN pin
"""

def _mm(v): return v / 1e6

def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])

def check(board):
    import pcbnew  # noqa: F401  (caller already has it loaded)
    pad_pos = {}     # (ref, padnum) -> (x, y)
    pad_net = {}     # (ref, padnum) -> netname
    centers = {}     # ref -> (x, y)
    for f in board.GetFootprints():
        ref = f.GetReference()
        centers[ref] = (_mm(f.GetPosition().x), _mm(f.GetPosition().y))
        for p in f.Pads():
            key = (ref, p.GetNumber())
            pad_pos[key] = (_mm(p.GetPosition().x), _mm(p.GetPosition().y))
            pad_net[key] = p.GetNetname()

    fails = []

    # R1: hot loop — the SW power triangle stays tight
    tri = [("U1", "5"), ("D1", "1"), ("L1", "1")]
    for k in tri:
        assert pad_net.get(k) == "SW", f"{k} expected on SW net (got {pad_net.get(k)})"
    worst = 0.0
    for i in range(len(tri)):
        for j in range(i + 1, len(tri)):
            d = _dist(pad_pos[tri[i]], pad_pos[tri[j]])
            worst = max(worst, d)
    if worst > 10.0:
        fails.append(f"R1 hot loop: SW triangle max leg {worst:.1f}mm > 10mm")
    else:
        print(f"  R1 hot loop: SW triangle max leg {worst:.1f}mm <= 10mm  OK")

    # R2: bootstrap cap hugs the BST pin
    bst_pads = [k for k, n in pad_net.items() if n == "BST"]
    u1_bst = next(k for k in bst_pads if k[0] == "U1")
    cb_bst = next(k for k in bst_pads if k[0] == "Cbst")
    d = _dist(pad_pos[u1_bst], pad_pos[cb_bst])
    if d > 3.5:
        fails.append(f"R2 bootstrap: Cbst BST pad {d:.1f}mm from U1 BST pin > 3.5mm")
    else:
        print(f"  R2 bootstrap: Cbst-to-BST {d:.1f}mm <= 3.5mm  OK")

    # R3: sense divider stays away from the SW node
    sw_pads = [pad_pos[k] for k, n in pad_net.items() if n == "SW"]
    worst_ref, worst_d = None, 1e9
    for ref in ("R1", "R2", "C1"):
        dmin = min(_dist(centers[ref], sp) for sp in sw_pads)
        if dmin < worst_d:
            worst_ref, worst_d = ref, dmin
    if worst_d < 10.0:
        fails.append(f"R3 sense divider: {worst_ref} only {worst_d:.1f}mm from SW node < 10mm")
    else:
        print(f"  R3 sense divider: nearest ({worst_ref}) {worst_d:.1f}mm >= 10mm from SW  OK")

    # R4: HF input cap hugs VIN
    d = _dist(pad_pos[("Cin3", "1")], pad_pos[("U1", "3")])
    if d > 6.0:
        fails.append(f"R4 input HF cap: Cin3 VBAT pad {d:.1f}mm from U1 VIN > 6mm")
    else:
        print(f"  R4 input HF cap: Cin3-to-VIN {d:.1f}mm <= 6mm  OK")

    if fails:
        raise SystemExit("LAYOUT RULE FAILURES:\n  " + "\n  ".join(fails) + "\n" + RULES_DOC)
    print("layout rules: all OK")

if __name__ == "__main__":
    import pcbnew
    HERE = os.path.dirname(os.path.abspath(__file__))
    BOARD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "brickdup_carrier.kicad_pcb")
    check(pcbnew.LoadBoard(BOARD))
