# brickdup — Session Handoff

Context document for continuing work in a fresh session. Read this plus the
repo docs (README, WIRING, REFERENCE, ENCLOSURE, CHANGELOG) and you have the
full picture.

---

## What this project is

**brickdup** — a LoRa wireless battery-voltage monitor for film/video sets.
Sensor nodes tap into camera batteries (4S "onboard" bricks or 6S "block"
batteries) and broadcast readings to a handheld receiver with an e-ink display.
The user (Ryan) is a film-industry tech (DIT-adjacent) building this for real
on-set use.

- **Repo:** https://github.com/Kunkles/brickdup (local: `~/Documents/brickwatch/`
  — folder name predates the repo rename, that's fine)
- **Firmware version:** v0.5.3 (`FW_VERSION` in each sketch; CHANGELOG.md)
- **CI:** GitHub Actions builds all sketches on every push; artifacts =
  `brickdup_{universal,onboard,block,receiver}.bin`. Tags `v*` attach bins to a
  GitHub Release.

## Hardware on hand

| Unit | Board | Role |
|---|---|---|
| 2× nodes | Heltec WiFi LoRa 32 V3 (915MHz, ESP32-S3 + SX1262, 0.96" OLED) | sensor nodes |
| 1× receiver | Heltec **Wireless Paper** V1.2 (ESP32-S3 + SX1262 + 2.13" e-ink) | handheld |
| Node LiPo | MakerHawk **1100mAh** 1S JST1.25 (`B0F9YSFV4T`) — **41.4×25.15×10.25mm** (calipered) | bridge cell |
| Receiver LiPo | MakerFocus **3000mAh** 1S JST1.25 (`B08T6GT7DV`) — **65×35×10mm** | solo all-day |
| Bench supply | SPS-3010 series 0–30V/10A | for divider testing |
| Buck (per node) | Pololu D24V10F5 (36V→5V 1A) | powers node + charges LiPo |

**Arduino IDE 2.x**, Heltec board package (3.3.8, URL in README). Board per
sketch: receiver = "Wireless Paper" (the eink lib hard-requires it — "Wrong
build env" error otherwise), nodes = "Heltec WiFi LoRa 32(V3)". USB CDC On
Boot = Enabled. Libraries: RadioLib, Heltec ESP32 Dev-Boards (`HT_SSD1306Wire.h`),
heltec-eink-modules (todd-herbert). Region menu → US915 (cosmetic; freq is
hardcoded 915.0).

## Architecture / key design decisions

- **Radio:** 915.0MHz, BW125, SF9, CR4/5, sync 0xAB, 17dBm, preamble 8 — must
  match across all units. TX every 10s.
- **Packet (ASCII):** `T:<OB|BL>,I:<permId>,V:<float>,S:<0|1|2|3>[,B:<lipo>][,M:<name>]`
  (S:3 = no source / battery removed-dead; B: = node bridge-LiPo volts)
- **Identity:** permanent id from chip MAC. Universal sketch uses
  **`ND-XXXX`** (type-independent so toggling 4S/6S doesn't spawn a ghost
  node); legacy sketches use `OB-`/`BL-`. The id IS the WiFi AP name
  (`Brickdup-ND-XXXX`, password `brickdup`, portal at 192.168.4.1). User-
  assignable friendly name (≤10 chars, NVS) rides in `M:` and wins on display.
- **Universal node** (`sensor_universal_heltec_v3/`) is the recommended node
  firmware: one divider **200k/22k** (2×100k + 22k as built; 6S-safe, 25.2V→~2.5V on GPIO7), battery
  type is a runtime setting (web dropdown or long-press PRG) that flips
  thresholds (OB: WARN 13.5/CRIT 12.8 · BL: WARN 21.0/CRIT 20.0) and broadcast
  type. Legacy `sensor_onboard`/`sensor_block` kept for reference.
- **Node power architecture (DONE in fw 0.5.3):** camera battery → buck →
  Heltec 5V pin (powers board + charges bridge LiPo via onboard charger);
  camera battery also → divider → GPIO7 (sense, common ground). The 1100mAh
  LiPo bridges swaps and keeps the node alive to **report** a removed/dead
  camera battery: node reads its LiPo (B:<v>) and sends S:3 ("no source") when
  the camera reading <5V; receiver shows explicit DEAD + the Li level (vs the
  older silent-after-CRIT *inferred* DEAD, still supported).
- **Bench/demo flags now OFF for real monitoring:** universal sketch has
  `USB_TEST_MODE 0` and `DEMO_VOLTAGE_ON 0` — it reads the real divider on
  GPIO7 (via `analogReadMilliVolts`). Set `USB_TEST_MODE 1` only to re-run the
  no-divider USB bench test. Receiver has `DEMO_NODES` (currently 0).

## Feature inventory (all working, v0.5.3)

**Nodes:** OLED status (id/SSID top, name, big 7-segment voltage with narrow
"1" + GAP 6, emboldened "V", type + version bottom), WiFi config portal
(captive — auto-pops on join) with rename / battery type / single-point
calibration (gain factor in NVS) / WiFi-off / OTA `/update`, PRG button:
tap = WiFi toggle, long-press = 4S↔6S (big confirmation flash), triple-tap =
power off (deep sleep, "POWERED DOWN" screen, press to wake). WiFi state
persists across reboots.

**Receiver:** e-ink list (5/page, USER button pages), header = BRICKDUP +
version + page + own battery (+ = charging, trend-based; ADC2 GPIO20/ctrl 19
can't read while WiFi on — holds last value; optional `VBUS_PIN` define for
wired USB detect), per-node rows = name (10 char, "..." truncation), SoC% +
~time-to-empty (Li-ion curve, 100%=full, 0%=CRIT), 1-decimal voltage, 3-bar
RSSI (≥-95/-110/-120), states OK/WARN/CRIT (inverted bar) / STALE (15s) /
LOST (28s, flashes via fastmode) / DEAD (steady — silent-after-CRIT
inference). Long-press = WiFi dashboard (captive, live table polling /data
JSON every 2s, Clear-node-list, OTA link), triple-tap = power off. Node
roster persists in NVS (~2min throttle). DNSServer captive portal on all
units.

## Roadmap (README has full text)

Done: ping test, paging, fuel gauge, calibration, RSSI bars, dashboard, OTA,
captive portal, universal node, CI, NVS roster, bridge-LiPo firmware
(explicit removed/dead reporting + node LiPo level, fw 0.5.3).
**Open:** channel/group selection (freq+syncword sets), WiFi STA mode + mDNS,
trusted-WiFi auto-join list, BLE + **iOS app** (persistent readout + CRIT/DEAD
notifications, Core Bluetooth background), **VCLX/NiMH block mode** (thresholds
+ honest fuel gauge — needs meter verification), CRIT buzzer (needs piezo),
deep sleep, PCB (universal, screw
terminals, buck+divider integrated). Also promised: a **user manual** at some
point (user asked; deferred until features settle).

## Conventions / user preferences

- Commit style: imperative summary + body, trailer
  `Co-Authored-By: Claude <model> <noreply@anthropic.com>`. Push after every
  change ("update the git repo" = check clean/pushed).
- User prefers: web-portal config over recompiling, zero per-unit firmware
  edits, physical-button UX (taps/long-press), visible feedback for every
  action (e.g. the type-toggle confirmation flash), honest caveats about
  accuracy/limitations, short friendly names (10 char cap), green `#2dd47a`
  accent + black backgrounds on web pages (logo embedded as
  `brickdup_logo.h`, served at `/logo.jpg`).
- Iterate in small steps with hardware verification between (user flashes +
  reports); compile errors get pasted back — fix and push.
- Diagrams: clean SVG schematics (boxes, junction dots, common ground rail,
  GitHub light/dark-safe colors), saved to `docs/` and embedded in the
  relevant doc — not ASCII art, not chat-only. See `docs/node_wiring.svg`.
- Display tweaks went through several rounds (7-seg digits, narrow 1, GAP 6,
  small bold V) — current state is liked; don't redesign unprompted.

## Known gotchas

- e-ink lib needs exact board selected; `getTextBounds` works but
  `drawFastHLine` doesn't exist — use `drawLine`/`fillRect`.
- OLED needs Vext (GPIO36 LOW) before init; fonts only 10/16/24pt (hence
  custom 7-seg renderer `drawVoltage7`/`drawDigit7`; unused `drawV7` still in
  file).
- GPIO0 = boot strap: never *hold* during reset/wake.
- ESP32-S3 ADC2 (receiver battery GPIO20) conflicts with WiFi.
- Universal divider top end (200k/22k): 6S full = ~2.5V on GPIO7 — fine; legacy BL
  180k/27k ran 3.29V (tight, documented).
- Heltec boards.txt hardcodes `default_8MB` partitions (OTA-capable app0/app1,
  no Partition Scheme menu — that's fine).
- Receiver SSID `Brickdup-RX-XXXX`; nodes `Brickdup-ND-XXXX` (universal).
- CI artifact name: `brickdup-firmware`.

## Immediate next steps (where we left off)

1. User may want an **OpenSCAD starter scaffold** for the enclosures (offered,
   not yet accepted). ENCLOSURE.md has all parameters; battery dims measured
   and recorded; board dims still `‹MEASURE›`.
2. Before real deployment: set `DEMO_VOLTAGE_ON 0` (universal),
   `USB_TEST_MODE 0` (when divider wired), calibrate via portal, bench-test
   divider with the 0–30V supply (WIRING.md procedure).
3. Bridge-LiPo firmware (explicit DEAD reporting) is the next meaty firmware
   task when user is ready.
