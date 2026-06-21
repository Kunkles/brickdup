#!/usr/bin/env python3
"""Generate brickdup_psu.kicad_pcb: 32x18 outline + M2 holes + a first
placement pass with all footprints netted, plus GND pours on both layers.

Reuses component/net data from gen_kicad.py so the board stays in sync with the
schematic. Components are placed but NOT routed — open in the KiCad GUI, tidy the
placement, and route per pcb/README.md sec 5.

Run with KiCad's bundled python:
  /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3 gen_pcb.py
"""
import os, pcbnew
import gen_kicad as g

HERE  = os.path.dirname(os.path.abspath(__file__))
OUT   = os.path.join(HERE, "brickdup_psu.kicad_pcb")
FPDIR = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
MHDIR = FPDIR + "/MountingHole.pretty"
W, H = 32.0, 18.0
HOLES = [(4.0, 9.0), (28.0, 9.0)]

# First-pass placement: ref -> (x_mm, y_mm, rotation_deg). Power chain across the
# middle; FB divider by U1; sense divider isolated in the west corner near J2.
# NOTE: rough first-pass placement only (arrange + route in the GUI). On a 32x18
# board the JST bodies + parts leave little slack, so courtyards still overlap;
# this just gets every part on-board, netted, and grouped by function.
PLACE = {
    # west: sense + FB dividers, enable, J2 out (north edge)
    "R1":   (2.5, 9, 90), "R2": (2.5, 12.5, 90), "C1": (5.5, 12.5, 90),
    "RFB1": (8.5, 8, 90), "RFB2": (8.5, 11.5, 90), "Cff": (8.5, 15, 90),
    "REN1": (5.5, 5, 90), "REN2": (8.5, 5, 90),
    "J2":   (6, 2.5, 0),     # 5V/SENSE/GND out, mouth faces north edge (toward Heltec)
    # centre: regulator + output
    "U1":   (14, 10, 0),
    "Cbst": (11.5, 5, 90), "RDIM": (14, 5, 90),
    "L1":   (19, 6, 0),
    "Cout1":(17.5, 14.5, 0), "Cout2":(20.5, 14.5, 0), "Cout3":(23.5, 14.5, 0),
    # east: input caps, diodes, input connector
    "Cin3": (23, 6, 90),
    "D1":   (24, 11, 0),
    "Cin1": (27.5, 5.5, 90), "Cin2": (27.5, 11, 90),
    "D2":   (30.5, 5.5, 90),
    "J1":   (28.5, 13, 270), # VBAT/GND in, mouth faces east edge (toward LEMO)
}

def mm(v): return pcbnew.FromMM(v)

b = pcbnew.CreateEmptyBoard()
b.SetCopperLayerCount(2)

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

# --- footprints (placed + netted) ---
def load_fp(fpid):
    lib, name = fpid.split(":")
    return pcbnew.FootprintLoad(f"{FPDIR}/{lib}.pretty", name)

for ref, (lib_id, val, fpid, _pos, dnp) in g.COMPS.items():
    fp = load_fp(fpid)
    if fp is None:
        raise SystemExit(f"footprint not found: {fpid}")
    x, y, rot = PLACE[ref]
    fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
    if rot:
        fp.SetOrientationDegrees(rot)
    fp.SetReference(ref)
    fp.SetValue(val)
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
