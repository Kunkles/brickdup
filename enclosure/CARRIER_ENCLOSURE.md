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
  - **USB: NO opening in this version (decided 2026-07-24).** The port is
    recessed ~9 mm behind the outer wall face (module east edge 6.3 mm
    inboard of the board edge, + gap + 2.4 wall), so a usable opening must
    admit the cable OVERMOLD (~13 × 8) and, since the port axis is only
    ~4.4 mm below the base rim, has to be a top-open notch with a matching
    lid-skirt notch. All that geometry is in git history (commit b5b8ceb)
    if wanted later — for now: lid-off USB for the initial flash, OTA after.
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

**Current shell (v0.6, 2026-07-24): button wells DROPPED for now** — the lid
is OLED-window-only. Because the buttons are wired (BTN1/BTN2 JSTs), wells
can be added back anywhere on the lid whenever the button plan firms up;
the concept below is kept for that moment.

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

### 5b. LEMO panel connector (battery input) — EAST BAY

- **DECIDED (2026-07-24): the tub gets a v11-style east bay (`bay_l = 20`).**
  A plain tub leaves 0.5 mm east of the board — but J1's mating JST plug +
  wire bend need ~10–12 mm, and the LEMO body intrudes ~10 mm past the wall
  (12 mm deep, measured). Without the bay the LEMO rear also lands in the
  board-edge/battery z-band (body ≈ z 6–18 vs pouch top 12.2, board
  14.5–16.1). The bay puts LEMO rear + nut, J1 plug, and the pigtail U-turn
  **east of the board footprint**, so the full-footprint under-board LiPo
  bay (§5a) is completely unaffected. Case grows ~20 mm east (≈88 mm long).
- **LEMO in the bay's east wall**, centre height `lemo_z = 14` ‹MEASURE›
  (Ø13 nut clears the floor), y = bay centreline ‹MEASURE — align with J1's
  mouth at dry-fit›. Short 2-wire pigtail J1 → LEMO, crimped JST-PH one end.
- **v11 measured hole carried over 1:1**: double-D, Ø8.9 with the two flats
  8.2 across, flats LEFT+RIGHT of the hole (anti-rotation). The v11
  `lemo_nut = 13` lid-lip relief is NOT needed here — the carrier wall is
  much taller, so the nut (top ≈ z 18.5) sits well below the lid lip. Leave
  finger/wrench room around the nut inside.

### 5c. RF jack (LoRa antenna) — plain bulkhead, WEST wall

**DECIDED (2026-07-24): back to the v11-style perpendicular bulkhead.** The
H1-donor protected-channel/cradle direction is dropped along with the rest
of the sculpted styling (the reference material stays in
`enclosure/reference/` if the idea ever returns).

- **SMA bulkhead jack through the WEST wall** (u.FL is at the module's west
  end — shortest pigtail), whip sticks straight out west.
- **v11 measured hole carried over 1:1**: Ø6.5 with a single flat on the
  bottom (5.9 flat-to-round), nut inside.
- Height `sma_z = 21.5` ‹MEASURE›: barrel clears the board top (z≈16.1)
  below and the module underside (z≈27.1) above; the bulkhead body intrudes
  over the board's west strip, under the module overhang.
- Reserve inside: nut + wrench room, and the **u.FL→SMA pigtail service
  loop** (u.FL is ~30-cycle rated — never taut). Keep the LiPo pouch and its
  lead clear of the coax run (pigtail is 169 mm — coil the slack away from
  the west edge lead path).

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
