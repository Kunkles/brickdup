#!/usr/bin/env python3
"""Generate brickdup_psu.kicad_sch (buck + divider) for KiCad 10.

Connectivity is expressed with *local net labels* placed exactly on each pin's
connection point (KiCad treats same-named labels on a sheet as one net), so no
fragile wire geometry is hand-computed. Standard symbols are embedded by copying
KiCad's own library definitions; the MP9486A is a project-local symbol.

Run with KiCad's bundled python:
  /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3 gen_kicad.py
Then validate:
  kicad-cli sch erc brickdup_psu.kicad_sch
  kicad-cli sch export netlist brickdup_psu.kicad_sch -o /tmp/n.net

NOTE: U1 pin NUMBERS are PROVISIONAL (datasheet mirrors disagree). Verify against
the official MP9486A datasheet/footprint before layout. Pin FUNCTIONS are correct.
"""
import os, re, uuid

KSYM = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT  = os.path.join(HERE, "brickdup_psu.kicad_sch")

def U(s):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, "brickdup_psu/" + s))

def snap(v):                      # snap to 1.27 mm (50 mil) connection grid
    return round(round(v / 1.27) * 1.27, 4)

# ---- extract a top-level (symbol "NAME" ...) block, balanced ----
def extract_symbol(lib, name):
    t = open(f"{KSYM}/{lib}.kicad_sym").read()
    key = f'(symbol "{name}"'
    i = t.find(key)
    d = 0; j = i
    while j < len(t):
        c = t[j]
        if c == '(': d += 1
        elif c == ')':
            d -= 1
            if d == 0: break
        j += 1
    block = t[i:j+1]
    # rename top symbol id to "Lib:Name" (children keep "Name_x_y")
    block = block.replace(f'(symbol "{name}"', f'(symbol "{lib}:{name}"', 1)
    return block

# pin local connection coords {number: (lx, ly)} for each std symbol
PINS = {
    "Device:R":   {"1": (0, 3.81),  "2": (0, -3.81)},
    "Device:C":   {"1": (0, 3.81),  "2": (0, -3.81)},
    "Device:L":   {"1": (0, 3.81),  "2": (0, -3.81)},
    "Device:D_Schottky": {"1": (-3.81, 0), "2": (3.81, 0)},   # 1=K 2=A
    "Device:D_TVS":      {"1": (-3.81, 0), "2": (3.81, 0)},   # 1=A1 2=A2
    "Connector_Generic:Conn_01x02": {"1": (-5.08, 0), "2": (-5.08, -2.54)},
    "Connector_Generic:Conn_01x03": {"1": (-5.08, 2.54), "2": (-5.08, 0), "3": (-5.08, -2.54)},
    # connection points = the pin (at) in the symbol below (body edge +/-7.62, pin length 2.54)
    "brickdup:MP9486A": {
        "3": (-12.7, 7.62),  "7": (-12.7, 2.54),  "6": (-12.7, -2.54), "8": (-12.7, -7.62),
        "5": (12.7, 7.62),   "4": (12.7, 2.54),   "1": (12.7, -2.54),  "2": (12.7, -7.62),
    },
}

# ---- MP9486A project-local symbol (rectangle + 8 functional pins) ----
def mp_pin(num, name, lx, ly, ang, etype="passive"):
    return f'''      (pin {etype} line
        (at {lx} {ly} {ang})
        (length 2.54)
        (name "{name}" (effects (font (size 1.0 1.0))))
        (number "{num}" (effects (font (size 1.0 1.0))))
      )'''

MP9486A_SYM = f'''  (symbol "brickdup:MP9486A"
    (pin_names (offset 1.016))
    (exclude_from_sim no) (in_bom yes) (on_board yes)
    (property "Reference" "U" (at 0 13.97 0) (effects (font (size 1.27 1.27))))
    (property "Value" "MP9486A" (at 0 -13.97 0) (effects (font (size 1.27 1.27))))
    (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
    (property "Datasheet" "https://www.monolithicpower.com/en/mp9486a.html" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
    (property "Description" "100V 5V/1A async buck (PROVISIONAL pin numbers - verify)" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
    (symbol "MP9486A_0_1"
      (rectangle (start -7.62 10.16) (end 7.62 -10.16)
        (stroke (width 0.254) (type default)) (fill (type background)))
    )
    (symbol "MP9486A_1_1"
{mp_pin("3","VIN",-12.7,7.62,0)}
{mp_pin("7","EN",-12.7,2.54,0)}
{mp_pin("6","DIM",-12.7,-2.54,0)}
{mp_pin("8","GND",-12.7,-7.62,0)}
{mp_pin("5","SW",12.7,7.62,180)}
{mp_pin("4","BST",12.7,2.54,180)}
{mp_pin("1","FB",12.7,-2.54,180)}
{mp_pin("2","NC",12.7,-7.62,180,"no_connect")}
    )
  )'''

# ---- component instances: ref -> dict ----
# pos is (px,py) page coords; value/fp set props; dnp flag for DNP parts
FP = {
    "0402": "Resistor_SMD:R_0402_1005Metric",
    "0805": "Resistor_SMD:R_0805_2012Metric",
    "c0402": "Capacitor_SMD:C_0402_1005Metric",
    "c0603": "Capacitor_SMD:C_0603_1608Metric",
    "c1206": "Capacitor_SMD:C_1206_3216Metric",
    "c1210": "Capacitor_SMD:C_1210_3225Metric",
}
COMPS = {
    # ref:        (lib_id,                          value,        footprint,                              pos,        dnp)
    "U1":  ("brickdup:MP9486A",                     "MP9486A",    "Package_SO:SOIC-8-1EP_3.9x4.9mm_P1.27mm_EP2.41x3.3mm_ThermalVias", (160, 110), False),
    "L1":  ("Device:L",                             "33uH",       "Inductor_SMD:L_7.3x7.3_H4.5",          (210, 70),  False),
    "D1":  ("Device:D_Schottky",                    "SS210 100V", "Diode_SMD:D_SMA",                      (210, 120), False),
    "D2":  ("Device:D_TVS",                         "SMBJ45A",    "Diode_SMD:D_SMB",                      (60, 150),  False),
    "Cin1":("Device:C",                             "2.2uF/100V", FP["c1210"],                            (40, 90),   False),
    "Cin2":("Device:C",                             "2.2uF/100V", FP["c1210"],                            (60, 90),   False),
    "Cin3":("Device:C",                             "100nF/100V", FP["c0603"],                            (80, 90),   False),
    "Cbst":("Device:C",                             "100nF/50V",  FP["c0402"],                            (130, 70),  False),
    "Cout1":("Device:C",                            "22uF/25V",   FP["c1206"],                            (250, 120), False),
    "Cout2":("Device:C",                            "22uF/25V",   FP["c1206"],                            (270, 120), False),
    "Cout3":("Device:C",                            "100nF/50V",  FP["c0402"],                            (290, 120), True),
    "Cff": ("Device:C",                             "22pF",       FP["c0402"],                            (240, 80),  True),
    "RFB1":("Device:R",                             "240k 1%",    FP["0402"],                             (250, 80),  False),
    "RFB2":("Device:R",                             "10k 1%",     FP["0402"],                             (250, 100), False),
    "REN1":("Device:R",                             "100k",       FP["0402"],                             (110, 70),  False),
    "REN2":("Device:R",                             "DNP",        FP["0402"],                             (110, 150), True),
    "RDIM":("Device:R",                             "DNP",        FP["0402"],                             (180, 150), True),
    "R1":  ("Device:R",                             "200k 1%",    FP["0805"],                             (300, 70),  False),
    "R2":  ("Device:R",                             "22k 1%",     FP["0805"],                             (300, 95),  False),
    "C1":  ("Device:C",                             "100nF/50V",  FP["c0603"],                            (320, 95),  False),
    "J1":  ("Connector_Generic:Conn_01x02",         "VBAT/GND (JST PH)", "Connector_JST:JST_PH_S2B-PH-SM4-TB_1x02-1MP_P2.00mm_Horizontal", (350, 150), False),
    "J2":  ("Connector_Generic:Conn_01x03",         "5V/SENSE/GND (JST PH)", "Connector_JST:JST_PH_S3B-PH-SM4-TB_1x03-1MP_P2.00mm_Horizontal", (40, 170), False),
}

# ---- nets: name -> [(ref, pin), ...] ----
NETS = {
    "VBAT":  [("U1","3"),("Cin1","1"),("Cin2","1"),("Cin3","1"),("D2","1"),("REN1","1"),("R1","1"),("J1","1"),("RDIM","2")],
    "GND":   [("U1","8"),("Cin1","2"),("Cin2","2"),("Cin3","2"),("D2","2"),("D1","2"),("Cout1","2"),("Cout2","2"),("Cout3","2"),("RFB2","2"),("R2","2"),("C1","2"),("J1","2"),("J2","3"),("REN2","2")],
    "SW":    [("U1","5"),("L1","1"),("D1","1"),("Cbst","1")],
    "+5V":   [("L1","2"),("Cout1","1"),("Cout2","1"),("Cout3","1"),("RFB1","1"),("Cff","1"),("J2","1")],
    "BST":   [("U1","4"),("Cbst","2")],
    "FB":    [("U1","1"),("RFB1","2"),("RFB2","1"),("Cff","2")],
    "EN":    [("U1","7"),("REN1","2"),("REN2","1")],
    "DIM":   [("U1","6"),("RDIM","1")],
    "SENSE": [("R1","2"),("R2","1"),("C1","1"),("J2","2")],
}

ROOT = U("root")

def global_pt(ref, pin):
    lib = COMPS[ref][0]
    px, py = COMPS[ref][3]
    px, py = snap(px), snap(py)
    lx, ly = PINS[lib][pin]
    return (round(px + lx, 4), round(py - ly, 4))   # lib +Y up -> page +Y down

def sym_instance(ref):
    lib, val, fp, (px, py), dnp = COMPS[ref]
    px, py = snap(px), snap(py)
    u = U("sym/" + ref)
    pins = PINS[lib]
    pin_lines = "\n".join(
        f'    (pin "{n}" (uuid "{U("pin/"+ref+"/"+n)}"))' for n in pins)
    return f'''  (symbol
    (lib_id "{lib}")
    (at {px} {py} 0)
    (unit 1)
    (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp {"yes" if dnp else "no"})
    (uuid "{u}")
    (property "Reference" "{ref}" (at {px+2.54} {py-1.27} 0) (effects (font (size 1.27 1.27)) (justify left)))
    (property "Value" "{val}" (at {px+2.54} {py+1.27} 0) (effects (font (size 1.27 1.27)) (justify left)))
    (property "Footprint" "{fp}" (at {px} {py} 0) (effects (font (size 1.27 1.27)) (hide yes)))
    (property "Datasheet" "" (at {px} {py} 0) (effects (font (size 1.27 1.27)) (hide yes)))
{pin_lines}
    (instances
      (project "brickdup_psu"
        (path "/{ROOT}" (reference "{ref}") (unit 1))))
  )'''

def label(net, x, y):
    return f'''  (label "{net}"
    (at {x} {y} 0)
    (effects (font (size 1.27 1.27)) (justify left bottom))
    (uuid "{U(f"lbl/{net}/{x}/{y}")}")
  )'''

def build():
    # lib_symbols
    libs = ["Device:R","Device:C","Device:L","Device:D_Schottky","Device:D_TVS",
            "Connector_Generic:Conn_01x02","Connector_Generic:Conn_01x03"]
    lib_blocks = []
    for lid in libs:
        lib, name = lid.split(":")
        lib_blocks.append(extract_symbol(lib, name))
    lib_blocks.append(MP9486A_SYM)
    lib_symbols = "  (lib_symbols\n" + "\n".join(lib_blocks) + "\n  )"

    # instances
    insts = "\n".join(sym_instance(r) for r in COMPS)

    # labels + collision check
    seen = {}   # (x,y) -> net
    labels = []
    for net, pins in NETS.items():
        for ref, pin in pins:
            x, y = global_pt(ref, pin)
            key = (x, y)
            if key in seen and seen[key] != net:
                raise SystemExit(f"COLLISION at {key}: {seen[key]} vs {net} ({ref}.{pin})")
            seen[key] = net
            labels.append(label(net, x, y))
    labels = "\n".join(labels)

    # no_connect on U1 NC pin
    ncx, ncy = global_pt("U1", "2")
    nc = f'  (no_connect (at {ncx} {ncy}) (uuid "{U("nc/U1")}"))'

    return f'''(kicad_sch
  (version 20250114)
  (generator "brickdup_gen")
  (generator_version "10.0")
  (uuid "{ROOT}")
  (paper "A4")
  (title_block
    (title "brickdup_psu - sensor-node buck + divider")
    (rev "0.1")
    (comment 1 "Connectivity by net labels. U1 pin NUMBERS provisional - verify vs datasheet + run ERC.")
  )
{lib_symbols}
{insts}
{labels}
{nc}
  (sheet_instances
    (path "/" (page "1")))
)
'''

if __name__ == "__main__":
    open(OUT, "w").write(build())
    print("wrote", OUT)
