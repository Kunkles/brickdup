# brickdup — Sensor-Node Power/Sense PCB (`brickdup_psu`)

A small custom PCB that **combines the buck converter and the voltage divider**
onto one board, sized to drop into the sensor-node enclosure. It replaces the
Pololu D24V10F5 module + hand-built inline divider with a single JLCPCB-assembled
board.

> **Status: design spec / v0.1 (pre-layout).** Component values below are
> engineering selections grounded in the MP9486A datasheet + Würth
> EV9486A-N-00A reference design. **Nothing here has been built or simulated.**
> Treat every value as "verify before fab" — especially the MP9486A pinout
> (see the warning in §3) and the LCSC part numbers (stock/Basic status drifts;
> confirm at order time).

---

## 1. What the board does

```
 VBAT (4S/6S, ≤25.2V) ─┬─► MP9486A buck ──► 5.0V ──► Heltec "5V" pin (+ LiPo charge)
   (from LEMO)         │
                       └─► R1 200k ──┬── R2 22k ──┬── GND
                                     │            │
                                     └─ 100nF ────┤
                                     │
                                     └──────────► SENSE → Heltec GPIO7
```

- **Input:** raw camera-battery voltage from the LEMO — 4S **or** 6S, up to
  **25.2 V**. The board is the *only* thing that ever sees raw pack voltage.
- **Buck:** steps VBAT down to a regulated **5.0 V**, which powers the Heltec
  *and* feeds its onboard LiPo charger.
- **Divider:** the same 200k / 22k / 100nF network the node uses today, producing
  the GPIO7 sense voltage. Ratio is unchanged, so **no firmware change** is
  needed — `DIVIDER_RATIO = (222/22)` in the universal sketch still holds.

This is the same architecture documented in [`WIRING.md`](../WIRING.md); the only
change is that the buck + divider are now one manufactured board instead of a
module + inline parts.

---

## 2. Why a discrete buck (MP9486A) instead of the D24V10F5 module

You chose a fully discrete regulator (JLCPCB places all SMD parts). Selection
criteria and the result:

| Need | Driver | Choice |
|---|---|---|
| **Input voltage margin** | A 6S pack is 25.2 V. Hot-plugging it through the LEMO + cable inductance into ceramic input caps can **ring toward ~2×Vin (~50 V)**. A 36 V part (incl. the D24V10F5) survives this only with marginal protection. | **100 V-rated IC** → ringing is a non-issue, no load-bearing TVS needed. |
| **Output current** | Heltec WiFi-portal load + LiPo charge (see §4). | ~1 A continuous, brief sub-1 A peaks. |
| **Simplicity (first spin)** | Fewer external parts = fewer ways to get a switcher wrong. | **Hysteretic / internally-compensated** topology → no COMP network. |
| **JLCPCB assembly** | Must be in the LCSC library. | MP9486AGN-Z is stocked (`C404013`). |

**Part: Monolithic Power MP9486AGN-Z** — 100 V input, 5 V/1 A async step-down,
hysteretic control, SOIC-8 (exposed pad). LCSC `C404013` / JLC part
`MP9486AGN-Z`.

Higher-current alternate (if bench testing ever hits the 1 A ceiling): **TI
TPS54360** (60 V / 3.5 A) — but it needs an external compensation network and is
a bigger design lift. Stick with the MP9486A for the first board.

---

## 3. Schematic & component values

Authoritative schematic: [`docs/pcb_schematic.svg`](../docs/pcb_schematic.svg).

> ⚠️ **MP9486A pinout must be taken from the official symbol, not from this
> doc.** Two datasheet mirrors disagree on the SOIC-8 pin *numbering* (they agree
> on pin *functions*: VIN, GND, SW, BST, FB, EN, DIM). When you capture the
> schematic, use the MPS/SnapEDA MP9486A symbol+footprint and **run ERC**. The
> functional connections below are what matter.

### 3.1 Buck stage (MP9486A)

| Ref | Function | Value | Notes |
|---|---|---|---|
| U1 | Regulator | MP9486AGN-Z | SOIC-8-EP. Tie EP to GND plane. |
| L1 | Buck inductor | **33 µH**, Isat ≥ 1.7 A, shielded | Ref design uses WE 7447714330 (33 µH/2.9 A, 12×12 mm). Prefer a smaller ~7×7 mm 33 µH ≥1.5 A part to fit the board. |
| D1 | Catch (freewheel) diode | **Schottky, ≥100 V, ≥2 A** | e.g. SS210 (100 V/2 A, SMA). Async buck → required. Cathode→SW, anode→GND. |
| Cin1, Cin2 | Input bulk | **2.2 µF, 100 V, X7R, 1210** | ×2. 100 V rating is mandatory (transient margin). DC-bias derates these to ~1 µF each at 25 V — that's fine. |
| Cin3 | Input HF bypass | 100 nF, 100 V, 0603 | Right at VIN/GND. |
| Cbst | Bootstrap | 100 nF, 50 V, 0402 | BST↔SW. |
| Cout1, Cout2 | Output | **22 µF, 25 V, X7R, 1206** | ×2 on the 5 V rail. |
| Cout3 | Output HF | 100 nF, 50 V, 0402 | optional. |
| RFB1 | FB divider top | **240 kΩ, 1%, 0402** | Sets 5.0 V: Vout = 0.2 V × (1 + RFB1/RFB2). |
| RFB2 | FB divider bottom | **10 kΩ, 1%, 0402** | 0.2 V × (1 + 240/10) = **5.0 V**. |
| Cff | FB feedforward | 22 pF, 0402 | **DNP** (fit only if transient response needs it). |
| REN1 | Enable pull-up | 100 kΩ, 0402 | VBAT→EN (keeps it enabled; add REN2 to set a UVLO). |
| REN2 | Enable divider bottom | — | **DNP**. Populate to set a turn-on UVLO if desired. |
| RDIM | DIM-pin set | per datasheet | **Verify** how DIM must be tied for steady full output (it's a PWM-dimming pin in LED use). Placeholder/DNP until confirmed. |

> **FB reference = 0.2 V** (confirmed by two datasheet mirrors). If a final
> datasheet check shows a different VFB, recompute RFB1 = RFB2 × (Vout/VFB − 1).

### 3.2 Input protection (recommended)

| Ref | Function | Value | Notes |
|---|---|---|---|
| D2 | Input TVS | **SMBJ45A** | Standoff 45 V (won't conduct at 25.2 V), clamp ~73 V (< 100 V IC max). Cheap insurance against hot-plug ringing. |
| Q1 | Reverse-polarity P-FET | (optional) | **DNP.** The LEMO is keyed so polarity is fixed; fit a P-FET in the VBAT line only if you want protection against a miswired connector. |

### 3.3 Voltage divider (faithful to the current node)

| Ref | Function | Value | Notes |
|---|---|---|---|
| R1 | Divider top (VBAT→SENSE) | **200 kΩ, 1%, 0805** | 0805 for voltage rating (sees ~23 V). |
| R2 | Divider bottom (SENSE→GND) | **22 kΩ, 1%, 0805** | As built today. |
| C1 | ADC filter | **100 nF, 50 V, 0603** | SENSE→GND, **in parallel with R2** (not in series with the sense line). |

GPIO7 = 25.2 V × 22/222 ≈ **2.50 V** (6S full) — same headroom under the 3.3 V
ADC ceiling as today. Keep the SENSE net **away from the SW node**.

### 3.4 Connectors (JST-PH, SMD side-entry)

Both I/O points are **JST-PH 2.0 mm SMD side-entry** connectors so the board is
plug-in / serviceable and stays single-side SMD for JLCPCB (no THT surcharge).
PH is rated ~2 A/contact — fine for the ~1 A rails.

| Ref | Type | Pins | To |
|---|---|---|---|
| J1 | S2B-PH-SM4-TB | **VBAT**, **GND** | LEMO lead cable (raw pack) |
| J2 | S3B-PH-SM4-TB | **5V**, **SENSE**, **GND** | Heltec 5V pin, GPIO7, GND |

**Mating cables (off-board, buy or build — not in the PCB BOM):**
- **J1 ↔ LEMO:** crimp the LEMO's two leads into a **PHR-2** housing with **SPH-002T-P0.5S**
  contacts → *zero solder* on this link.
- **J2 ↔ Heltec:** a 3-wire pigtail — **PHR-3** housing + 3 crimp contacts on the
  board end; the other end's three wires solder **once** to the Heltec `5V`,
  `GPIO7`, and `GND` pads (the Heltec is a bare module, so its side is always a
  solder joint — but the board side now unplugs).

So the only remaining hand-soldering is the 3 wires at the Heltec; the LEMO link
is crimp-only and everything is serviceable.

> **Soldering reduced, not eliminated:** JLC solders J1/J2 to the board; you crimp
> the cables. The Heltec module itself has no mating connector, so its 3 pads are
> the one unavoidable solder point.

---

## 4. Power budget (sizing sanity check)

| Load | Current @ 5 V | When |
|---|---|---|
| Heltec, LoRa-only idle | ~30–40 mA | normal reporting |
| Heltec, WiFi config portal | ~120–150 mA avg, ~350 mA peak | during setup |
| LiPo charge (Heltec onboard charger) | ~500 mA, tapering | whenever a pack is connected and the cell isn't full |
| **Worst-case continuous** | **~0.65 A** (portal + charge) | brief, during setup with a low LiPo |
| **Peak** | **< 1 A** | TX burst + full charge |

MP9486A is rated 1 A continuous (3.5 A internal current limit), so peaks have
headroom and the LiPo bridges anything transient. Thermals at 25 V→5 V/0.65 A
(~85 % eff) are gentle for a SOIC-8-EP with a ground-pour pad.

---

## 5. Board outline & stack-up

- **Size:** **40 × 20 mm**, rounded corners (see
  [`board_outline.svg`](board_outline.svg)). Width is set by the enclosure's
  south channel (~20 mm); length has room to grow there if ever needed.
- **Stack-up:** 2-layer, 1.6 mm FR4, 1 oz copper (JLCPCB default).
- **Mounting:** 2 × **M2** holes (2.2 mm dia) at **diagonal corners** —
  NW (4, 4) and (32, 16) board-local — which keeps the central band + east edge clear
  for the regulator + input cluster. Two diagonal points fully locate the board.
- **Pours:** ground pour both layers, stitched with vias.

### Layout rules (matter more than the schematic for a switcher)

1. **Tight input loop:** Cin1/Cin2 → U1 VIN → U1 GND/EP → D1 must enclose the
   smallest possible area. This is the #1 EMI/stability driver.
2. **SW node small & fat:** the SW copper (U1 SW → L1 → D1 cathode) carries the
   switching edge — keep it compact but wide; don't run sensitive traces near it.
3. **FB is quiet:** route RFB1/RFB2 → FB away from SW and L1; tap Vout for FB at
   the output caps.
4. **EP thermal:** solder U1's exposed pad to a copper pour with several thermal
   vias to the bottom-layer GND pour.
5. **Divider isolation:** keep R1/R2/C1/SENSE on the opposite side of the board
   from SW; SENSE is a high-impedance ADC node.

---

## 6. JLCPCB ordering

- **Fab:** 2-layer, 1.6 mm, HASL or ENIG, default copper.
- **Assembly:** "Economic/Standard PCBA," **top side only** (all parts incl. the
  J1/J2 SMD JST connectors are on F.Cu — single-side, no THT surcharge).
- **Files to generate from KiCad** once the project is captured:
  - Gerbers + drill (`kicad-cli pcb export gerbers` / `drill`)
  - BOM (`bom.csv`, see [`bom.csv`](bom.csv))
  - CPL / pick-and-place (`kicad-cli pcb export pos --format csv`)
- **Confirm at order time:** every LCSC code's stock + Basic/Extended status
  (Extended parts add a per-reel loading fee). Prefer Basic parts for the
  passives; U1, L1, D1, D2 will likely be Extended.

---

## 7. Enclosure integration

The shell ([`enclosure/node_enclosure.scad`](../enclosure/node_enclosure.scad))
**v11** hosts this board (changes applied + OpenSCAD-compiled):

- **Removed** the buck locating recess + its variables.
- **Widened the south channel** `ch_s` 13.5 → **20 mm** to seat the 18 mm board
  (`inner_w`/`outer_w` grow ~6 mm → outer **75.6 × 60.7 × 24.4 mm**).
- **Board bay:** two M2 standoff bosses (`psu_holes` at board-local NW (4,4) and
  (32,16)) the 40 × 20 board screws down onto; bosses top at z = 4.5.
- **South-rib notch** for J2's 5V/SENSE/GND wires to cross to the Heltec.
- **`psu_gap_e`** holds the board's east edge back so J1 + its JST plug clear the
  LEMO's rear cups — the model echoes **15.6 mm** clearance.
- **Wire routing:** J1 (VBAT/GND) faces east into the LEMO/east bay; J2
  (5V/SENSE/GND) faces north to the Heltec. Vent slots over the south region kept.

ENCLOSURE.md §2 already anticipated this ("the planned sensor PCB combines the
buck + divider… then this becomes a single board footprint"). The SCAD change is
a separate task once the board outline is final.

---

## 8. Files in this directory

| File | What |
|---|---|
| `README.md` | This spec. |
| `bom.csv` | JLCPCB-format BOM (verify LCSC codes at order). |
| `board_outline.svg` | Dimensioned 40 × 20 mm outline + hole positions. |
| `brickdup_psu.kicad_pro` | KiCad 10 project. |
| `brickdup_psu.kicad_sch` | Schematic — **ERC electrically clean** (0 connectivity errors). |
| `brickdup_psu.kicad_pcb` | Board: 40 × 20 mm Edge.Cuts + 2× M2 holes, all 22 parts placed (auto-spread, **0 pad overlaps**) + netted, GND pours both layers. **Routing still to do** (the 41 unconnected DRC items are the ratsnest). |
| `gen_kicad.py` / `gen_pcb.py` | Generators that produce the `.kicad_sch` / `.kicad_pcb` (run with KiCad's bundled python). |

### Using the KiCad project

1. **Open `brickdup_psu.kicad_pro` in KiCad 10.** The schematic uses **net-label
   connectivity** (no drawn wires) — every pin carries a local net label, which is
   a valid KiCad style and keeps the generated file robust. The human-readable
   schematic is [`docs/pcb_schematic.svg`](../docs/pcb_schematic.svg).
2. **Verify the MP9486A pinout** against the official datasheet/footprint and fix
   `gen_kicad.py`'s `PINS["brickdup:MP9486A"]` + symbol if needed, then re-run, OR
   swap in the SnapEDA MP9486A symbol. **Run ERC.**
3. In the PCB editor: parts are already placed (rough) and netted, with GND pours
   on both layers. **Arrange the placement, then route** per §5, then press `B`
   to fill the pours. After any schematic change, run **Update PCB from schematic**.
   (Re-run `gen_pcb.py` to regenerate the board from scratch if you prefer.)
4. Export Gerbers + drill + BOM + CPL for JLCPCB (§6).

> The headless `kicad-cli` ERC reports ~44 *warnings* of the form "configuration
> does not include the symbol/footprint library 'Device'/'Capacitor_SMD'/…".
> These are an artifact of running ERC with no initialized KiCad config — they
> **disappear when you open the project in the KiCad GUI** (which has those
> standard libraries registered). They are not electrical errors.

---

*See also: [`WIRING.md`](../WIRING.md) (node power/sense), [`REFERENCE.md`](../REFERENCE.md)
(pins), [`ENCLOSURE.md`](../ENCLOSURE.md) (shell).*
