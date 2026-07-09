#!/usr/bin/env python3
"""Generate brickdup_carrier.kicad_sch — v0.2 carrier board for KiCad 10.

The carrier hosts the Heltec WiFi LoRa 32 V3 on a 2x18 socket (HDRA = Heltec
header J3 / GPIO side, HDRB = Heltec header J2 / power side) and carries the
UNCHANGED v0.1 buck + divider electronics (MP9486A, 33uH, SS210, same values).

New in v0.2 vs pcb/brickdup_psu:
  - Heltec socket rows HDRA/HDRB (pin map verified against Heltec's official
    HTIT-WB32LA(F)_V3 pin map image, 2026-07).
  - J2 (3-pin JST to the Heltec) is GONE: +5V / SENSE / GND route on copper
    straight to the socket (5V = HDRB.2, SENSE = HDRA.18/GPIO7, GND = pin 1s).
  - SW1: 2-pin JST for a wired power switch in SERIES with VBAT (J1 -> SW1 ->
    buck). JP1 solder jumper bridges SW1 when no switch is fitted.
  - BTN1: 2-pin JST, GPIO0 (PRG) -> GND.  BTN2: 2-pin JST, RST -> GND.
  - Breakout headers (unpopulated 2.54mm THT):
      BRK1 8-pin "SPI"  : 3V3 GND IO33 IO34 IO35 IO47 IO48 IO26 (future W5500)
      BRK2 8-pin "ADC"  : 5V  GND IO2  IO3  IO4  IO5  IO6  IO38
      BRK3 4-pin "I2C"  : 3V3 GND IO41(SDA) IO42(SCL)

Connectivity is expressed with local net labels placed exactly on pin points;
pin coordinates are PARSED from each symbol block (not hardcoded).

Run with KiCad's bundled python:
  /Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3 gen_kicad.py
Validate:
  kicad-cli sch erc brickdup_carrier.kicad_sch
"""
import os, re, uuid

KSYM = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT  = os.path.join(HERE, "brickdup_carrier.kicad_sch")

def U(s):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, "brickdup_carrier/" + s))

def snap(v):                      # snap to 1.27 mm (50 mil) connection grid
    return round(round(v / 1.27) * 1.27, 4)

# ---- extract a top-level (symbol "NAME" ...) block, balanced ----
def extract_symbol(lib, name):
    t = open(f"{KSYM}/{lib}.kicad_sym").read()
    key = f'(symbol "{name}"'
    i = t.find(key)
    if i < 0:
        raise SystemExit(f"symbol not found: {lib}:{name}")
    d = 0; j = i
    while j < len(t):
        c = t[j]
        if c == '(': d += 1
        elif c == ')':
            d -= 1
            if d == 0: break
        j += 1
    block = t[i:j+1]
    block = block.replace(f'(symbol "{name}"', f'(symbol "{lib}:{name}"', 1)
    return block

# ---- parse pin connection coords {number:(x,y)} out of a symbol block ----
PIN_RE = re.compile(
    r'\(pin\s+\w+\s+\w+\s*\(at\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\)'
    r'.*?\(number\s+"([^"]+)"', re.S)

def parse_pins(block):
    pins = {}
    for m in PIN_RE.finditer(block):
        x, y, ang, num = float(m.group(1)), float(m.group(2)), float(m.group(3)), m.group(4)
        pins[num] = (x, y)
    return pins

# ---- MP9486A project-local symbol (same as v0.1) ----
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
    (property "Description" "100V 5V/1A async buck" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
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
{mp_pin("9","EP",0,0,0,"passive")}
    )
  )'''

FP = {
    "0402": "Resistor_SMD:R_0402_1005Metric",
    "0805": "Resistor_SMD:R_0805_2012Metric",
    "c0402": "Capacitor_SMD:C_0402_1005Metric",
    "c0603": "Capacitor_SMD:C_0603_1608Metric",
    "c1206": "Capacitor_SMD:C_1206_3216Metric",
    "c1210": "Capacitor_SMD:C_1210_3225Metric",
    "jstph2": "Connector_JST:JST_PH_S2B-PH-SM4-TB_1x02-1MP_P2.00mm_Horizontal",
    "sock18": "Connector_PinSocket_2.54mm:PinSocket_1x18_P2.54mm_Vertical",
    "hdr8":  "Connector_PinHeader_2.54mm:PinHeader_1x08_P2.54mm_Vertical",
    "hdr4":  "Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical",
    "sj":    "Jumper:SolderJumper-2_P1.3mm_Open_TrianglePad1.0x1.5mm",
}

# ---- components: ref -> (lib_id, value, footprint, sch_pos, dnp) ----
COMPS = {
    # ---------------- buck + divider: IDENTICAL electronics to v0.1 ----------
    "U1":  ("brickdup:MP9486A", "MP9486A",    "Package_SO:SOIC-8-1EP_3.9x4.9mm_P1.27mm_EP2.41x3.3mm", (150, 90),  False),
    "L1":  ("Device:L",         "33uH 6A",    "brickdup:L_CYA0850",  (200, 55),  False),
    "D1":  ("Device:D_Schottky","SS210 100V", "Diode_SMD:D_SMA",     (200, 100), False),
    "D2":  ("Device:D_TVS",     "SMBJ45A",    "Diode_SMD:D_SMB",     (60, 130),  False),
    "Cin1":("Device:C",         "2.2uF/100V", FP["c1210"],           (40, 70),   False),
    "Cin2":("Device:C",         "2.2uF/100V", FP["c1210"],           (60, 70),   False),
    "Cin3":("Device:C",         "100nF/100V", FP["c0603"],           (80, 70),   False),
    "Cbst":("Device:C",         "100nF/50V",  FP["c0402"],           (120, 55),  False),
    "Cout1":("Device:C",        "22uF/25V",   FP["c1206"],           (240, 100), False),
    "Cout2":("Device:C",        "22uF/25V",   FP["c1206"],           (260, 100), False),
    "Cout3":("Device:C",        "100nF/50V",  FP["c0402"],           (280, 100), True),
    "Cff": ("Device:C",         "470pF",      FP["c0603"],           (230, 65),  False),
    "RFB1":("Device:R",         "240k 1%",    FP["0402"],            (240, 65),  False),
    "RFB2":("Device:R",         "10k 1%",     FP["0402"],            (240, 82),  False),
    "REN1":("Device:R",         "100k",       FP["0402"],            (105, 55),  False),
    "REN2":("Device:R",         "DNP",        FP["0402"],            (105, 130), True),
    "R1":  ("Device:R",         "200k 1%",    FP["0805"],            (300, 55),  False),
    "R2":  ("Device:R",         "22k 1%",     FP["0805"],            (300, 80),  False),
    "C1":  ("Device:C",         "100nF/50V",  FP["c0603"],           (320, 80),  False),
    # ---------------- power in + wired switch/buttons ------------------------
    "J1":  ("Connector_Generic:Conn_01x02", "VBAT IN (JST PH)",   FP["jstph2"], (40, 160),  False),
    "SW1": ("Connector_Generic:Conn_01x02", "PWR SWITCH (JST PH)",FP["jstph2"], (80, 160),  False),
    "JP1": ("Jumper:SolderJumper_2_Open",   "SW bypass",          FP["sj"],     (80, 180),  False),
    "BTN1":("Connector_Generic:Conn_01x02", "PRG BTN (JST PH)",   FP["jstph2"], (130, 160), False),
    "BTN2":("Connector_Generic:Conn_01x02", "RST BTN (JST PH)",   FP["jstph2"], (170, 160), False),
    # ---------------- Heltec socket rows -------------------------------------
    # HDRA = Heltec "J3" row (GPIO side). Pin 1 = GND at the USB end.
    "HDRA":("Connector_Generic:Conn_01x18", "HELTEC J3 (GPIO side)",  FP["sock18"], (370, 90),  False),
    # HDRB = Heltec "J2" row (power side). Pin 1 = GND at the USB end.
    "HDRB":("Connector_Generic:Conn_01x18", "HELTEC J2 (power side)", FP["sock18"], (420, 90),  False),
    # ---------------- breakout headers (DNP = not assembled) -----------------
    "BRK1":("Connector_Generic:Conn_01x08", "SPI breakout",  FP["hdr8"], (240, 160), True),
    "BRK2":("Connector_Generic:Conn_01x08", "ADC breakout",  FP["hdr8"], (280, 160), True),
    "BRK3":("Connector_Generic:Conn_01x04", "I2C breakout",  FP["hdr4"], (320, 160), True),
}

# Heltec socket pin meaning (for reference + silk):
#   HDRA: 1=GND 2=3V3 3=3V3 4=IO37 5=IO46 6=IO45 7=IO42 8=IO41 9=IO40 10=IO39
#         11=IO38 12=IO1 13=IO2 14=IO3 15=IO4 16=IO5 17=IO6 18=IO7(SENSE)
#   HDRB: 1=GND 2=5V 3=Ve 4=Ve 5=IO44/RX 6=IO43/TX 7=RST 8=IO0(PRG) 9=IO36
#         10=IO35 11=IO34 12=IO33 13=IO47 14=IO48 15=IO26 16=IO21 17=IO20 18=IO19

# ---- nets ----
NETS = {
    # v0.1 buck + divider nets, unchanged except J2 -> socket pins
    "VBAT":  [("U1","3"),("Cin1","1"),("Cin2","1"),("Cin3","1"),("D2","1"),
              ("REN1","1"),("R1","1"),("SW1","2"),("JP1","2")],
    "VBATIN":[("J1","1"),("SW1","1"),("JP1","1")],
    "GND":   [("U1","8"),("U1","9"),("Cin1","2"),("Cin2","2"),("Cin3","2"),
              ("D2","2"),("D1","2"),("Cout1","2"),("Cout2","2"),("Cout3","2"),
              ("RFB2","2"),("R2","2"),("C1","2"),("J1","2"),("REN2","2"),
              ("BTN1","2"),("BTN2","2"),
              ("HDRA","1"),("HDRB","1"),
              ("BRK1","2"),("BRK2","2"),("BRK3","2")],
    "SW":    [("U1","5"),("L1","1"),("D1","1"),("Cbst","1")],
    "+5V":   [("L1","2"),("Cout1","1"),("Cout2","1"),("Cout3","1"),
              ("RFB1","1"),("Cff","1"),("HDRB","2"),("BRK2","1")],
    "BST":   [("U1","4"),("Cbst","2")],
    "FB":    [("U1","1"),("RFB1","2"),("RFB2","1"),("Cff","2")],
    "EN":    [("U1","7"),("U1","6"),("REN1","2"),("REN2","1")],
    "SENSE": [("R1","2"),("R2","1"),("C1","1"),("HDRA","18")],
    # Heltec-side signals
    "3V3":   [("HDRA","2"),("HDRA","3"),("BRK1","1"),("BRK3","1")],
    "PRG":   [("HDRB","8"),("BTN1","1")],
    "RST":   [("HDRB","7"),("BTN2","1")],
    # breakout GPIO nets
    "IO33":  [("HDRB","12"),("BRK1","3")],
    "IO34":  [("HDRB","11"),("BRK1","4")],
    "IO35":  [("HDRB","10"),("BRK1","5")],
    "IO47":  [("HDRB","13"),("BRK1","6")],
    "IO48":  [("HDRB","14"),("BRK1","7")],
    "IO26":  [("HDRB","15"),("BRK1","8")],
    "IO2":   [("HDRA","13"),("BRK2","3")],
    "IO3":   [("HDRA","14"),("BRK2","4")],
    "IO4":   [("HDRA","15"),("BRK2","5")],
    "IO5":   [("HDRA","16"),("BRK2","6")],
    "IO6":   [("HDRA","17"),("BRK2","7")],
    "IO38":  [("HDRA","11"),("BRK2","8")],
    "IO41":  [("HDRA","8"),("BRK3","3")],    # SDA
    "IO42":  [("HDRA","7"),("BRK3","4")],    # SCL
}

# socket pins intentionally left unconnected -> schematic no_connect markers
NC_PINS = [("HDRA", n) for n in ("4","5","6","9","10","12")] + \
          [("HDRB", n) for n in ("3","4","5","6","9","16","17","18")]

ROOT = U("root")
SYM_PINS = {}   # lib_id -> {num:(x,y)} filled in build()

def global_pt(ref, pin):
    lib = COMPS[ref][0]
    px, py = COMPS[ref][3]
    px, py = snap(px), snap(py)
    lx, ly = SYM_PINS[lib][pin]
    return (round(px + lx, 4), round(py - ly, 4))   # lib +Y up -> page +Y down

def sym_instance(ref):
    lib, val, fp, (px, py), dnp = COMPS[ref]
    px, py = snap(px), snap(py)
    u = U("sym/" + ref)
    pins = SYM_PINS[lib]
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
      (project "brickdup_carrier"
        (path "/{ROOT}" (reference "{ref}") (unit 1))))
  )'''

def label(net, x, y):
    return f'''  (label "{net}"
    (at {x} {y} 0)
    (effects (font (size 1.27 1.27)) (justify left bottom))
    (uuid "{U(f"lbl/{net}/{x}/{y}")}")
  )'''

def build():
    libs = ["Device:R","Device:C","Device:L","Device:D_Schottky","Device:D_TVS",
            "Connector_Generic:Conn_01x02","Connector_Generic:Conn_01x04",
            "Connector_Generic:Conn_01x08","Connector_Generic:Conn_01x18",
            "Jumper:SolderJumper_2_Open"]
    lib_blocks = []
    for lid in libs:
        lib, name = lid.split(":")
        block = extract_symbol(lib, name)
        lib_blocks.append(block)
        SYM_PINS[lid] = parse_pins(block)
    lib_blocks.append(MP9486A_SYM)
    SYM_PINS["brickdup:MP9486A"] = parse_pins(MP9486A_SYM)
    lib_symbols = "  (lib_symbols\n" + "\n".join(lib_blocks) + "\n  )"

    # sanity: every netted pin must exist in the parsed pin map
    for net, nodes in NETS.items():
        for ref, pin in nodes:
            lib = COMPS[ref][0]
            if pin not in SYM_PINS[lib]:
                raise SystemExit(f"pin {pin} missing on {lib} (net {net}, ref {ref})")

    insts = "\n".join(sym_instance(r) for r in COMPS)

    seen = {}
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

    ncs = []
    ncx, ncy = global_pt("U1", "2")
    ncs.append(f'  (no_connect (at {ncx} {ncy}) (uuid "{U("nc/U1")}"))')
    for ref, pin in NC_PINS:
        x, y = global_pt(ref, pin)
        ncs.append(f'  (no_connect (at {x} {y}) (uuid "{U(f"nc/{ref}/{pin}")}"))')
    ncs = "\n".join(ncs)

    return f'''(kicad_sch
  (version 20250114)
  (generator "brickdup_gen")
  (generator_version "10.0")
  (uuid "{ROOT}")
  (paper "A3")
  (title_block
    (title "brickdup_carrier - Heltec V3 carrier + buck + divider")
    (rev "0.2")
    (comment 1 "v0.1 buck/divider unchanged. Socket pin map from Heltec HTIT-WB32LA(F)_V3.")
  )
{lib_symbols}
{insts}
{labels}
{ncs}
  (sheet_instances
    (path "/" (page "1")))
)
'''

if __name__ == "__main__":
    open(OUT, "w").write(build())
    print("wrote", OUT)
