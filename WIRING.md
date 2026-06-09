# brickdup — Sensor Node Wiring

Nodes are **powered by the very battery they monitor**, through a buck converter
— there is no separate node battery. The MCU never sees raw pack voltage; only
the buck's regulated 5V and a divided-down sense voltage.

> ⚠️ **Never** connect raw battery voltage to the Heltec USB-C port, the `5V`
> pin, or `3V3`. Raw pack voltage goes **only** to the buck `VIN` and the top of
> the divider (R1). Everything else runs off the buck's regulated 5V. Getting
> this wrong destroys the board.

---

## Universal node (recommended) — 4S **or** 6S, up to 25.2V

One divider sized for 6S that also reads 4S fine. The battery type is a firmware
setting (web page or long-press PRG) — **no extra wiring** for it.

| Item | Value |
|---|---|
| R1 (VBAT → GPIO7) | **200 kΩ** |
| R2 (GPIO7 → GND) | **27 kΩ** |
| GPIO7 at 25.2V (6S full) | **~3.0 V** (headroom under the 3.3V ADC ceiling) |
| GPIO7 at 16.8V (4S full) | ~2.0 V |
| Buck | Pololu **D24V10F5** (36V max in → 5V) — must be 36V-rated for 6S |

```
                 ┌─────────────► Buck VIN ──► VOUT 5V ──► Heltec 5V
   VBAT ─────────┤
 (4S or 6S,      └──[200kΩ]──┬──► GPIO7
  ≤25.2V)                    │
                          [27kΩ]   [100nF]
                             │        │
   GND ──────────────────────┴────────┴──► Heltec GND  +  Buck GND
```

- **Buck rating matters:** for 6S (25.2V) use the 36V-rated D24V10F5. A 28V buck
  (e.g. MP1584 modules) is too marginal for 6S.
- `ADC_SCALE` in the sketch is the universal value `(227/27 × 3.3/4095)`. If you
  fit different resistors, update it.
- After wiring, **calibrate** on the web page against a multimeter.

---

## Legacy single-mode variants

The two original sketches use fixed dividers (one per battery type). Prefer the
universal node above; these are kept for reference.

## Common to both variants

| Part | Value / Model |
|---|---|
| MCU | Heltec WiFi LoRa 32 V3 |
| Buck converter | Pololu **D24V10F5** (36V max in → 5V out) |
| Sense pin | **GPIO7** (ADC1_CH6) |
| ADC filter cap | **100 nF** (104) ceramic, GPIO7 → GND |

**Power path (identical for both):**
```
Battery + (VBAT) ──► Buck VIN
Battery − (GND)  ──► Buck GND
Buck VOUT (5V)   ──► Heltec "5V" pin
Buck GND         ──► Heltec GND
```

**Sense path (resistor values differ per variant — see below):**
```
Battery + (VBAT) ──[ R1 ]──┬──[ R2 ]── GND
                           │
                           ├──► Heltec GPIO7
                           │
                          100nF
                           │
                          GND
```

Tie **all grounds common**: battery −, buck GND, divider bottom, the cap, and
Heltec GND.

---

## Onboard variant (`OB`) — 4S Li-Ion, ≤ 16.8V

Sketch: `sensor_onboard_heltec_v3/`
Connector: D-Tap or AB 4-pin

| Item | Value |
|---|---|
| R1 (VBAT → GPIO7) | **100 kΩ** |
| R2 (GPIO7 → GND) | **22 kΩ** |
| Divider ratio | 22 / (100+22) |
| GPIO7 at 16.8V | **3.03 V** (under the 3.3V ADC ceiling) |
| WARN threshold | **13.5 V** |
| CRIT threshold | **12.8 V** |

```
                 ┌─────────────► Buck VIN ──► VOUT 5V ──► Heltec 5V
   VBAT ─────────┤
 (4S, ≤16.8V)    └──[100kΩ]──┬──► GPIO7
                             │
                          [22kΩ]   [100nF]
                             │        │
   GND ──────────────────────┴────────┴──► Heltec GND  +  Buck GND
```

---

## Block variant (`BL`) — 6S Li-Ion, ≤ 25.2V

Sketch: `sensor_block_heltec_v3/`
Connector: AB 4-pin (inline)

| Item | Value |
|---|---|
| R1 (VBAT → GPIO7) | **180 kΩ** |
| R2 (GPIO7 → GND) | **27 kΩ** |
| Divider ratio | 27 / (180+27) |
| GPIO7 at 25.2V | **3.29 V** (just under the 3.3V ADC ceiling) |
| WARN threshold | **21.0 V** |
| CRIT threshold | **20.0 V** |

```
                 ┌─────────────► Buck VIN ──► VOUT 5V ──► Heltec 5V
   VBAT ─────────┤
 (6S, ≤25.2V)    └──[180kΩ]──┬──► GPIO7
                             │
                          [27kΩ]   [100nF]
                             │        │
   GND ──────────────────────┴────────┴──► Heltec GND  +  Buck GND
```

> Note: the BL divider lands at **3.29V** near full charge — deliberately close
> to the 3.3V ADC limit for resolution. Use 1% resistors and don't exceed 25.2V
> in (a 6S pack's max). If you want more headroom, bump R1 to 200kΩ and update
> `ADC_SCALE` in the sketch.

---

## Before flashing for real use

- Set **`USB_TEST_MODE 0`** in the onboard sketch. While it's `1` the node reads
  the Heltec's *own* onboard battery sense (for bench testing over USB-C), not
  the GPIO7 divider.
- The `100nF` cap belongs **right at GPIO7 → GND** to quiet ADC noise.
- 1% resistor tolerance still leaves readings off by a few tenths of a volt until
  a calibration routine exists — trim using the resistors' measured values, or
  adjust `ADC_SCALE`, if you need it tighter now.

## Pin reference (Heltec V3, same on every board)

```
LoRa SX1262 (HSPI):  CS=8, DIO1=14, RST=12, BUSY=13 | SCK=9, MISO=11, MOSI=10
ADC sense:           GPIO7 (ADC1_CH6)
External 5V in:      "5V" pad (a.k.a. Vextin/VS on some clones — confirm silkscreen)
```
