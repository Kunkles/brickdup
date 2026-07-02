# brickdup_carrier — v0.2 Heltec V3 carrier board

A carrier/baseboard that **sockets the Heltec WiFi LoRa 32 V3** on 0.1″ female
headers and carries the **unchanged v0.1 buck + divider** power stage
(MP9486A 100 V → 5 V/1 A, 200k/22k sense divider → GPIO7). Replaces the v0.1
wired J2 harness with copper: the only hand-wiring left is the LEMO pigtail
and the optional panel switch/buttons.

**Design lineage:** `pcb/brickdup_psu` (v0.1) — see its README for the full
buck/divider spec, part selection rationale, and layout rules. This README
covers only what v0.2 adds/changes.

---

## 1. What changed vs v0.1

| Area | v0.1 | v0.2 carrier |
|---|---|---|
| Heltec interface | 3-wire JST harness (J2) | **2×18 socket** (HDRA/HDRB), Heltec plugs in |
| 5V / SENSE / GND | wires | copper to socket (5V=HDRB.2, SENSE=HDRA.18/GPIO7) |
| Power switch | none | **SW1** 2-pin JST, in **series** with VBAT (JP1 solder-jumper bypass) |
| Buttons | Heltec onboard only, pressed via lid pistons | **BTN1** (PRG/GPIO0), **BTN2** (RST) 2-pin JSTs → wire to lid/panel buttons anywhere |
| GPIO breakout | none | BRK1 SPI ×8, BRK2 ADC ×8, BRK3 I2C ×4 (unpopulated THT) |
| J1/JST orientation | mouths faced inward (v0.1 bug) | **mouths face off-board** (J1 east, SW1/BTN1/BTN2 south) — asserted in gen_pcb.py |
| D2 clearance | flagged by JLC, de-populated | solver is **courtyard-aware**; D2 placeable |
| Cff | 22 pF DNP | footprint kept, BOM value ‹**BENCH — set from v0.1 Cff test**› |
| Mounting | 2× M2 | 4× M2 (board = enclosure tray) |
| Board | 40×20 mm | **62×44 mm** |

Electronics (values, nets, topology of buck + divider) are **identical** to
v0.1 pending the Cff bench result and any findings from the v0.1 design review.

## 2. Socket pin map (verified vs Heltec HTIT-WB32LA(F)_V3 pin map, 2026-07)

Rows are 18-pin, 2.54 mm pitch. **Pin 1 = GND, at the USB end (board EAST).**
`ROW_SPACING = 22.86 mm` — **✓ VERIFIED 2026-07-02** with calipers on a real
Heltec V3 (measured 22.77–22.93 mm across holes; pitch measured 2.55 mm).

### HDRA — Heltec header J3 (GPIO side, board NORTH row)

| Pin | Heltec | Carrier use |
|---|---|---|
| 1 | GND | GND |
| 2, 3 | 3V3 | 3V3 rail → BRK1/BRK3 |
| 4 | GPIO37 (ADC_Ctrl) | — internal, NC |
| 5, 6 | GPIO46, GPIO45 | — strapping pins, NC |
| 7, 8 | GPIO42, GPIO41 | **I2C → BRK3** (SCL=42, SDA=41) |
| 9, 10 | GPIO40, GPIO39 | — NC (JTAG) |
| 11 | GPIO38 | BRK2.8 |
| 12 | GPIO1 (VBAT_Read) | — internal, NC |
| 13–17 | GPIO2–GPIO6 (ADC1) | **BRK2** generic/ADC |
| 18 | **GPIO7** | **SENSE** (divider midpoint — same firmware pin as v0.1/wired) |

### HDRB — Heltec header J2 (power side, board SOUTH row)

| Pin | Heltec | Carrier use |
|---|---|---|
| 1 | GND | GND |
| 2 | **5V** | **+5V from buck** (powers Heltec + charges its LiPo) |
| 3, 4 | Ve | — NC |
| 5, 6 | GPIO44 RX, GPIO43 TX | — NC (USB serial) |
| 7 | **RST** | **BTN2** JST |
| 8 | **GPIO0** (PRG/USER_SW) | **BTN1** JST |
| 9 | GPIO36 (Vext ctrl) | — internal, NC |
| 10–12 | GPIO35, 34, 33 | **BRK1** (SPI cluster) |
| 13, 14 | GPIO47, GPIO48 | **BRK1** |
| 15 | GPIO26 | BRK1.8 |
| 16 | GPIO21 (OLED_RST) | — internal, NC |
| 17, 18 | GPIO20, GPIO19 | — NC (ADC2/USB) |

## 3. Switch, buttons, breakouts

- **SW1 (power switch, series):** J1 VBAT → `VBATIN` → SW1 → `VBAT` → buck.
  Wire a panel toggle/slide switch to the SW1 JST. **No switch? Bridge JP1**
  (solder jumper next to J1) and leave SW1 empty. Switch must be rated ≥30 V DC
  at ~1 A (it carries raw battery, max 25.2 V).
- **BTN1 = PRG (GPIO0→GND), BTN2 = RST (RST→GND):** momentary N.O. buttons,
  wired anywhere (lid flexures, panel). Parallel with the Heltec's onboard
  buttons — both keep working. All firmware gestures (tap/long/triple on
  GPIO0) work unchanged.
- **Breakouts (unpopulated 2.54 mm THT, DNP in BOM):**
  - **BRK1 "SPI"** (south): 3V3, GND, IO33, IO34, IO35, IO47, IO48, IO26 —
    six GPIOs + power = future W5500/SPI module lands here.
  - **BRK2 "ADC"** (north): 5V, GND, IO2–IO6 (ADC1/touch), IO38.
  - **BRK3 "I2C"** (north): 3V3, GND, IO41 (SDA), IO42 (SCL).

## 4. Floorplan

```
        N (ADC + I2C breakouts, north strip)
  ┌────────────────────────────────────────────┐
  │ O   [BRK2 ADC........]   [BRK3 I2C..]   O  │   O = M2 holes ×4
  │ ══HDRA════════════════════════════pin1══   │   Heltec rows: pin1 EAST
  │  ANT│ divider  │  buck island   │        │ │   (USB end → east wall)
  │     │ R1 R2 C1 │ Cout L1 D1 U1 Cin D2│ [J1]│ ← VBAT in, mouth EAST
  │ ══HDRB════════════════════════════pin1══   │   JP1 bypass near J1
  │ O  [SW1] [BTN1] [BTN2]  [BRK1 SPI.....] O  │
  └────────────────────────────────────────────┘
        S (switch + buttons, mouths off south edge)
```

- Buck island sits **between the socket rows under the Heltec** — the socket
  gives ~8.5 mm clearance, enough for L1 (~5 mm). It's biased **east (USB
  end)**, keeping the switch node away from the SX1262/antenna end (west).
- Sense divider isolated **west**, far from the SW node, short run to HDRA.18.
- The Heltec module outline (50.2×25.5) is drawn on silk with USB/ANT marks.

## 5. Assembly notes

- Socket rows = THT **female pin sockets** (2×18-pin 1×18 strips): either JLC
  hand-solder service or solder them yourself (easiest THT job there is).
  Heltec ships with matching male pins.
- BRK1–3 are **DNP** — solder headers only when a project needs them.
- JSTs (J1, SW1, BTN1, BTN2) are the same S2B-PH-SM4-TB as v0.1 (LCSC C295747).
- Cff: populate with the **bench-validated value** from the v0.1 whine fix.

## 6. Reproducible pipeline

Same toolchain as v0.1 (see `pcb/HANDOFF.md` §7). From `pcb/carrier/`:

```
python3 gen_kicad.py                  # schematic (ERC: 0 violations)
python3 gen_pcb.py                    # outline+socket+solver placement (courtyard-aware)
python3 ../export_dsn.py brickdup_carrier.kicad_pcb /tmp/carrier.dsn
java -jar /tmp/freerouting224.jar -de /tmp/carrier.dsn -do /tmp/carrier.ses -mp 12
python3 apply_route.py                # import + vias + solid GND on connectors + fill
kicad-cli pcb drc brickdup_carrier.kicad_pcb -o /tmp/drc.json --format json --severity-error
python3 fix_thermals.py brickdup_carrier.kicad_pcb /tmp/drc.json   # heal starved thermals
kicad-cli pcb drc brickdup_carrier.kicad_pcb   # -> 0 violations, 0 unconnected
```

**freerouting gotcha:** if it routes but never writes the SES, set
`"gui": {"enabled": false}` in its `freerouting.json` (under
`$TMPDIR/freerouting/`) — with `gui.enabled=true` the headless run finishes
routing and then hangs waiting on a GUI handoff instead of saving.

## 7. Open items before ordering

1. ~~ROW_SPACING~~ **✓ verified 22.86 mm** (calipers, 2026-07-02). Still worth
   eyeballing **pin-1/GND at the USB end** when the sockets arrive (test-fit the
   Heltec on loose sockets before soldering them).
2. **Cff value** from the v0.1 bench test → update BOM + populate.
3. Fold in any v0.1 **design-review findings** (EN threshold, EP thermal vias).
4. **Enclosure v2** dry-fit plan — see `enclosure/CARRIER_ENCLOSURE.md`.
5. LCSC codes for: pin sockets 1×18 (e.g. C2337recheck), pin headers (DNP —
   no code needed), plus carry-over v0.1 BOM codes.
