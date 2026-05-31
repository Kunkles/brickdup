# LoRa Battery Monitor — Project Handoff

## Project goal

Build a LoRa-based wireless battery voltage monitoring system for use on film/video sets. Multiple sensor nodes tap into different battery types and broadcast voltage readings to a single handheld receiver with an e-ink display.

## System architecture

- **Sensor nodes** (one per battery being monitored) — read voltage via ADC, transmit packets over LoRa every 10 seconds, then sleep
- **Receiver** (handheld) — listens continuously, tracks all nodes, displays current state on e-ink

Two variants of sensor node:

| Variant | Battery | Connector | Voltage range | Divider |
|---|---|---|---|---|
| Onboard (`OB`) | 4S Li-Ion | D-Tap or AB 4-pin | up to 16.8V | R1=100kΩ, R2=22kΩ |
| Block (`BL`) | 6S Li-Ion | AB 4-pin (inline) | up to 25.2V | R1=180kΩ, R2=27kΩ |

## Hardware

All boards: **Heltec WiFi LoRa 32 V3** (ESP32-S3 + SX1262, 915 MHz)

Receiver also has: **Waveshare 2.13" e-Paper HAT V4** (250×122, SPI, GDEY0213B74 controller)

### Pin map (Heltec V3 — same on every board)

```
LoRa SX1262 (HSPI):
  CS=8, DIO1=14, RST=12, BUSY=13
  SCK=9, MISO=11, MOSI=10

ADC (sensor nodes only):
  VBAT_PIN = GPIO7 (ADC1_CH6)

E-ink (receiver only, uses default SPI):
  CS=5, DC=4, RST=3, BUSY=2
  SCK=6, MOSI=1
```

### Sensor node front-end

Voltage divider feeds GPIO7. A 100nF ceramic cap between GPIO7 and GND filters ADC noise. The MCU itself is powered through a buck converter (Pololu D24V10F5 recommended — 36V max input, 5V out) tapped off the same VBAT line.

**Do NOT feed VBAT directly to the Heltec USB or VIN pin.** It will destroy the board. Buck converter is mandatory.

## Packet format

ASCII string, comma-separated:

```
T:<type>,N:<id>,V:<voltage>,S:<status>
```

Example: `T:OB,N:1,V:14.73,S:0`

- `type` — `OB` (onboard) or `BL` (block)
- `id` — 1-99, unique per physical node (hardcoded at flash time)
- `voltage` — float, 2 decimal places
- `status` — 0=OK, 1=WARN (below `WARN_V`), 2=CRIT (below `CRIT_V`)

Thresholds:
- Onboard: WARN=13.5V, CRIT=12.8V
- Block: WARN=21.0V, CRIT=20.0V

## Radio config (must match on all nodes)

```
Frequency: 915.0 MHz
Bandwidth: 125 kHz
Spreading factor: 9
Coding rate: 4/5
Sync word: 0xAB
TX power: 17 dBm
Preamble: 8
```

SF9 chosen for 50–100m range with obstacles (typical on-set use). Up to 12 nodes tracked, packets every 10s — no collision concern.

## Source files

Three Arduino sketches in this folder:

- `sensor_onboard_heltec_v3.ino` — flash to each onboard battery sensor
- `sensor_block_heltec_v3.ino` — flash to each block/floor battery sensor  
- `receiver_heltec_v3.ino` — flash to the handheld receiver

Before flashing each sensor node, change `NODE_ID` at the top of the file (1, 2, 3...). `NODE_TYPE` is fixed per file — don't change it.

## Build environment

**Arduino IDE 2.x** with ESP32 board support:

1. File → Preferences → Additional Board Manager URLs:
   `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
2. Tools → Board → "Heltec WiFi LoRa 32(V3)"
3. Tools → USB CDC On Boot → **Enabled** (required for Serial over USB-C)
4. Tools → Upload Speed → 921600

**Libraries** (Library Manager):
- `RadioLib` by Jan Gromeš (handles SX1262)
- `GxEPD2` by ZinggJM (e-ink, receiver only)
- `Adafruit GFX Library` (dependency for GxEPD2)

## Where to start

The most useful next steps for Claude Code:

1. **Bench test sketch** — write a minimal test that just sends/receives a "ping" packet to verify the radio link works before wiring up any analog circuitry. Both ends should be Heltec V3s, no divider needed.

2. **Calibration routine** — add a one-time calibration mode to sensor nodes. User holds a button on boot, feeds a known voltage (e.g. measured with a multimeter), node stores the calibration factor in NVS/preferences. This corrects for resistor tolerance.

3. **Deep sleep** — sensor nodes currently use `delay()` between transmissions. Switch to `esp_deep_sleep_start()` for ~10µA sleep current. Wake every 10s, take reading, transmit, sleep. Massive battery life improvement.

4. **PCB design** — sensor node PCB with screw terminals for VBAT input, divider resistor footprints, decoupling cap, Heltec V3 castellated footprint or headers, buck converter footprint. Two variants or one universal board with DNP options.

5. **Receiver UX improvements:**
   - Button to cycle through pages when more than 5 nodes connect (currently truncates at row 5)
   - Buzzer or piezo for CRIT alerts
   - Battery indicator for the receiver's own LiPo
   - RSSI bars per node (data already available — see `radio.getRSSI()` in the RX handler)

6. **Persistence** — store last-seen node list in NVS so the receiver remembers which nodes existed across reboots (shows them as stale until they re-check-in).

## Known issues / open questions

- **e-ink GPIO conflict risk**: Heltec V3 has limited free pins. Confirm the e-ink pins (1, 2, 3, 4, 5, 6) don't conflict with the Heltec OLED I2C (17/18) or strapping pins (0, 45, 46). Pin 1 may be reserved on some board revisions — double check with a scope before powering up.

- **e-ink controller variant**: Code targets the `GDEY0213B74` (Waveshare V4). If a different rev arrives (`GDEH0213B72` or `GDEW0213T5D`), swap the GxEPD2 driver class in `receiver_heltec_v3.ino` line ~25.

- **AB 4-pin sourcing**: Anton Bauer 4-pin male connectors are not on Amazon. Confirmed sources: Pinknoise Systems (UK), Trew Audio (US). Alternative: buy an AB-to-D-Tap adapter cable, cut off the D-Tap end.

- **No ACK / retry**: packets are fire-and-forget. If a node misses transmission, receiver shows "stale" after 30s. For 7+ nodes this is fine; if reliability becomes an issue, add a simple ACK from receiver and retry-once on sensor side.

- **Channel sharing**: all nodes transmit on the same frequency/SF. Airtime per packet at SF9/125kHz/CR4-5 is ~200ms. With 7 nodes × 10s interval, collision probability is negligible, but verify on big shows (10+ nodes).

## Shopping references

Receiver bill of materials and sensor BOMs are documented in earlier conversation — summary:

- Heltec WiFi LoRa 32 V3 (915 MHz) — Amazon, ~$22 ea
- Waveshare 2.13" e-Paper HAT V4 — Amazon, ~$22
- D-Tap male connectors — B&H (Cable Techniques CT-DTAP-M)
- AB 4-pin connectors — Pinknoise / Trew Audio
- Pololu D24V10F5 buck converters
- 1% metal film resistors (100k, 22k, 180k, 27k)
- 100nF ceramic caps (104)

## Coding conventions used so far

- Single `.ino` per sketch, no external `.h` files yet — fine for the current size
- All config at the top of each file as `#define`s
- Magic numbers in the divider formula are calculated inline as comments (`ADC_SCALE` precomputed at compile time)
- Serial output format: `[TX]` / `[RX]` prefix, type+id, voltage, status, optional RSSI
- 2-space indent, K&R braces

Feel free to refactor into shared headers (`config.h`, `packet.h`, `lora_setup.h`) once the codebase grows past ~500 lines — that's the natural breakpoint.
