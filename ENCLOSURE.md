# brickdup — 3D-Printable Enclosure Design Brief

A complete brief for designing 3D-printable enclosures for the brickdup system.
Written so an LLM or CAD tool can produce parametric models (OpenSCAD,
Fusion 360, etc.). **Dimensions marked `‹MEASURE›` must be confirmed with
calipers before cutting final tolerances** — verify against the actual hardware.

There are **two enclosures**:
1. **Sensor node** — rugged, mounts on/near a camera battery, powered by that
   battery (no internal cell). Survives a set.
2. **Receiver (handheld)** — pocketable, e-ink window, internal LiPo, button
   access. The "remote" you carry.

---

## 0. Global design parameters (use as variables)

| Parameter | Default | Notes |
|---|---|---|
| `wall` | 2.0 mm | Wall thickness (PETG/PLA) |
| `tol_slip` | 0.20 mm | Clearance for slip-fit parts |
| `tol_press` | 0.10 mm | Clearance for press-fit |
| `fillet` | 1.5 mm | Edge rounding |
| `screw` | M2 or M2.5 | Self-tapping into bosses, or heat-set inserts |
| `pcb_standoff` | 3 mm | Height of PCB support ribs/bosses |
| Print material | **PETG** preferred | Tougher/heat-tolerant than PLA; on-set durability + WiFi warmth |
| Orientation | Lid/base split | Design for supportless printing where possible |

**General rules**
- Two-part shell: **base + lid**, joined by **M2 screws into bosses** (preferred
  for serviceability) or snap-fit clips.
- All board-edge ports get cutouts sized `port + tol_slip` on each side.
- Add **0.4–0.6 mm chamfers** at USB/connector mouths so cables seat easily.
- Provide **internal ribs/bosses** to locate the PCB and stop it sliding.
- The nodes run warm when WiFi is on — include **vent slots** (see §3).

---

## 1. Components to house

### Heltec WiFi LoRa 32 V3 (both node and receiver use this MCU family)
| Item | Value | Notes |
|---|---|---|
| PCB L × W | **≈ 50.2 × 25.5 mm** `‹MEASURE›` | |
| PCB thickness | ≈ 1.0 mm | |
| Tallest component height | ≈ 8–10 mm `‹MEASURE›` | OLED + USB dominate |
| USB-C port | one short end, centered | for charging/flashing |
| 0.96" OLED | top face, ~21.7 × 11 mm active `‹MEASURE›` window | node only |
| Buttons | RST + PRG/USER near USB end | **PRG must be pressable** (see §4) |
| LoRa antenna | u.FL/IPEX connector on PCB edge → external antenna | route a pigtail out |
| LiPo JST | 1.25 mm 2-pin connector (on V3) | |

### Heltec Wireless Paper (receiver)
| Item | Value | Notes |
|---|---|---|
| PCB + e-ink module | **`‹MEASURE›`** (≈ 2.13" panel; roughly 60–65 × 30–35 mm) | |
| e-ink active area | **250 × 122 px ≈ 48.5 × 23.7 mm** `‹MEASURE›` | the display window |
| USB-C | one end | charging/flashing |
| USER button | GPIO0, on-board | **must be pressable** |
| LoRa antenna | u.FL → external | |
| Internal LiPo | see below | |

### Internal LiPo (1S, JST 1.25) — **sized per role**

Both units take a 1S LiPo (MakerFocus, protection board, JST 1.25 plug), but the
**capacity differs by role** because the battery does a different job in each:

| Unit | Cell (chosen) | Why |
|---|---|---|
| **Node** | **MakerHawk 1100 mAh** 1S (Amazon `B0F9YSFV4T`) | The LiPo is a **bridge/backup**, not primary power — the buck tops it off from the camera battery whenever one is connected. It only carries the node through a swap (seconds) or the window after a camera battery dies (minutes). Solo runtime is still ~15 h. **Smaller = more compact node.** |
| **Receiver** | **MakerFocus 3000 mAh** 1S (Amazon `B08T6GT7DV`) | Runs **solo all day** — nothing tops it off. ~3000 mAh ≈ 1+ day with margin for dashboard use. |

Both are 1S LiPo pouches with a protection board and a **JST 1.25 plug** that mates
the Heltec battery connector directly (no adapter).

| Item | Value | Notes |
|---|---|---|
| **Node cell** (1100 mAh) | **40 × 25 × 10 mm** (L × W × thick) | pocket ≈ **42 × 27 × 11 mm** (+1 mm clearance) |
| **Receiver cell** (3000 mAh) | **65 × 35 × 10 mm** (L × W × thick) | pocket ≈ **67 × 37 × 11 mm** (+1 mm clearance) |
| Mounting | flat pocket, tape or retention lip | keep clear of the antenna |

> Both cells are **10 mm thick** — that sets the minimum internal depth of each
> shell's battery pocket. Add the JST plug + strain relief on the lead end
> (~+2 mm length). Pocket lengths above already include +1 mm all-round slip.

> ⚠️ **The LiPo is the biggest size driver for each shell.** Measure the exact
> cell you'll use, then design the pocket around it (+1 mm clearance all round,
> +2 mm on the lead side for the JST plug + strain relief). Never compress a
> pouch cell — give it a flat, unstressed bed.

---

## 2. Sensor-node enclosure

> **Parametric model:** [`enclosure/node_enclosure.scad`](enclosure/node_enclosure.scad)
> implements this section (**stacked + side-channel** layout: LiPo flat on
> the floor, Heltec on 13 mm towers above it and ~2.5 mm from the west wall
> so USB-C is a normal chamfered port hole; side channels carry the buck +
> wiring and host the four internal M2 corner bosses; east bay for the LEMO
> tail + divider; outer ≈ **73 × 52 × 30 mm**). Open in OpenSCAD, set
> `part`, tweak the `MEASURE`-tagged
> variables after calipering. Assumes no bottom-facing pin headers on the
> Heltec; if soldered, raise `standoff_h` (shell grows taller). PRG/RST are
> actuated via **captive printed plungers** (guide tube in the lid + printed
> piston, §4) — no exposed PCB; set `plungers = false` for plain holes.

Houses: **Heltec V3** + the **buck converter** (Pololu D24V10F5, ~12.7 × 10.2 mm
`‹MEASURE›`) + the **voltage divider + cap** + a **small bridge LiPo (~1100 mAh)**
+ wiring to the **battery connector** (**LEMO panel-mount** — chosen over
D-Tap/AB; measure your shell's panel-hole diameter + key flat).

> **Power architecture:** the camera battery → buck → 5V powers the node *and*
> charges the LiPo; the camera battery is also sensed via the divider → GPIO7.
> The LiPo **bridges** battery swaps and keeps the node alive to report a dead /
> removed camera battery for sure (vs just going silent). So the node needs a
> **small LiPo pocket** in addition to the buck + divider bays.

**Required features**
- **OLED window** on the top face (clear cutout or thin transparent insert), over
  the 0.96" OLED.
- **PRG button access** — a hole, flexible membrane, or a printed plunger button.
- **USB-C cutout** (flashing + charging the bridge LiPo).
- **Bridge LiPo pocket** — flat bed for the ~1100 mAh cell, JST reachable, away
  from the antenna; tape or a retention lip (never compress the pouch).
- **LoRa antenna exit** — a hole/grommet for the u.FL pigtail + external antenna,
  or an SMA bulkhead cutout if using a panel-mount antenna.
- **Battery-lead entry** — a strain-relieved cutout/grommet where the wires from
  the D-Tap/AB connector enter (these carry VBAT to the buck + divider).
- **Mounting** — pick one (make it a swappable module):
  - flat back with a **velcro/strap channel** (battery mount on set), and/or
  - **¼"-20 or 3/8" threaded insert** boss, and/or
  - **AB/D-Tap connector** panel-mount face.
- **Vent slots** near the buck + ESP for WiFi-mode warmth (see §3).
- **Internal bays:** locate the Heltec, a footprint for the buck, and a small bay
  for the divider board, with wire channels between them.

**Voltage divider — plan the bay around your build method.** The divider is tiny
(R1 = 200kΩ, R2 = 27kΩ, + 100 nF cap, on GPIO7), but its footprint depends on how
it's assembled — design the bay for whichever you use:
- **Inline (smallest):** components soldered inline and heat-shrunk — no board.
  Just provide a **wire channel + a ~10 × 25 mm slack pocket** between the
  battery-lead entry and the Heltec.
- **Perfboard scrap:** allow a **~20 × 15 mm board bay** (`‹MEASURE your board›`)
  with a locating lip.
- **Future PCB:** the planned sensor PCB **combines the buck + divider** on one
  board — then this becomes a single board footprint (size TBD by the PCB).

Keep the divider node (GPIO7) and its 100 nF cap **close to the Heltec** to keep
the ADC trace short and quiet.

**Suggested envelope:** ~60 × 35 × 20 mm internal `‹DERIVE from parts›`. Rugged,
thick corners, IP-ish (gasket channel optional).

---

## 3. Thermal / ventilation

WiFi-on draws ~80–150 mA and warms the ESP + regulator (~40–50 °C). LoRa-only is
cool. Include modest passive venting so a sealed unit doesn't bake during config:
- **Slots** (≥1 mm, label-side or bottom) above the ESP module and buck.
- Keep vents **off the top display face** (debris/water).
- Receiver: less critical (WiFi usually off), but a few slots near the ESP help.

---

## 4. Buttons & display access

- **Buttons (GPIO0 / PRG / USER):** the button is a small SMD tactile on the PCB.
  Provide **a printed flexible plunger** (living hinge or a separate TPU button)
  aligned to it, OR a simple access hole. The button is used a lot (WiFi toggle,
  long-press = battery type, triple-tap = power off), so make it **easy and
  reliable**. `‹MEASURE button XY position from a board reference corner›`.
- **OLED / e-ink window:** flush cutout, or recess + thin clear acrylic/PETG
  window (0.5–1 mm) glued/captured. e-ink needs no backlight; a flush window is
  fine. Align precisely to the active area `‹MEASURE offsets›`.

---

## 5. Antenna

- The LoRa antenna is **external** (u.FL pigtail to a wire/SMA antenna). **Do not
  bury the antenna inside a closed cavity against the PCB ground or battery** —
  route it out of the shell. Provide a **u.FL pigtail exit hole** or an **SMA
  bulkhead** cutout (SMA nut ≈ 6.5 mm hole `‹VERIFY›`).
- Keep the antenna run away from the LiPo and large metal.

---

## 6. Assembly & serviceability

- **Base + lid**, M2 screws into 4 corner bosses (heat-set inserts preferred for
  repeated opening) — these get opened to swap antennas, reflash via USB, etc.
- PCB held by standoffs/bosses + a retaining lip; no glue on the board.
- Receiver: LiPo in a taped pocket, leads strain-relieved, JST reachable.
- Leave **finger clearance** to unplug USB and the JST.

---

## 7. Print settings (recommended)

- **Material:** PETG (PLA acceptable for cool/indoor use).
- **Walls:** 3 perimeters; **Infill:** 20–30 % (gyroid).
- **Layer:** 0.2 mm.
- **Tolerance test first:** print a small fit-test of the USB cutout + a PCB-edge
  slot before the full shell.

---

## 8. Measurements to take before finalizing (checklist)

Take these with calipers off the real hardware and fill into the parameters:

- [ ] Heltec V3 PCB L × W × thickness; height of tallest component
- [ ] OLED active-area size + its X/Y offset from a PCB corner
- [ ] PRG & RST button X/Y positions + height
- [ ] USB-C cutout width/height + offset from PCB edge
- [ ] u.FL connector position (antenna exit)
- [ ] Wireless Paper module overall L × W × thickness
- [ ] e-ink active-area size + X/Y offset
- [ ] USER button + USB-C positions on the receiver
- [x] Node LiPo (1100 mAh): **40 × 25 × 10 mm** (+ lead length ‹measure›)
- [x] Receiver LiPo (3000 mAh): **65 × 35 × 10 mm** (+ lead length ‹measure›)
- [ ] Buck (D24V10F5) footprint + height; divider board size
- [ ] LEMO connector: panel-hole diameter + key-flat dims, body depth behind
      panel, boot/strain-relief length

---

## 9. Acceptance criteria

A good design:
- Closes with the PCB located, no rattle, no stress on the e-ink/OLED.
- USB, button, antenna, and (node) battery leads all accessible without opening.
- LiPo (receiver) sits flat and unstressed with the JST reachable.
- Opens with hand tools for reflash/service.
- Survives a drop from cart height (corners + PETG).
- Vents enough that a WiFi-on session doesn't overheat.

---

*Hardware reference: see [REFERENCE.md](REFERENCE.md) (pins, board roles) and
[WIRING.md](WIRING.md) (node power/sense wiring).*
