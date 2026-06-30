# brickdup_psu — Session Handoff (custom PSU PCB + enclosure)

Self-contained handoff so this work can continue in a fresh chat. Covers the
custom **buck + divider PCB** (`brickdup_psu`), the enclosure changes to host it,
and the JLCPCB order.

---

## 1. What this is

A custom PCB that combines the sensor-node's **buck converter + voltage divider**
onto one board, replacing the Pololu D24V10F5 module + hand-built inline divider.
Goal: a JLCPCB-assembled board that drops into the 3D-printed sensor-node enclosure.

- **In:** raw camera battery (4S/6S, ≤25.2 V) from a LEMO connector → board's J1.
- **Buck:** discrete **MP9486A** (100 V in, **5.0 V/1 A**, hysteretic) → powers the
  Heltec + charges its bridge LiPo.
- **Divider:** 200k/22k/100nF → analog sense to the Heltec's **GPIO7** (unchanged
  ratio, so no firmware change). `DIVIDER_RATIO = (222/22)`.
- **Out:** J2 (5V, SENSE, GND) → Heltec.
- The only board↔Heltec interface is **power + one analog sense line + GND** —
  no serial/UART/SPI/I²C anywhere in the design.

## 2. Current status (as of session end)

- **Branch:** `psu-pcb` (pushed). **PR:** https://github.com/Kunkles/brickdup/pull/1
- **KiCad 10 project:** fully placed + **auto-routed** (0 unconnected, 0 shorts).
  DRC = cosmetic silk + a few courtyard warnings only.
- **JLCPCB order: PLACED** (assembled, qty 5). A duplicate first order was refunded.
- **Boards received + bench bring-up started 2026-06-30** (see §2a).
- **NOT yet done:** MPSmart sim, enclosure dry-fit, full bring-up (buck regulation fault open).

## 2a. v0.1 bench bring-up — 2026-06-30 (boards in hand)

- **Sense divider: GOOD.** 14 V in → **1.36 V at GPIO7** (ratio ~10.3 vs design 10.09).
  No firmware/calibration change needed.
- **JLC parts placement confirmed:** D1 polarity correct, U1 pin-1 correct. **D2 (TVS)
  de-populated** at JLC's request (engineer flagged D2 vs D1/L1 clearance) — board works
  without it; footprint remains for optional hand-fit. **J1/J2 wire-mouths placed reversed**
  (face inward) — electrically fine (nets follow pads), accepted for v0.1; rotate 180° in v0.2.
- **Buck regulation — FAULT, open:**
  - *No load:* output wanders **5–6.5 V** (rides high). Classic hysteretic light-load
    pulse-skipping with all-ceramic Cout (no FB ripple for the comparator).
  - *Under ~100–250 mA load:* voltage **stabilizes**, BUT then audible **screech/squeak**,
    **heats up fast**, and behavior **changes when pressing the output connector**
    (mechanical sensitivity → suspect cold joint). Heltec orange charge LED blinks in sync
    with the erratic screech (5 V rail browning out / cycling).
  - *Next steps:* (1) identify which part heats — U1 vs L1 vs just the load resistor;
    (2) reflow suspect joints, esp. **U1 exposed-pad ground**, J2, Cout1/2, L1, D1;
    (3) populate **Cff** (start ~100 pF, up to ~1 nF) for hysteretic ripple injection /
    loop stability; (4) scope SW + Vout. Don't reconnect the Heltec as load until the
    rail is steady + cool on a plain resistor.

## 3. Key files (all in the repo)

| File | What |
|---|---|
| `pcb/README.md` | Full design spec (architecture, parts, layout rules, ordering, §9 validation). |
| `pcb/bom.csv` | BOM with **as-ordered LCSC codes** (single source of truth). |
| `pcb/brickdup_psu.kicad_{pro,sch,pcb}` | The KiCad 10 project (placed + routed). |
| `pcb/gen_kicad.py` | Generates the schematic (symbols + net-label connectivity). |
| `pcb/gen_pcb.py` | Generates the board: outline, M2 holes, separation-solver placement, nets, GND zones. |
| `pcb/export_dsn.py` | Exports a zone-stripped Specctra DSN for the router. |
| `pcb/apply_route.py` | Imports the freerouting SES, normalizes vias, hides silk refs, fills zones. |
| `pcb/convert_jlc.py` | Converts CPL/BOM to JLCPCB upload format. |
| `pcb/brickdup.pretty/L_CYA0850.kicad_mod` | Custom footprint for the inductor (datasheet-verified land). |
| `pcb/fab/` | JLCPCB upload set: `brickdup_psu-gerbers.zip`, `jlc_cpl.csv`, `jlc_bom.csv`. |
| `pcb/mpsmart-inputs.md` | Copy-paste sheet for the MPSmart closed-loop sim. |
| `docs/pcb_schematic.svg` | Human-readable schematic. |
| `docs/pcb_routed_3d.png` | 3D render of the routed board. |
| `enclosure/node_enclosure.scad` | Enclosure **v11** — updated to host this board. |

## 4. As-ordered BOM (LCSC part numbers)

| Ref | Value | LCSC |
|---|---|---|
| U1 | MP9486AGN-Z (100V buck) | **C404013** |
| L1 | 33µH 3A/6A inductor (CYA0850, 9.2×8mm, custom fp) | **C19268648** |
| D1 | SS210 Schottky 100V 2A | **C14996** |
| D2 | SMBJ45A TVS | **C42371744** |
| Cin1, Cin2 | 2.2µF 100V X7R 1210 | **C55151** |
| Cin3 | 100nF 50V 0603 | **C14663** |
| Cbst | 100nF 16V 0402 | **C1525** |
| Cout1, Cout2 | 22µF 25V X5R 1206 | **C12891** |
| RFB1 | 240k 0402 1% | **C64043** |
| RFB2 | 10k 0402 1% | **C25744** |
| REN1 | 100k 0402 1% | **C25741** |
| R1 | 200k 0805 1% | **C17539** |
| R2 | 22k 0805 1% | **C17560** |
| C1 | 100nF 50V 0603 | **C14663** |
| J1 | JST-PH 2-pin SMD side (S2B-PH-SM4-TB) | **C295747** |
| J2 | JST-PH 3-pin SMD side (S3B-PH-SM4-TB) | **C265101** |
| **DNP** | Cff, Cout3, REN2 | (not placed) |

RFB1=240k/RFB2=10k sets 5.0 V (MP9486A VFB = 0.2 V). DIM is tied to EN (datasheet:
non-dimming buck). U1 exposed pad → GND.

## 5. Open items / next steps

1. **DFM analysis** (JLC Order History, ~4–6 h after ordering): verify the
   **rotation** of U1, D1, D2, J1, J2 (KiCad↔JLC rotation can differ). Fix in DFM if flagged.
2. **When boards arrive — bench bring-up:** feed VBAT via J1 (16–25 V), confirm
   **~5 V at J2**, check U1/inductor stay cool, then wire to the Heltec and confirm
   it powers up and reads battery voltage on GPIO7.
3. **Closed-loop sim (optional, recommended):** run **MPSmart** with `pcb/mpsmart-inputs.md`
   (ngspice can't do the switcher loop — confirmed). Validates ripple/transient/stability.
4. **Enclosure dry-fit** (full of `‹MEASURE›` guesses, never physically fit):
   - Confirm the board's 2 M2 holes line up with the bosses, **J1 faces the LEMO (east)**
     and **J2 faces the Heltec (north)** (orientation was fixed in code, not verified).
   - Confirm the **J2 connector + 3 wires clear the LiPo** (raised Heltec to 16mm towers
     for ~5.75mm clearance; the cleaner horizontal **wire-trench** is deferred to dry-fit).
   - Confirm the **lid clears the LEMO nut** (added a parametric lid-lip relief, `lemo_nut`=13).
   - Then lock in `‹MEASURE›` values (Heltec dims, LEMO hole/nut, button positions).
5. **Order complementary parts** (see `pcb/README.md` §3.4):
   - **JST-PH 2.0mm pigtails**: 2-pin (J1↔LEMO, crimp) + 3-pin (J2↔Heltec, solder to Heltec pads). 24–26 AWG.
   - LEMO panel connector, bridge LiPo (1S ~1100 mAh, JST 1.25), LoRa antenna (u.FL→SMA), M2 screws.
6. Merge PR #1 when ready.

## 6. Known caveats / risks

- **Unbuilt / not bench-tested.** Component values are engineering selections.
- **Closed-loop regulator behavior NOT validated** (ripple, loop stability) — needs MPSmart or bench.
- **Custom L1 footprint** matches the datasheet land on paper; verify with the real part.
- **Enclosure never dry-fit** — the board↔enclosure orientation was reconciled in code
  (KiCad Y-down vs OpenSCAD Y-up), but only a physical dry-fit confirms it.

## 7. Toolchain + reproducible pipeline (this machine)

- KiCad 10: `/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`; bundled python
  with `pcbnew` at `/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3`.
- OpenSCAD 2021.01: `/Applications/OpenSCAD-2021.01.app/Contents/MacOS/OpenSCAD`
  (render with `-D '$fn=20'`; run outside the sandbox or it gets SIGKILLed).
- freerouting **v2.x** jar (download to /tmp; v1.9 fails headless). Java: `/opt/homebrew/opt/openjdk/bin/java`.
- ngspice + poppler via Homebrew.

Regenerate the board from scratch:
```
cd pcb
python3 gen_kicad.py
python3 gen_pcb.py                 # deterministic separation-solver placement
python3 export_dsn.py             # -> /tmp/brickdup.dsn (zones stripped)
java -jar /tmp/freerouting2.jar -de /tmp/brickdup.dsn -do /tmp/brickdup.ses -mp 60
python3 apply_route.py            # import routes + fill -> final board
python3 convert_jlc.py            # -> fab/jlc_cpl.csv, fab/jlc_bom.csv
```
(Use KiCad's bundled python for all of the above so `pcbnew` is importable.)
Validate: `kicad-cli sch erc` / `kicad-cli pcb drc`. Headless ERC shows ~44 benign
"library not in configuration" warnings — artifact of no GUI config, not errors.

---

*See also: `pcb/README.md` (spec), `WIRING.md` (node power/sense), `REFERENCE.md`
(pins), `ENCLOSURE.md` (shell brief).*
