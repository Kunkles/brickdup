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
socket standoff  ~8.5 mm   ← L1 (~5 mm) + all buck parts live here
carrier PCB       1.6 mm
M2 boss           ~3 mm
base ─────────────────────────────
```
Inner height ≈ **19–21 mm** — shorter than v11 despite the socket.

## 4. Buttons — the flexure concept (Ryan's preference)

- **Living-hinge cantilever tabs in the lid**: U-shaped slot leaves a tab
  attached on one edge; a small boss on the tab's underside presses a
  **panel-mount or wired tact switch** connected to BTN1/BTN2. Print flat,
  ~0.8–1.2 mm tab thickness, ≥8 mm tab length for a comfortable click.
- Because buttons are *wired*, the flexures go wherever ergonomics want them
  (top of lid, side wall) — no alignment to PCB coordinates required.
- **SW1 power switch**: small panel slide/toggle in the south or east wall
  (rated ≥30 V DC / 1 A), or bridge JP1 and omit.

## 5. LiPo

Heltec's bridge LiPo keeps its JST-1.25 on the module. Pouch pocket in the
base **west of the buck island / under the antenna end**, longer leads OK
(per Ryan: no LiPo on the PCB, longer lead is fine). Never compress the pouch;
retention lip, not squeeze.

## 6. Open ‹MEASURE› items for the SCAD pass

1. Socket standoff height (8.5 mm typ female header) + Heltec total height.
2. USB-C port XY on the module east face (offset from board centreline).
3. u.FL position / antenna clearance west.
4. LEMO panel hole + nut (carry over v11 values `lemo_nut=13` etc.).
5. Lid flexure tab dimensions after a print test (tab length/thickness/boss).
6. Confirm ROW_SPACING 22.86 mm (also gates the PCB order).
