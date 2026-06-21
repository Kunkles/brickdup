#!/usr/bin/env python3
"""Generate brickdup_psu.kicad_pcb: 32x18 outline + M2 holes + a first
placement pass with all footprints netted, plus GND pours on both layers.

Reuses component/net data from gen_kicad.py so the board stays in sync with the
schematic. Components are placed but NOT routed — open in the KiCad GUI, tidy the
placement, and route per pcb/README.md sec 5.

Run with KiCad's bundled python:
  /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3 gen_pcb.py
"""
import os, random, pcbnew
import gen_kicad as g

HERE  = os.path.dirname(os.path.abspath(__file__))
OUT   = os.path.join(HERE, "brickdup_psu.kicad_pcb")
FPDIR = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
MHDIR = FPDIR + "/MountingHole.pretty"
W, H = 40.0, 20.0
HOLES = [(4.0, 4.0), (32.0, 16.0)]   # diagonal-ish; SE hole pulled in to clear J1 (match enclosure psu_holes)

# First-pass placement: ref -> (x_mm, y_mm, rotation_deg). Power chain across the
# middle; FB divider by U1; sense divider isolated in the west corner near J2.
# Rough first-pass placement on the 38x18 board (arrange + route in the GUI).
# Power flows W->E: J1 (VBAT, east edge) -> Cin -> U1 -> L1 -> Cout -> 5V -> J2
# (north-west). Sense divider is isolated in the far west, away from SW.
PLACE = {
    # Hot-loop-aware floorplan. U1 rot 180 -> VIN/BST/FB on its EAST side (toward
    # the J1 input) and SW/GND on its WEST side (toward the output + J2). Goal:
    # tight Cin->VIN and SW->D1->L1 loops; FB + sense kept off the SW node.
    "U1":   (20, 10, 180),
    # INPUT (east, by VIN + J1): HF cap hugs VIN, bulk caps + TVS toward J1
    "Cin3": (24, 9.5, 90),
    "Cin1": (27, 7.5, 90), "Cin2": (27, 12, 90), "D2": (31, 12.5, 0),
    "Cbst": (24, 6.5, 90),                 # near BST (east-top)
    "J1":   (38, 9.5, 270),                # VBAT/GND in -> LEMO (east edge)
    # FB divider near U1.FB (east-bottom), away from SW
    "RFB1": (24.5, 13, 90), "RFB2": (26.5, 13, 90), "Cff": (28.5, 13, 90),
    # OUTPUT (west, off SW): catch diode at SW, inductor, output caps -> J2
    "D1":   (15.5, 7.5, 0),
    "L1":   (11.5, 9.5, 0),
    "Cout1":(8, 12.5, 0), "Cout2":(11, 14, 0), "Cout3":(14, 14, 0),
    "J2":   (8, 2.5, 0),                    # 5V/SENSE/GND out -> Heltec (west-north)
    # enable + dim near U1's west pins
    "REN1": (16, 12.5, 90), "REN2": (18, 13.5, 90),
    # sense divider: taps VBAT (east), routes SENSE to J2; clear of SW (west)
    "R1":   (31, 5, 90), "R2": (33, 5, 90), "C1": (35, 5, 90),
}

def mm(v): return pcbnew.FromMM(v)
def tomm(v): return pcbnew.ToMM(v)

EDGE = 0.6     # keep courtyards this far inside the board edge
GAP  = 0.75    # min gap between pad-unions (clears courtyards too)
HOLE_KO = 2.8  # mounting-hole keepout radius
PIN_EDGE = {"J1": "E", "J2": "N"}   # connectors pinned to a board edge

def load_fp(fpid):
    lib, name = fpid.split(":")
    return pcbnew.FootprintLoad(f"{FPDIR}/{lib}.pretty", name)

def half_extents(fpid, rot):
    """Half-width/height (mm) of the union of all PAD bboxes at this rotation.
    Pad-based (not courtyard) so the solver can't let copper pads overlap, even
    for parts whose mounting/diode pads stick outside the courtyard."""
    fp = load_fp(fpid)
    fp.SetPosition(pcbnew.VECTOR2I(0, 0))
    if rot: fp.SetOrientationDegrees(rot)
    bb = None
    for p in fp.Pads():
        pb = p.GetBoundingBox()
        if bb is None: bb = pb
        else: bb.Merge(pb)
    if bb is None or bb.GetWidth() == 0:
        bb = fp.GetBoundingBox(False, False)
    return tomm(bb.GetWidth()) / 2, tomm(bb.GetHeight()) / 2

def solve_placement():
    """Separate overlapping courtyards starting from the PLACE seeds."""
    P = {r: dict(x=float(x), y=float(y), rot=rot) for r, (x, y, rot) in PLACE.items()}
    for r in P:
        P[r]["hw"], P[r]["hh"] = half_extents(g.COMPS[r][2], P[r]["rot"])
    refs = list(P)
    def clamp(r):
        p = P[r]
        lo_x, hi_x = EDGE + p["hw"], W - EDGE - p["hw"]
        lo_y, hi_y = EDGE + p["hh"], H - EDGE - p["hh"]
        edge = PIN_EDGE.get(r)
        if edge == "E": p["x"] = hi_x
        elif edge == "W": p["x"] = lo_x
        if edge == "N": p["y"] = lo_y
        elif edge == "S": p["y"] = hi_y
        p["x"] = min(max(p["x"], lo_x), hi_x)
        p["y"] = min(max(p["y"], lo_y), hi_y)
    def pinned(r, axis):
        e = PIN_EDGE.get(r)
        return (axis == "x" and e in ("E", "W")) or (axis == "y" and e in ("N", "S"))
    def relax(iters):
        for _ in range(iters):
            for i in range(len(refs)):
                for j in range(i + 1, len(refs)):
                    ra, rc = refs[i], refs[j]
                    a, c = P[ra], P[rc]
                    dx, dy = c["x"] - a["x"], c["y"] - a["y"]
                    ox = (a["hw"] + c["hw"] + GAP) - abs(dx)
                    oy = (a["hh"] + c["hh"] + GAP) - abs(dy)
                    if ox <= 0 or oy <= 0:
                        continue
                    axis = "x" if ox < oy else "y"
                    if pinned(ra, axis) and pinned(rc, axis):
                        axis = "y" if axis == "x" else "x"
                    o = ox if axis == "x" else oy
                    d = dx if axis == "x" else dy
                    sgn = 1 if d >= 0 else -1
                    pa, pc = pinned(ra, axis), pinned(rc, axis)
                    if pa and not pc:   c[axis] += o * sgn
                    elif pc and not pa: a[axis] -= o * sgn
                    else:               a[axis] -= o / 2 * sgn; c[axis] += o / 2 * sgn
            for r in refs:                                  # push out of hole keepouts
                p = P[r]
                for hx, hy in HOLES:
                    dx, dy = p["x"] - hx, p["y"] - hy
                    ox, oy = (p["hw"] + HOLE_KO) - abs(dx), (p["hh"] + HOLE_KO) - abs(dy)
                    if ox > 0 and oy > 0:
                        if ox < oy: p["x"] += ox * (1 if dx >= 0 else -1)
                        else:       p["y"] += oy * (1 if dy >= 0 else -1)
            for r in refs: clamp(r)

    def overlap_score():
        s = 0.0
        for i in range(len(refs)):
            for j in range(i + 1, len(refs)):
                a, c = P[refs[i]], P[refs[j]]
                ox = (a["hw"] + c["hw"] + GAP) - abs(c["x"] - a["x"])
                oy = (a["hh"] + c["hh"] + GAP) - abs(c["y"] - a["y"])
                if ox > 0 and oy > 0:
                    s += ox * oy
        return s

    seeds = {r: (P[r]["x"], P[r]["y"]) for r in refs}
    best, best_score = None, None
    for attempt in range(120):                              # random-restart relaxation
        if attempt == 0:
            for r in refs: P[r]["x"], P[r]["y"] = seeds[r]  # try the functional seeds first
        else:
            random.seed(attempt)
            for r in refs:
                P[r]["x"] = random.uniform(EDGE + P[r]["hw"], W - EDGE - P[r]["hw"])
                P[r]["y"] = random.uniform(EDGE + P[r]["hh"], H - EDGE - P[r]["hh"])
        for r in refs: clamp(r)
        relax(1500)
        sc = overlap_score()
        if best_score is None or sc < best_score:
            best, best_score = {r: dict(P[r]) for r in refs}, sc
        if sc < 1e-6:
            break
    print(f"placement: overlap score {best_score:.3f} after seeded+random restarts")
    return best

b = pcbnew.CreateEmptyBoard()
b.SetCopperLayerCount(2)
b.GetDesignSettings().m_CopperEdgeClearance = pcbnew.FromMM(0.3)  # JLC-safe copper-to-edge

# --- Edge.Cuts rectangle ---
corners = [(0, 0), (W, 0), (W, H), (0, H)]
for i in range(4):
    s = pcbnew.PCB_SHAPE(b); s.SetShape(pcbnew.SHAPE_T_SEGMENT); s.SetLayer(pcbnew.Edge_Cuts)
    s.SetWidth(mm(0.1))
    x1, y1 = corners[i]; x2, y2 = corners[(i + 1) % 4]
    s.SetStart(pcbnew.VECTOR2I(mm(x1), mm(y1))); s.SetEnd(pcbnew.VECTOR2I(mm(x2), mm(y2)))
    b.Add(s)

# --- nets ---
netmap = {}
for name in g.NETS:
    ni = pcbnew.NETINFO_ITEM(b, name)
    b.Add(ni); netmap[name] = ni
# (ref,pad) -> net name
pad_net = {}
for name, nodes in g.NETS.items():
    for ref, pin in nodes:
        pad_net[(ref, pin)] = name

# --- footprints (placed via the separation solver + netted) ---
SOLVED = solve_placement()

for ref, (lib_id, val, fpid, _pos, dnp) in g.COMPS.items():
    fp = load_fp(fpid)
    if fp is None:
        raise SystemExit(f"footprint not found: {fpid}")
    s = SOLVED[ref]
    fp.SetPosition(pcbnew.VECTOR2I(mm(s["x"]), mm(s["y"])))
    if s["rot"]:
        fp.SetOrientationDegrees(s["rot"])
    fp.SetReference(ref)
    fp.SetValue(val)
    fp.Value().SetVisible(False)          # cut silk-over-copper; value lives in the BOM
    fp.Reference().SetTextSize(pcbnew.VECTOR2I(mm(0.6), mm(0.6)))
    if dnp:
        try: fp.SetDNP(True)
        except Exception: pass
    for pad in fp.Pads():
        nm = pad_net.get((ref, pad.GetNumber()))
        if nm:
            pad.SetNet(netmap[nm])
    b.Add(fp)

# --- M2 mounting holes ---
for i, (x, y) in enumerate(HOLES):
    fp = pcbnew.FootprintLoad(MHDIR, "MountingHole_2.2mm_M2")
    fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y))); fp.SetReference(f"H{i+1}")
    b.Add(fp)

# --- GND copper pours on both layers (left unfilled; press B in GUI to fill) ---
for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
    z = pcbnew.ZONE(b)
    z.SetLayer(layer)
    z.SetNet(netmap["GND"])
    sps = z.Outline()
    sps.NewOutline()
    for x, y in [(0.3, 0.3), (W - 0.3, 0.3), (W - 0.3, H - 0.3), (0.3, H - 0.3)]:
        sps.Append(mm(x), mm(y))
    b.Add(z)

# silk title
t = pcbnew.PCB_TEXT(b); t.SetText("brickdup_psu v0.1"); t.SetLayer(pcbnew.F_SilkS)
t.SetPosition(pcbnew.VECTOR2I(mm(W / 2), mm(H - 0.8))); t.SetTextSize(pcbnew.VECTOR2I(mm(1), mm(1)))
b.Add(t)

pcbnew.SaveBoard(OUT, b)
print("wrote", OUT, "with", len(g.COMPS), "placed parts and", len(g.NETS), "nets")
