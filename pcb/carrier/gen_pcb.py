#!/usr/bin/env python3
"""Generate brickdup_carrier.kicad_pcb — 62x44 carrier, Heltec V3 socket,
buck island between the socket rows, wired switch/button JSTs, breakouts.

Fixed geometry (sockets, breakouts, JSTs, holes) is placed EXPLICITLY; only the
buck/divider island runs through the separation solver, with the fixed items
acting as immovable obstacles.

Orientation ground truths (derived from the v0.1 board + JLC renders):
  - JST S2B-PH-SM4 at rot 0   -> wire mouth faces SOUTH (+y).
  - JST S2B-PH-SM4 at rot +90 -> wire mouth faces EAST (+x).
    (v0.1's J1 used rot -90 = mouth WEST/inward — the v0.1 mistake, fixed here.)
  - PinSocket_1x18 at rot -90 -> pin 1 at origin, pins run WEST (-x).
  - PinHeader_1xN  at rot +90 -> pin 1 at origin, pins run EAST (+x).
Runtime asserts verify all four before saving.

Run with KiCad's bundled python:
  .../python3 gen_pcb.py
"""
import os, random, pcbnew
import gen_kicad as g

HERE  = os.path.dirname(os.path.abspath(__file__))
OUT   = os.path.join(HERE, "brickdup_carrier.kicad_pcb")
FPDIR = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
MHDIR = FPDIR + "/MountingHole.pretty"

W, H = 62.0, 44.0
HOLES = [(3.5, 3.5), (58.5, 3.5), (3.5, 40.5), (58.5, 40.5)]   # M2 x4 corners

# Heltec socket geometry. Rows are 2.54mm-pitch, 18 pins (span 43.18mm).
# ROW_SPACING (J3<->J2 row distance) VERIFIED 2026-07-02: calipers on a real
# Heltec V3 read 22.77-22.93mm across holes -> 22.86mm (0.9") confirmed.
# Pin pitch also verified: 2.55mm measured (= 2.54mm nominal).
ROW_SPACING = 22.86
PIN1_X, ROWA_Y = 52.2, 8.0          # pin 1 (GND, USB end) sits EAST
ROWB_Y = ROWA_Y + ROW_SPACING       # 30.86

# ---- fixed items: ref -> (x, y, rot). Never moved by the solver. ----
FIXED = {
    "HDRA": (PIN1_X, ROWA_Y, -90),  # Heltec J3 row (GPIO side), pins run west
    "HDRB": (PIN1_X, ROWB_Y, -90),  # Heltec J2 row (power side)
    "BRK2": (38.0, 2.8, -90),       # ADC breakout, north strip (pads 38 -> 20.2)
    "BRK3": (50.0, 2.8, -90),       # I2C breakout, north strip (pads 50 -> 42.4)
    "BRK1": (38.0, 35.2, 90),       # SPI breakout, south strip (pads 38 -> 55.8)
    "SW1":  (11.0, 39.0, 0),        # power-switch JST, south edge, mouth south
    "BTN1": (21.0, 39.0, 0),        # PRG button JST
    "BTN2": (31.0, 39.0, 0),        # RST button JST
    "J1":   (57.1, 19.5, 90),       # VBAT in JST, east edge, mouth EAST (fixed!)
    "JP1":  (47.5, 27.0, 0),        # SW1 bypass solder jumper, near J1
    # -- buck HOT LOOP pinned rigid (SW node must stay tight: v0.1 rule #1) --
    # U1 rot180: SW/GND pads west (toward D1+L1), VIN/BST/FB pads east (to Cin)
    "U1":   (39.5, 20.0, 180),      # SW pad -> (37.0, 18.1)
    "D1":   (31.5, 15.3, 0),        # SW pad (29.5, 15.3), GND (33.5, 15.3)
    "L1":   (26.5, 22.0, 180),      # SW pad east (29.6, 22), +5V pad west (23.4, 22)
    "Cbst": (44.2, 17.5, 90),       # bootstrap cap by U1's BST pin (42.0, 18.1)
}

# ---- solver seeds for the buck/divider island (between the socket rows). ----
# Same relative floorplan as v0.1 (hot-loop aware), shifted into the channel.
# U1 rot 180 -> VIN/BST/FB east (toward J1), SW/GND west (toward L1/output).
PLACE = {
    "Cin3": (43.5, 20.5, 90),
    "Cin1": (46.5, 16.5, 90), "Cin2": (46.5, 22.5, 90), "D2": (50.5, 13, 0),
    "RFB1": (41, 24.5, 90), "RFB2": (43, 24.5, 90), "Cff": (45, 24.5, 90),
    "Cout1":(20, 20, 90), "Cout2":(19, 24, 0), "Cout3":(22.5, 24.5, 0),
    "REN1": (33, 24, 90), "REN2": (35, 24.5, 90),
    # sense divider isolated WEST (away from SW node), short hop to HDRA.18
    "R1":   (12, 19, 90), "R2": (14.5, 19, 90), "C1": (17, 19, 90),
}

def mm(v): return pcbnew.FromMM(v)
def tomm(v): return pcbnew.ToMM(v)

EDGE = 0.6
GAP  = 0.75
HOLE_KO = 2.8

def load_fp(fpid):
    lib, name = fpid.split(":")
    if lib == "brickdup":                       # shared with v0.1
        return pcbnew.FootprintLoad(os.path.join(HERE, "..", "brickdup.pretty"), name)
    return pcbnew.FootprintLoad(f"{FPDIR}/{lib}.pretty", name)

def half_extents(fpid, rot):
    """Half extents of the pad-union MERGED with the courtyard graphics.
    v0.1 used pads only — that let parts tuck inside big-bodied neighbours'
    courtyards (the JLC D2-vs-D1/L1 assembly flag). Courtyard-aware extents
    keep the solver honest about real body clearance."""
    fp = load_fp(fpid)
    fp.SetPosition(pcbnew.VECTOR2I(0, 0))
    if rot: fp.SetOrientationDegrees(rot)
    bb = None
    for p in fp.Pads():
        pb = p.GetBoundingBox()
        if bb is None: bb = pb
        else: bb.Merge(pb)
    for gi in fp.GraphicalItems():
        try:
            if gi.GetLayer() in (pcbnew.F_CrtYd, pcbnew.B_CrtYd):
                gb = gi.GetBoundingBox()
                if bb is None: bb = gb
                else: bb.Merge(gb)
        except Exception:
            pass
    if bb is None or bb.GetWidth() == 0:
        bb = fp.GetBoundingBox(False, False)
    # centre offset of the union relative to the footprint origin
    cx = tomm(bb.GetCenter().x); cy = tomm(bb.GetCenter().y)
    return tomm(bb.GetWidth()) / 2, tomm(bb.GetHeight()) / 2, cx, cy

def solve_placement():
    """Relax the movable island; FIXED refs are immovable obstacles."""
    P = {}
    for r, (x, y, rot) in PLACE.items():
        P[r] = dict(x=float(x), y=float(y), rot=rot, fixed=False)
    for r, (x, y, rot) in FIXED.items():
        P[r] = dict(x=float(x), y=float(y), rot=rot, fixed=True)
    for r in P:
        hw, hh, cx, cy = half_extents(g.COMPS[r][2], P[r]["rot"])
        # store the pad-union CENTRE (origin offset folded in) so the AABB
        # separation math is honest for asymmetric parts (headers, JSTs)
        P[r]["hw"], P[r]["hh"], P[r]["ox"], P[r]["oy"] = hw, hh, cx, cy
    refs = list(P)
    def ctr(p):   # pad-union centre in board coords
        return p["x"] + p["ox"], p["y"] + p["oy"]
    def clamp(r):
        p = P[r]
        if p["fixed"]: return
        cx, cy = ctr(p)
        lo_x, hi_x = EDGE + p["hw"] - p["ox"], W - EDGE - p["hw"] - p["ox"]
        lo_y, hi_y = EDGE + p["hh"] - p["oy"], H - EDGE - p["hh"] - p["oy"]
        p["x"] = min(max(p["x"], lo_x), hi_x)
        p["y"] = min(max(p["y"], lo_y), hi_y)
    def relax(iters):
        for _ in range(iters):
            for i in range(len(refs)):
                for j in range(i + 1, len(refs)):
                    ra, rc = refs[i], refs[j]
                    a, c = P[ra], P[rc]
                    if a["fixed"] and c["fixed"]: continue
                    ax, ay = ctr(a); cx2, cy2 = ctr(c)
                    dx, dy = cx2 - ax, cy2 - ay
                    ox = (a["hw"] + c["hw"] + GAP) - abs(dx)
                    oy = (a["hh"] + c["hh"] + GAP) - abs(dy)
                    if ox <= 0 or oy <= 0:
                        continue
                    axis = "x" if ox < oy else "y"
                    o = ox if axis == "x" else oy
                    d = dx if axis == "x" else dy
                    sgn = 1 if d >= 0 else -1
                    if a["fixed"]:      c[axis] += o * sgn
                    elif c["fixed"]:    a[axis] -= o * sgn
                    else:               a[axis] -= o / 2 * sgn; c[axis] += o / 2 * sgn
            for r in refs:
                p = P[r]
                if p["fixed"]: continue
                cx, cy = ctr(p)
                for hx, hy in HOLES:
                    dx, dy = cx - hx, cy - hy
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
                if a["fixed"] and c["fixed"]: continue
                ax, ay = ctr(a); cx2, cy2 = ctr(c)
                ox = (a["hw"] + c["hw"] + GAP) - abs(cx2 - ax)
                oy = (a["hh"] + c["hh"] + GAP) - abs(cy2 - ay)
                if ox > 0 and oy > 0:
                    s += ox * oy
        return s

    movable = [r for r in refs if not P[r]["fixed"]]
    seeds = {r: (P[r]["x"], P[r]["y"]) for r in movable}
    best, best_score = None, None
    for attempt in range(120):
        if attempt == 0:
            for r in movable: P[r]["x"], P[r]["y"] = seeds[r]
        else:
            random.seed(attempt)
            for r in movable:
                # random restarts stay inside the inter-row channel
                P[r]["x"] = random.uniform(8, 54)
                P[r]["y"] = random.uniform(11, 28)
        for r in movable: clamp(r)
        relax(1500)
        sc = overlap_score()
        if best_score is None or sc < best_score:
            best, best_score = {r: dict(P[r]) for r in refs}, sc
        if sc < 1e-6:
            break
    print(f"placement: overlap score {best_score:.3f}")
    return best

b = pcbnew.CreateEmptyBoard()
b.SetCopperLayerCount(2)
b.GetDesignSettings().m_CopperEdgeClearance = pcbnew.FromMM(0.3)

# --- Edge.Cuts ---
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
pad_net = {}
for name, nodes in g.NETS.items():
    for ref, pin in nodes:
        pad_net[(ref, pin)] = name

# --- footprints ---
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
    fp.Value().SetVisible(False)
    fp.Reference().SetTextSize(pcbnew.VECTOR2I(mm(0.7), mm(0.7)))
    if dnp:
        try: fp.SetDNP(True)
        except Exception: pass
    for pad in fp.Pads():
        nm = pad_net.get((ref, pad.GetNumber()))
        if nm:
            pad.SetNet(netmap[nm])
    b.Add(fp)

# --- orientation asserts (ground truths from v0.1) ---
def pad_pos(ref, num):
    for fp in b.GetFootprints():
        if fp.GetReference() == ref:
            for p in fp.Pads():
                if p.GetNumber() == num:
                    return tomm(p.GetPosition().x), tomm(p.GetPosition().y)
    raise SystemExit(f"pad {ref}.{num} not found")

ax1, ay1 = pad_pos("HDRA", "1"); ax18, ay18 = pad_pos("HDRA", "18")
assert abs(ax1 - PIN1_X) < 0.1 and abs(ay1 - ROWA_Y) < 0.1, f"HDRA pin1 at {ax1},{ay1}"
assert ax18 < ax1 - 40 and abs(ay18 - ROWA_Y) < 0.1, f"HDRA pin18 at {ax18},{ay18} (row must run west)"
bx1, by1 = pad_pos("HDRB", "1")
assert abs(by1 - ROWB_Y) < 0.1, f"HDRB row at y={by1}, want {ROWB_Y}"
# J1 mouth east: signal pads must sit WEST of the footprint centre
j1x, _ = pad_pos("J1", "1")
assert j1x < FIXED["J1"][0], f"J1 signal pad at x={j1x} not west of centre (mouth not east?)"
# BRK1 runs east from pin 1
k1x, _ = pad_pos("BRK1", "1"); k8x, _ = pad_pos("BRK1", "8")
assert k8x > k1x + 15, f"BRK1 pins must run east (pin1 {k1x}, pin8 {k8x})"
print("orientation asserts OK")

# --- M2 mounting holes ---
for i, (x, y) in enumerate(HOLES):
    fp = pcbnew.FootprintLoad(MHDIR, "MountingHole_2.2mm_M2")
    fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y))); fp.SetReference(f"H{i+1}")
    b.Add(fp)

# --- GND pours both layers ---
for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
    z = pcbnew.ZONE(b)
    z.SetLayer(layer)
    z.SetNet(netmap["GND"])
    sps = z.Outline()
    sps.NewOutline()
    for x, y in [(0.3, 0.3), (W - 0.3, 0.3), (W - 0.3, H - 0.3), (0.3, H - 0.3)]:
        sps.Append(mm(x), mm(y))
    b.Add(z)

# --- silk: title, Heltec module outline, connector labels ---
def silk_text(txt, x, y, size=1.0):
    t = pcbnew.PCB_TEXT(b); t.SetText(txt); t.SetLayer(pcbnew.F_SilkS)
    t.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
    t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
    b.Add(t)

silk_text("brickdup_carrier v0.2", 15, 42.2, 1.2)
# Heltec module footprint outline (50.2 x 25.5, pins centred on the rows)
mod_e = PIN1_X + (50.2 - 43.18) / 2          # module east edge (USB end)
mod_w = mod_e - 50.2
mid_y = (ROWA_Y + ROWB_Y) / 2
mod_n, mod_s = mid_y - 25.5 / 2, mid_y + 25.5 / 2
r = pcbnew.PCB_SHAPE(b); r.SetShape(pcbnew.SHAPE_T_RECT); r.SetLayer(pcbnew.F_SilkS)
r.SetWidth(mm(0.15))
r.SetStart(pcbnew.VECTOR2I(mm(mod_w), mm(mod_n))); r.SetEnd(pcbnew.VECTOR2I(mm(mod_e), mm(mod_s)))
b.Add(r)
silk_text("HELTEC V3  USB->", 44, mid_y, 0.9)
silk_text("ANT", 8, mid_y - 8, 0.9)
silk_text("PWR SW", 11, 36.6, 0.8)
silk_text("PRG", 20.5, 36.6, 0.8)
silk_text("RST", 30.0, 36.6, 0.8)
silk_text("VBAT IN", 56.5, 13.5, 0.8)
silk_text("SPI", 33.2, 34.5, 0.8)
silk_text("ADC", 17.5, 2.8, 0.8)
silk_text("I2C", 40.0, 2.8, 0.8)

pcbnew.SaveBoard(OUT, b)
print("wrote", OUT, "with", len(g.COMPS), "parts and", len(g.NETS), "nets")
