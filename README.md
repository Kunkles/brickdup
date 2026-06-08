<p align="center"><img src="assets/brickdup-logo.png" width="360" alt="brickdup"></p>

# brickdup

Wireless battery voltage monitor for film/video sets. LoRa sensor nodes tap into camera batteries and broadcast readings to a handheld receiver with an e-ink display.

## Hardware

All boards: **Heltec WiFi LoRa 32 V3** (ESP32-S3 + SX1262, 915 MHz)

Receiver also has: **Waveshare 2.13" e-Paper HAT V4** (250×122, GDEY0213B74)

### Sensor node variants

| Variant | Battery | Connector | Voltage range | Divider |
|---|---|---|---|---|
| Onboard (`OB`) | 4S Li-Ion | D-Tap or AB 4-pin | up to 16.8V | R1=100kΩ, R2=22kΩ |
| Block (`BL`) | 6S Li-Ion | AB 4-pin (inline) | up to 25.2V | R1=180kΩ, R2=27kΩ |

Voltage divider feeds GPIO7. A 100nF ceramic cap between GPIO7 and GND filters ADC noise. Power the MCU through a buck converter (Pololu D24V10F5 — 36V max input, 5V out) tapped off VBAT. **Do not feed VBAT directly to the Heltec USB or VIN pin.**

📐 **Full wiring (both variants, with diagrams): [WIRING.md](WIRING.md)**

### Pin map

```
LoRa SX1262 (HSPI):   CS=8, DIO1=14, RST=12, BUSY=13 | SCK=9, MISO=11, MOSI=10
ADC (sensor nodes):   VBAT_PIN = GPIO7 (ADC1_CH6)
E-ink (receiver):     CS=5, DC=4, RST=3, BUSY=2 | SCK=6, MOSI=1
```

## Sketches

| File | Flash to |
|---|---|
| `bench_ping_test/` | Both V3s, to verify the radio link (set `ROLE_PINGER` per board) |
| `sensor_onboard_heltec_v3/` | Each onboard (4S) sensor node |
| `sensor_block_heltec_v3/` | Each block/floor (6S) sensor node |
| `receiver_wireless_paper_v1_2/` | The handheld receiver (Heltec Wireless Paper V1.2) |

> **Test modes:** `sensor_onboard_heltec_v3` has `USB_TEST_MODE` (default `1`) that
> transmits the board's onboard supply voltage so the TX → RX → e-ink chain can be
> validated over USB-C with no divider wired. Set to `0` for real 4S monitoring.

Before flashing each sensor, set `NODE_ID` at the top of the file (1–99, unique per unit). `NODE_TYPE` is fixed per sketch — don't change it.

## Node identity

Every node has two names:

- **Permanent id** — auto-derived from the chip's unique MAC at boot, e.g.
  `OB-7F3A`. Never changes, guaranteed unique, and is the WiFi network name.
  This is the key the receiver tracks nodes by.
- **User name** — the friendly label you assign over WiFi (`Cam A`). Defaults to
  the permanent id until set. Shown on the OLED + handheld and broadcast.

Because the permanent id comes from the silicon, you flash the **same firmware to
every node** — no `NODE_ID` edits, no per-unit builds. The only compile-time
choice is which sketch (OB vs BL = which divider is fitted).

## Packet format

```
T:<type>,I:<permId>,V:<voltage>,S:<status>[,M:<name>]
```

Example: `T:OB,I:OB-7F3A,V:14.73,S:0,M:Cam A`

- `type` — `OB` or `BL`
- `permId` — permanent unique id (chip-derived), receiver's tracking key
- `voltage` — float, 2 decimal places
- `status` — 0=OK, 1=WARN, 2=CRIT
- `name` — optional friendly name (no commas)

## Naming nodes (WiFi config portal)

Each node hosts a WiFi access point you can join to rename it — no reflashing:

1. Power the node and join WiFi **`Brickdup-OB-7F3A`** (password `brickdup`) —
   the suffix is unique per board, printed on the OLED at boot
2. Open **http://192.168.4.1**
3. Type a **name**, tap Save

The name persists in flash (survives reboot/reflash) and rides along in every
packet, so the handheld shows it automatically.

**Turning WiFi off (saves ~80mA):** no extra hardware needed —

- Tap the node's onboard **PRG button** any time to toggle WiFi on/off, or
- Hit **Turn off WiFi** on the config page when you're done naming.

Press PRG again to bring it back. The on/off choice is **remembered across
reboots** — a node switched off stays off after a power cycle. `WIFI_ON_AT_BOOT`
is only the first-ever-boot default.

Thresholds — Onboard: WARN=13.5V, CRIT=12.8V | Block: WARN=21.0V, CRIT=20.0V

## Radio config

```
Frequency: 915.0 MHz  |  Bandwidth: 125 kHz  |  SF: 9  |  CR: 4/5
Sync word: 0xAB       |  TX power: 17 dBm    |  Preamble: 8
```

All nodes must use identical settings. SF9 gives 50–100m range with obstacles. Up to 12 nodes, 10s interval — no collision concern.

## Build environment

**Arduino IDE 2.x**, board: `Heltec WiFi LoRa 32(V3)`

Additional board URL:
```
https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
```

Settings: USB CDC On Boot → **Enabled** | Upload Speed → 921600

**Libraries (Library Manager):**
- `RadioLib` by Jan Gromeš
- `GxEPD2` by ZinggJM
- `Adafruit GFX Library`

## BOM

| Part | Source | ~Cost |
|---|---|---|
| Heltec WiFi LoRa 32 V3 (915 MHz) | Amazon | $22 ea |
| Waveshare 2.13" e-Paper HAT V4 | Amazon | $22 |
| Pololu D24V10F5 buck converter | Pololu | — |
| D-Tap male connectors | B&H (CT-DTAP-M) | — |
| AB 4-pin connectors | Pinknoise Systems / Trew Audio | — |
| 1% metal film resistors (100k, 22k, 180k, 27k) | — | — |
| 100nF ceramic caps (104) | — | — |

## Roadmap

- [x] Bench ping test (verify radio link before analog wiring)
- [x] Receiver paging (USER button cycles pages when >5 nodes)
- [x] Fuel gauge: SoC % + rough time-to-empty per node (voltage-based)
- [x] Calibration (enter true voltage on the web page; gain factor saved to NVS)
- [ ] Deep sleep on sensor nodes (~10µA between transmissions)
- [ ] RSSI bars per node on display
- [ ] CRIT buzzer alert on receiver
- [ ] Receiver battery indicator
- [ ] NVS persistence (remember nodes across receiver reboots)
- [ ] PCB design (sensor node, two variants or DNP options)
