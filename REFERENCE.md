# brickdup — Pin & Controls Reference

Quick reference for every pin assignment and button gesture across the three
firmwares. For sensor-node *wiring* (dividers, buck, connectors) see
[WIRING.md](WIRING.md).

---

## Pin assignments

### Sensor nodes — Heltec WiFi LoRa 32 V3 (`OB` and `BL`)

| Function | Pin(s) |
|---|---|
| **LoRa SX1262** (HSPI) | CS=8, DIO1=14, RST=12, BUSY=13 · SCK=9, MISO=11, MOSI=10 |
| **VBAT sense** (real mode) | GPIO7 — external divider midpoint (ADC1) |
| **Onboard battery sense** (USB test mode) | ADC=GPIO1, enable=GPIO37 (drive LOW), factor ≈0.0041 |
| **OLED** (I²C, 128×64) | SDA=17, SCL=18, RST=21 |
| **OLED power rail** (Vext) | GPIO36 — drive LOW = on |
| **USER / PRG button** | GPIO0 |
| **External 5V input** | `5V` pad (from the buck — never raw VBAT) |

Divider resistors: **universal** R1=200k/R2=27k (covers 4S & 6S) · legacy
**OB** R1=100k/R2=22k · **BL** R1=180k/R2=27k.

### Receiver — Heltec Wireless Paper

| Function | Pin(s) |
|---|---|
| **LoRa SX1262** (HSPI) | CS=8, DIO1=14, RST=12, BUSY=13 · SCK=9, MISO=11, MOSI=10 |
| **E-ink** (internal, library-handled) | RST=6, DC=5, CS=4, BUSY=7, SCK=3, MOSI=2 |
| **E-ink power rail** (Vext) | GPIO45 — active low |
| **Own battery sense** | ADC=GPIO20 (ADC2), enable=GPIO19 (drive LOW), ×2 divider |
| **USER button** | GPIO0 |
| **VBUS / USB-present detect** *(optional)* | `VBUS_PIN` = `-1` (unset). Wire 5V→divider→spare GPIO, set the define |
| **Power LED** | GPIO18 (unused by firmware) |

> ADC2 (battery) can't be read while WiFi is active, so the receiver holds its
> last battery reading while the dashboard is up.

### Radio config (identical on all units)

```
915.0 MHz · 125 kHz BW · SF9 · CR 4/5 · sync 0xAB · 17 dBm · preamble 8
```

---

## Button controls

Both boards use the onboard button on **GPIO0**.

### Sensor nodes (PRG button)

| Gesture | Action |
|---|---|
| **Single tap** | Toggle the WiFi config portal on/off |
| **Long press** (~1s) | *(universal sketch)* toggle battery type 4S ↔ 6S |
| **Triple tap** | Power off (deep sleep ~10–20µA) — press the button again to wake |

WiFi on/off, "off", and battery type are remembered across reboots (NVS). The
legacy OB/BL sketches have no long-press (type is fixed per sketch).

### Receiver (USER button)

| Gesture | Action |
|---|---|
| **Short tap** | Page through nodes (5 per page) |
| **Long press** (~1.2s) | Toggle the web dashboard WiFi |
| **Triple tap** | Power off (deep sleep) — press the button again to wake |

> GPIO0 is the boot-strap pin — don't *hold* the button while a unit powers up
> or wakes (that enters bootloader). A normal tap is fine.

---

## On-screen layout

### Node OLED (universal sketch)

```
ND-7F3A                   OK     ← WiFi network name / id (left) · status (right)
Cam A                            ← user name
┌─┐ ┌─┐ . ┌─┐  V          OB 4S  ← big 7-segment voltage · battery type (right)
                          v0.5.0 ← firmware version (bottom-right)
```

- Top-left shows the full `Brickdup-ND-7F3A` SSID when WiFi is on, else just `ND-7F3A`.
- Battery type sits where `USB TEST` appears in test mode (right column).
- Long-press flashes a big `OB 4S` / `BL 6S` confirmation.
- "POWERED DOWN" (white on black) shows briefly on triple-tap before sleep.

### Receiver e-ink

```
BRICKDUP v0.5.0  2/3       4.1V  ← title · version · page (if >1) · battery (+ = charging)
──────────────────────────────
█ Cam A    63% ~48m   14.2V ▂▄█  ← marker · name · %/ETA · voltage · signal
  Cam B    88% ~2.1h  15.6V ▂▄░
  Cam C  stale        14.0V ▂░░
  Cam D              *DEAD*       ← silent after CRIT = battery dead (steady)
  Cam E              *LOST*       ← silent while healthy (flashes)
WiFi: Brickdup-RX-7F3A           ← AP name shown bottom-left when dashboard on
```

Per-node states: **OK / WARN / CRIT / STALE / DEAD / LOST**. CRIT and DEAD are
steady inverted bars; LOST flashes. "POWERED DOWN" fills the screen (white on
black) on triple-tap and stays visible while asleep (e-ink holds the image).

---

## Web portals

| Unit | AP name | Pages |
|---|---|---|
| Node | `Brickdup-OB-<id>` / `Brickdup-BL-<id>` | `/` config (name, calibrate), `/update` OTA |
| Receiver | `Brickdup-RX-<id>` | `/` dashboard (clear list, OTA link), `/update` OTA |

Password: **`brickdup`** · address: **http://192.168.4.1**
The `<id>` suffix is unique per board (chip serial) and shown on its display.
