# Carrier (v0.2) enclosure brief — supersedes the v11 node shell layout

The v0.2 carrier changes the enclosure's whole internal architecture. This
brief captures the direction before any OpenSCAD work; the existing
`node_enclosure.scad` (v11) stays as-is for v0.1 boards.

## 1. What the carrier changes

| v0.1 shell (v11) | v0.2 carrier shell |
|---|---|
| Heltec on 16 mm towers + separate PSU board on bosses | **One board**: carrier mounts on 4× M2 bosses; Heltec rides the socket (~8.5 mm above carrier) |
| 3-wire J2 harness routed around the LiPo (wire trench) | gone — copper |
| Captive piston plungers pressing the Heltec's own buttons (fixed XY, `‹MEASURE›` guesses) | **Lid flexure buttons anywhere** — wired to BTN1/BTN2 JSTs; switch on SW1 |
| Lid-lip relief for LEMO nut | keep concept; wall positions change |

## 2. Fixed geometry (from the board — these are known, not ‹MEASURE›)

- Carrier: **62 × 44 mm**, 4× M2 holes at (3.5, 3.5), (58.5, 3.5), (3.5, 40.5),
  (58.5, 40.5) (board origin NW, y south).
- **East wall**: J1 VBAT JST mouth (LEMO pigtail) + the Heltec **USB-C**
  (module east end) → USB access port goes in the east wall, above the LEMO
  entry. Both on one wall = one "service side".
  - **USB is recessed ~9 mm** behind the outer wall face (module east edge is
    6.3 mm inboard of the board edge, + gap + 2.4 wall). A cable's overmold
    must pass THROUGH the wall to seat the plug → the wall slot is
    overmold-sized (~13 × 8), not shell-sized. Best-effort access: chunky
    overmolds won't reach → lid-off USB; OTA covers field updates.
  - **J1 stacks almost directly below the USB port** (both at board y ≈ 19.5;
    JST at board level, USB ~12–15 mm up → ~5 mm daylight). The J1→LEMO
    harness must turn south immediately out of the JST — no slack bowing up
    into the USB path. Verify at dry-fit.
- **South wall**: SW1 / BTN1 / BTN2 JST mouths at x ≈ 11 / 20.5 / 30 — wires
  rise from these to the lid flexures or a south-wall switch.
- **West end**: Heltec antenna (u.FL) — keep the antenna pocket/SMA pigtail
  clearance on the west, same as v11 thinking.
- OLED faces up through the lid window (Heltec top surface ≈ carrier + 8.5 mm
  socket + ~3.5 mm module ≈ **12 mm over the carrier**, much lower than the
  16 mm towers).

## 3. Z-stack (approximate — verify at dry-fit)

```
lid ──────────────────────────────
   flexure buttons → wired to BTN1/2 (no pistons/tubes)
   OLED window
   ~2–3 mm clearance over Heltec top
Heltec module (~3.5 mm incl. OLED)
socket standoff  ~8.5 mm   ← L1 (~5 mm) + all buck parts + LiPo JST plug
carrier PCB       1.6 mm
M2 boss          ~12.5 mm  ← full-footprint LiPo bay under the board (§5a):
                              pouch 10.25 + THT stub clearance ~1.5 + margin
base ─────────────────────────────
```
Inner height ≈ **26–28 mm** with the under-board LiPo bay (§5a) — still in
v11's ballpark, and the footprint stays at board size instead of growing a
side bay.

## 4. Buttons — the flexure concept (Ryan's preference)

- **Living-hinge cantilever tabs in the lid**: U-shaped slot leaves a tab
  attached on one edge; a small boss on the tab's underside presses a
  **panel-mount or wired tact switch** connected to BTN1/BTN2. Print flat,
  ~0.8–1.2 mm tab thickness, ≥8 mm tab length for a comfortable click.
- Because buttons are *wired*, the flexures go wherever ergonomics want them
  (top of lid, side wall) — no alignment to PCB coordinates required.
- **SW1 power switch**: small panel slide/toggle in the south or east wall
  (rated ≥30 V DC / 1 A), or bridge JP1 and omit.

## 5. Reserved volumes — hard requirements (battery, LEMO, RF)

These three MUST have dedicated space in the shell; everything else designs
around them.

### 5a. Bridge LiPo bay

- Battery: MakerHawk 1100 mAh 1S pouch, **41.4 × 25.15 × 10.25 mm
  (calipered)** plus lead + strain relief. JST-1.25 plug goes to the connector
  on the **underside of the Heltec module** — the socket gap is exactly where
  the plug and lead live, so the lead routes up over the carrier's west edge
  into that gap. Longer lead is fine (Ryan's call — no LiPo on the PCB).
- **UNDER the carrier, full board footprint** (decided 2026-07-17): the whole
  under-board volume is battery space, so the pouch can land wherever the
  dry-fit says — no west-half-only rule. M2 bosses at **~12.5 mm**: pouch
  10.25 (the earlier 8 mm/603450 assumption was wrong) **+ clearance for the
  THT pin stubs protruding below the board** (socket rows + JST legs, ~1.5 mm
  assumed, ‹MEASURE› on real boards — stubs must never press the pouch; a
  thin foam pad on the floor is cheap insurance). Adds ~12 mm to the Z-stack
  (total inner ≈ 31–33 mm).
- Soft preference still WEST: shortest lead run to the west-edge socket gap,
  and it keeps the pouch away from under the buck island (U1/L1, the only
  warm parts, east) — but that's placement guidance, not geometry.
- Alternative if under-board is rejected at dry-fit: a side bay west of the
  carrier (grows the footprint ~36 mm — much bigger box; not preferred).
- Rules unchanged: **never compress the pouch** — retention lip + foam pad,
  no squeeze; keep it off the antenna coax.

### 5b. LEMO panel connector (battery input)

- **East wall** (the service wall), directly outboard of **J1's mouth**
  (J1 centre is at board y ≈ 19.5, mid-height of the east wall). Short
  2-wire pigtail J1 → LEMO, crimped JST-PH one end.
- **v11 measured hole carried over 1:1**: double-D, Ø8.9 with the two flats
  8.2 across, flats LEFT+RIGHT of the hole (anti-rotation). The v11
  `lemo_nut = 13` lid-lip relief is NOT needed here — the carrier wall is
  much taller, so the nut (top ≈ z 18.5) sits well below the lid lip. Leave
  finger/wrench room around the nut inside.

### 5c. RF jack (LoRa antenna) — protected parallel mount

**Design reference: `enclosure/reference/antenna_mount_ref.png`** (Meshtastic
handheld case, 2026-07-17). Ryan wants that antenna treatment, not a plain
perpendicular bulkhead:

- **SMA jack recessed in a corner pocket** at the WEST end (u.FL is right
  there — shortest pigtail), with the jack axis turned so the **antenna runs
  PARALLEL to the case lengthwise** instead of sticking straight out.
- A **molded shoulder/wing wraps the SMA base** — the case itself shields the
  connector joint (the fragile point) from knocks; the whip lies alongside
  the body in a shallow protective channel formed by the case rim.
- **DECIDED (2026-07-17): NORTH wall.** Pocket at the **NW corner**, jack
  axis pointing EAST — antenna lies along the north wall exterior.
- **SMA hardware: same bulkhead jack as originally planned** — v11 measured
  hole carried over 1:1: Ø6.5 with a single flat on the bottom (5.9
  flat-to-round), nut inside the pocket.
- **Antenna whip = 50 mm, protected FULL LENGTH**: the guard channel runs the
  entire north wall — SMA barrel (~11 mm) + 50 mm whip ≈ 61 mm vs the 62 mm
  case length, so the whip tip lands at the NE corner and nothing pokes past
  the case envelope. The channel rim must stand proud of the whip's full
  diameter for its whole run (a parapet/trench, not just a base shoulder),
  with an open top/side so the antenna can still be threaded on and radiate.
- Still reserve: nut + wrench access in the pocket, finger room to thread the
  antenna on, and the **u.FL→SMA pigtail service loop** (u.FL is ~30-cycle
  rated — never taut).
- Keep the LiPo pouch and its lead clear of the coax run.
- ‹MEASURE›: SMA barrel exact length/diameter, whip diameter (sets channel
  width/depth), pocket depth so fingers can thread the antenna at the NW end.
- If a second RF jack is ever needed (WiFi ext antenna), leave conceptual
  room beside the pocket — note it, don't cut it yet.

## 6. Open ‹MEASURE› items for the SCAD pass

1. Socket standoff height (8.5 mm typ female header) + Heltec total height.
2. USB-C port XY on the module east face (offset from board centreline) +
   plug-axis height over the board (SCAD assumes 13.6) + widest overmold that
   must fit the wall scoop.
3. u.FL position on the module (west end) → SMA jack height in the west wall.
4. ~~LEMO panel hole~~ ✓ v11 measured double-D (8.9/8.2) + SMA flat (6.5/5.9)
   carried over; only lemo_z (wall height position) still ‹MEASURE›.
5. Lid flexure tab dimensions after a print test (tab length/thickness/boss).
6. ~~ROW_SPACING~~ ✓ verified 22.86 mm with calipers (2026-07-02).
7. ~~Actual LiPo pouch dimensions~~ ✓ calipered 41.4×25.15×10.25 (MakerHawk
   1100); lead length still to confirm.
8. Heltec underside battery-JST position (sets where the LiPo lead enters the
   socket gap from the west edge).
9. THT stub protrusion below the board on real JLC-assembled carriers
   (socket rows + JST legs; boss_h assumes ≤1.5 mm — sets pouch clearance).
