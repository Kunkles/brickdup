# brickdup — Session Handoff (updated 2026-07-17)

Self-contained context for continuing in a fresh session. Read this plus the
repo docs (README, WIRING, REFERENCE, pcb/README, pcb/carrier/README,
enclosure/CARRIER_ENCLOSURE.md) for the full picture.

---

## What this project is

**brickdup** — a LoRa wireless battery-voltage monitor for film/video sets.
Sensor nodes tap into camera batteries (4S "onboard" bricks or 6S "block"
batteries) and broadcast readings to a handheld receiver with an e-ink display.
The user (Ryan) is a film-industry tech (DIT-adjacent) building this for real
on-set use.

- **Repo:** https://github.com/Kunkles/brickdup (local: `~/Documents/brickwatch/`)
- **Active branch: `carrier-v02`** (all current work; pushed). `psu-pcb` =
  v0.1 board PR (#1, open). `main` is behind both.
- **Firmware version:** v0.5.9 (`FW_VERSION` in each sketch; CHANGELOG.md)
- **CI:** GitHub Actions builds all sketches on every push; artifacts =
  `brickdup_{universal,onboard,block,receiver}.bin`. Tags `v*` → Release.

## Hardware on hand

| Unit | Board | Role |
|---|---|---|
| 2× nodes | Heltec WiFi LoRa 32 V3 (915MHz, ESP32-S3 + SX1262, 0.96" OLED) | sensor nodes |
| 1× receiver | Heltec **Wireless Paper** V1.2 (2.13" e-ink) | handheld |
| Node LiPo | MakerHawk **1100mAh** 1S JST1.25 — **41.4×25.15×10.25mm (calipered!)** | bridge cell |
| Receiver LiPo | MakerFocus **3000mAh** 1S JST1.25 — 65×35×10mm | solo all-day |
| Bench supply | SPS-3010 (0–30V/10A) | bring-up |
| **5× v0.1 PSU boards** | `pcb/brickdup_psu` 40×20, JLC-assembled | buck+divider (replaces Pololu) |
| **5× v0.2 carriers** | **IN PRODUCTION** at JLC (ordered 2026-07-17) | sockets the Heltec |
| Cap kit | VANXY 0603 600pc 1pF–10µF | Cff experiments |

Arduino IDE 2.x, Heltec package 3.3.8; receiver board = "Wireless Paper"
(e-ink lib hard-requires), nodes = "Heltec WiFi LoRa 32(V3)"; USB CDC On Boot
= Enabled; RadioLib, Heltec ESP32 Dev-Boards, heltec-eink-modules.

---

## 1. THIS SESSION'S ARC — hardware state

| Thing | State |
|---|---|
| **v0.1 boards bench** | Divider verified (14V → 1.36V @ GPIO7, ratio ≈ design; no cal change). Buck regulates 5.0V under load but **whines** — root cause: hysteretic MP9486A + all-ceramic Cout starves FB of ripple → audible burst mode. Fix = **Cff ripple injection ~470pF** (across RFB1). Board #1 also had bad hand-solder joints (erratic screech/heat, pressure-sensitive) — reflow of U1 improved it; fresh board = steady quiet-ish whine only. Resistor load gets hot = normal (1W in a ¼W part). |
| **v0.1 Cff rework** | Pads live in a canyon (L1/J1). Plan = **pigtail method**: wire legs onto a 0603 470pF at the bench, attach to **L1 east pad (+5V)** and **RFB2 south end (FB)** — verify ~250kΩ across the two points first. Map: `docs/pcb_cff_rework.svg`. Status unclear (Ryan attempted via tape/hot-plate adventures); now **OPTIONAL** — v0.2 ships Cff populated. Acceptance test: whine gone + no-load output steady ~5V (was wandering 5–6.5V). Failure modes are self-grading: unchanged = open joint; output <1V = bridge across RFB1. |
| **v0.1 J1/J2** | JST mouths face INWARD (v0.1 bug, accepted): electrically fine, harness U-turns. Fixed properly in v0.2. D2 TVS was de-populated by JLC (clearance) — board fine without it. |
| **v0.1 enclosure** | v11 STLs exported to `enclosure/stl/` (base/lid/plunger/both). Ryan printing these for interim v0.1 units. 2 plungers per unit; first assembly = the overdue dry-fit (check M2 bosses, J1↔LEMO harness room, J2 wires vs LiPo, lid vs LEMO nut). |

## 2. THE v0.2 CARRIER — designed, ordered, in production

`pcb/carrier/brickdup_carrier` — 62×44mm, sockets the **Heltec V3** on 2×18
female headers (**8.5mm height, NOT low-profile** — that clears L1 under the
module; ROW_SPACING **22.86mm caliper-verified**, pin pitch verified). v0.1
buck+divider carried over net-identical; 5V/SENSE/GND on copper (SENSE =
HDRA.18 = **GPIO7 — zero firmware change**). Full pin budget table in
`pcb/carrier/README.md`.

Connectors: **J1** VBAT in (side-entry JST-PH, mouth EAST → LEMO wall);
**SW1** series power switch JST + JP1 solder-jumper bypass (solderless alt:
wire loop crimped in a JST plug); **BTN1** = PRG/GPIO0, **BTN2** = RST — both
**vertical THT** JST (B2B-PH-K-S), wires exit UP to lid buttons, ≥2mm clip
clearance verified. Breakouts (DNP): BRK1 SPI ×8 (future W5500 lands here),
BRK2 ADC ×8, BRK3 I2C ×4. **Cff populated: 470pF 0603 machine-placed.**
Design goal held: **zero soldering for Ryan** (sockets + THT JSTs ride JLC's
hand-solder line).

**Order (2026-07-17, qty 5 assembled):** BOM matched 23/23 — carryover v0.1
codes + Cff=**C22396**, verticals=**C131337**, sockets=**C2905422**
(KH-2.54FH-1X18P-H8.5), RFB2→**C60490** (Yageo, Basic C25744 was short),
J1=C295747. Fab: 2-layer, 1.6mm, HASL-LF, 1oz, 0.3mm via, green. Fab package:
`pcb/carrier/fab/` (gerbers zip + jlc_bom.csv + jlc_cpl.csv).

**⚠️ ORDER WATCHLIST (time-sensitive):**
1. **DFM/placement review** (~4–6h post-order, Order History + email):
   **verify socket HDRA/HDRB ROTATION** — JLC's library rotation differs 90°
   from KiCad; Ryan was rotating them in JLC's placement editor to lie along
   the silk rows (east-west). The CPL centre-offset for these pin1-origin
   footprints is already fixed in `convert_jlc.py` (`CENTRE_FIX`).
2. **Confirm Production File** gate → should match `docs/carrier_3d_top.png`.
3. **Confirm Parts Placement** gate → U1 pin-1 dot SE corner; J1 mouth east
   off-board; 3 vertical JSTs standing on the south strip.
4. Engineer emails (Doris-style): design has margin everywhere v0.1 was
   flagged (D2↔D1 4.9mm now); expect quiet.

**Quality gates passed:** ERC 0; DRC 0/0; deterministic hand floorplan (the
overlap-solver was retired after it scrambled analog grouping); envelope
audit (no courtyard overlaps, SMT pairs ≥0.75mm); **executable layout rules**
`check_layout.py` (SW hot-loop ≤10mm → 8.4; Cbst→BST ≤3.5 → 2.5; sense
divider ≥10mm from SW → 12.8; Cin3→VIN ≤6 → 3.6); orientation asserts (JST
mouth directions, socket pin-1 east — derived from v0.1's mistakes, build
fails if violated).

**NOT done:** the long-queued **v0.1 design review** (deep datasheet pass) —
ordered anyway, findings would inform v0.3. Cff=470pF is engineering-sized,
not bench-proven (swap on v0.2 = easy open 0603; range 470pF–1nF).

## 3. v0.2 ENCLOSURE — functional geometry done, aesthetics PARKED

`enclosure/carrier_enclosure.scad` (v0.5) + spec `enclosure/CARRIER_ENCLOSURE.md`.

**Functional (SOLID, keep):** tub for the 62×44 board, 4× M2 bosses; LiPo bay
under the WEST half (lead runs up the west edge into the ~11mm socket gap to
the Heltec's underside battery JST); **antenna compartment** per Ryan's spec +
H1 reference: full-width north side, covered front/ends/roof, roof FLUSH with
lid top, **underside fully open**, SMA saddle at the WEST end (axis east) —
50mm whip incl SMA male, Ø8, pigtail 169mm; whip + barrel ≈ 61mm inside the
62mm wall, tip protected at the NE corner. East wall: LEMO + USB-C. Lid: OLED
window, 2 flexure-tab wells (buttons are WIRED — place anywhere). Z-stack:
socket gap under Heltec ≈ **11mm** (8.5 socket + 2.5 male header plastic) —
L1 (~5mm) clears with margin.

**⚠️ DISCREPANCY CAUGHT WRITING THIS HANDOFF:** the enclosure bay assumed a
603450-style pouch (50×34×**7**) on **8mm** bosses — but the actual node LiPo
(MakerHawk 1100, calipered previously) is **41.4×25.15×10.25mm**. The bay is
**too shallow**: raise `boss_h` to ~11mm (footprint is fine — smaller than
assumed). Adjust before any print; ripples into `inner_h`/`base_h`.

**Aesthetics: Ryan judged the sculpted look "absolute garbage" — HOLD.** Do
not resume blind CSG-sculpt iteration (token sink, wrong tool). Style donor:
`enclosure/H1_V1.2.3mf` (Meshtastic H1 case; parts Case Front V1.2 / Case
Rear Thick v2 / Buttons V1.2), reference photo
`enclosure/reference/antenna_mount_ref.png`, antenna cradle extracted 1:1 at
`enclosure/reference/h1_antenna_cradle.stl`. Facts: H1 interior (~60×41) is
SMALLER than the carrier → direct mesh stretch evaluated and REJECTED. Likely
paths: Ryan sculpts in Fusion over the SCAD's dimension skeleton, or print
the plain functional tub for bench duty.

**‹MEASURE› gates:** socket stack height (~15.5 assumed), SMA barrel + whip
diameter, LEMO dims (carry v11 `lemo_nut=13`), USB-C XY, OLED window XY,
flexure tuning, LiPo bay depth fix above.

## 4. TOOLCHAIN GOTCHAS (hard-won this session — do not relearn)

- **freerouting v2 headless**: routes but never writes the SES? Set
  `"gui": {"enabled": false}` in `$TMPDIR/freerouting/freerouting.json`.
  Jar = v2.2.4 from GitHub releases; /tmp AND the session scratchpad get
  cleaned between sessions — re-download when missing. `-mp 12` suffices.
- **KiCad bundled python** for all pcbnew scripts:
  `/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3`
- `pcbnew.WriteDRCReport` **crashes** standalone → use `kicad-cli pcb drc
  --format json`, then `pcb/carrier/fix_thermals.py` (heals starved thermal
  reliefs by setting those pads to solid pour connection), re-run DRC.
- **JLC CPL**: JLC reads Mid X/Y as part CENTRE; KiCad pos export gives the
  footprint ORIGIN (pin 1 for PinSocket_1x18 → half-body offset).
  `convert_jlc.py` `CENTRE_FIX` handles it. JLC per-part library ROTATIONS
  can still differ 90° — fix in their placement editor, not by CPL round-trips
  (re-upload wipes the manual part picks).
- **Pipeline** (`pcb/carrier/`): gen_kicad → erc → gen_pcb (runs envelope
  audit + check_layout asserts) → ../export_dsn → freerouting → apply_route →
  drc json → fix_thermals → drc → export gerbers/pos → convert_jlc.
- OpenSCAD 2021.01: run with sandbox disabled or it's SIGKILLed; GUI does
  **not** auto-reload changed files (Design → Automatic Reload and Preview).
- 3MF = zip of XML; Bambu parts in `3D/Objects/*.model`, names in
  `Metadata/model_settings.config`. Meshes convertible to STL by parsing.
- JLC BOM upload: arbitrary strings in the LCSC column can 500 their backend
  — leave unknown codes EMPTY.

## 5. OPEN ITEMS, priority order

1. **JLC order gates** (§2 watchlist) — socket rotation is the one real risk.
2. Boards arrive → **plug-together bring-up**: Heltec into socket (dry-fit
   pin-1 orientation on loose sockets if self-soldering ever happens),
   resistor load first (current limit 0.3–0.5A), listen for whine (Cff is in
   this time), then full node.
3. v0.1 interim units: optional Cff pigtail rework; print v11 enclosures;
   field them.
4. Enclosure: **fix LiPo bay depth (boss_h → ~11)**; caliper pass when
   hardware lands; decide aesthetics path (Fusion vs plain tub).
5. **v0.1 design review** (never run) — before any v0.3 spin.
6. Backlog: W5500 Ethernet via BRK1 (tally/platform ideas — see "Tally Light"
   session + memory), firmware roadmap items below.

## 6. Key files

| Path | What |
|---|---|
| `pcb/carrier/` | v0.2 project: generators, checks, fab package, README (pin budget) |
| `pcb/HANDOFF.md` | v0.1 handoff incl. bench findings (§2a) |
| `docs/carrier_3d_*.png` | v0.2 renders (current); `docs/carrier_*_layout.svg` one rev stale |
| `docs/pcb_cff_rework.svg` | v0.1 Cff pigtail rework map |
| `enclosure/carrier_enclosure.scad` + `CARRIER_ENCLOSURE.md` | v0.2 shell + spec |
| `enclosure/H1_V1.2.3mf` + `reference/` | style donor + extracted cradle + photo |
| `enclosure/stl/` | v11 printables for v0.1 |
| `pcb/order_records/` | v0.1 JLC order provenance |

---

## FIRMWARE / SYSTEM REFERENCE (stable — unchanged this session)

**Radio:** 915.0MHz, BW125, SF9, CR4/5, sync 0xAB, 17dBm, preamble 8; TX/10s.
**Packet:** `T:<OB|BL>,I:<permId>,V:<float>,S:<0|1|2|3>[,B:<lipo>][,M:<name>]`
(S:3 = source removed/dead). **Identity:** `ND-XXXX` from MAC (universal
sketch); id = AP name `Brickdup-ND-XXXX` / pw `brickdup` / 192.168.4.1.

**Universal node** (recommended): one 200k/22k divider (25.2V→~2.5V, GPIO7),
battery type = runtime setting (portal or long-press PRG; thresholds OB
13.5/12.8, BL 21.0/20.0, editable, NVS). Power: camera batt → buck → Heltec
5V pin (+ charges bridge LiPo); divider → GPIO7. LiPo bridges swaps; node
reports S:3 + own `B:` level when source <5V. `USB_TEST_MODE 0`,
`DEMO_VOLTAGE_ON 0` for real monitoring.

**Feature inventory (v0.5.9, all working):** node OLED 7-seg voltage UI,
captive config portal (rename/type/calibration/WiFi-off/OTA), PRG gestures
(tap WiFi, long type, triple sleep). Receiver: e-ink 5/page list, SoC% +
time-to-empty, RSSI bars, OK/WARN/CRIT/STALE/LOST/DEAD states, WiFi dashboard
(live /data JSON), NVS roster, triple-tap sleep.

**Firmware roadmap (open):** channel/group selection, WiFi STA + mDNS, BLE +
iOS app, VCLX/NiMH block mode, CRIT buzzer, deep sleep, user manual.

**Conventions:** commits imperative + `Co-Authored-By: Claude <model>
<noreply@anthropic.com>`; push after changes. Diagrams = clean SVGs in
`docs/`, GitHub light/dark safe. Ryan prefers portal config over recompiles,
physical-button UX, visible feedback, honest caveats. Display layout is liked
— don't redesign unprompted.

**Firmware gotchas:** e-ink lib needs exact board; OLED needs Vext (GPIO36
LOW) first; GPIO0 = strap (never hold at boot); ADC2 vs WiFi conflict
(receiver battery); Heltec boards.txt hardcodes 8MB OTA partitions.

---

## OPEN QUESTION — camera battery consistency (raised 2026-09-01)

Goal: the handheld should agree with the number the camera shows, so people
trust it. Two different features, decide after checking a real camera:

1. **Calibration path (cheaper, preferred if it works):** use the camera's
   reported voltage as a reference to trim that node's calibration factor
   (the config portal field already exists). No radio traffic, no gateway,
   keeps working when no computer is on the cart. Fixes ADC error, which is
   the dominant disagreement (ESP32-S3 ADC non-linearity >> the 1% divider).
2. **Live rebroadcast:** computer → gateway → LoRa as a `T:CAM` packet.
   Needed only if you want the camera's *percentage* (its own curve) shown.
   Airtime is a non-issue at the 10s heartbeat — costs exactly one more
   node's worth. Gateway = spare Heltec on USB serial (~1h), or the
   backlogged W5500 on BRK1 for a proper cart-side bridge.

**To check at the camera:** does it report volts, percent, or both? And take
**simultaneous readings** (camera's number vs. a brickdup node on the same
battery) at **two charge states** — one point tells you offset error only,
two points separate offset from gain, which is what calibration needs.

**Latent bug found while reading the parser:** `parsePacket()`
(receiver .ino ~L288) resets `permId`, `name`, and `lipo` but NOT `*voltage`
or `*status`. Harmless today (call site declares them fresh each packet) but
a `T:CAM` packet omitting `V:` is exactly the case that would expose it.
Fix before adding any packet type that doesn't carry voltage.
