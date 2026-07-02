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
M2 boss           ~8 mm    ← LiPo bay under the carrier's WEST half (§5a)
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

- Battery: 1S ~1100 mAh pouch, plan for **~50 × 34 × 7 mm** (e.g. 603450)
  plus lead + strain relief. JST-1.25 plug goes to the connector on the
  **underside of the Heltec module** — the 8.5 mm socket gap is exactly where
  the plug and lead live, so the lead routes up over the carrier's west edge
  into that gap. Longer lead is fine (Ryan's call — no LiPo on the PCB).
- **Recommended spot: UNDER the carrier, west half.** Raise the M2 bosses to
  ~8 mm and the pouch lies flat beneath the board. The west half is under the
  sense divider (cool); the buck island (U1/L1, the only warm parts) is the
  east half — keep the pouch out from under it. Adds ~7 mm to the Z-stack
  (total inner ≈ 26–28 mm, still comparable to v11).
- Alternative if under-board is rejected at dry-fit: a side bay west of the
  carrier (grows the footprint ~36 mm — much bigger box; not preferred).
- Rules unchanged: **never compress the pouch** — retention lip + foam pad,
  no squeeze; keep it off the antenna coax.

### 5b. LEMO panel connector (battery input)

- **East wall** (the service wall), directly outboard of **J1's mouth**
  (J1 centre is at board y ≈ 19.5, mid-height of the east wall). Short
  2-wire pigtail J1 → LEMO, crimped JST-PH one end.
- Carry over the v11 parametrics: panel hole + **`lemo_nut = 13` lid-lip
  relief** (the v11 fix) so the nut clears the lid. Leave finger/wrench room
  around the nut inside.

### 5c. RF jack (LoRa antenna)

- **SMA bulkhead jack in the WEST wall** (antenna end of the Heltec — the
  u.FL is right there, shortest pigtail, and it keeps RF on the opposite wall
  from the LEMO/USB service side).
- Reserve: ~6.5 mm panel hole, nut + wrench clearance inside, plus a **service
  loop** for the u.FL→SMA pigtail so the lid can open without yanking the u.FL
  (u.FL connectors are ~30-cycle rated — don't make the pigtail taut).
- Keep the LiPo pouch and its lead clear of the coax run.
- If a second RF jack is ever needed (WiFi ext antenna), there's west-wall
  room beside the SMA — note it, don't cut it yet.

## 6. Open ‹MEASURE› items for the SCAD pass

1. Socket standoff height (8.5 mm typ female header) + Heltec total height.
2. USB-C port XY on the module east face (offset from board centreline).
3. u.FL position on the module (west end) → SMA jack height in the west wall.
4. LEMO panel hole + nut (carry over v11 values `lemo_nut=13` etc.).
5. Lid flexure tab dimensions after a print test (tab length/thickness/boss).
6. ~~ROW_SPACING~~ ✓ verified 22.86 mm with calipers (2026-07-02).
7. Actual LiPo pouch dimensions + lead length (§5a assumes 603450, 50×34×7).
8. Heltec underside battery-JST position (sets where the LiPo lead enters the
   socket gap from the west edge).
