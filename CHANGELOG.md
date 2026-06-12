# Changelog

Firmware version shown in each unit's screen corner (`FW_VERSION`). All three
sketches share the same version number. Bump `FW_VERSION` in each `.ino` when
cutting a release and add an entry here.

> Note: early development wasn't individually versioned — the version display
> shipped as `0.1.0` and stayed there while features piled on. `0.5.0` is the
> first deliberate bump and rolls up everything below. Numbers are approximate
> by design; this is pre-hardware-validation firmware.

## 0.5.1 — current

- Universal node: `ADC_SCALE` set to the as-built divider — R1 = 200kΩ
  (2×100kΩ in series), R2 = **22kΩ** (was the 27kΩ design value). 25.2V now
  reads ~2.5V on GPIO7; recalibrate via the portal after flashing.
- Other sketches: version bump only (shared `FW_VERSION`).

## 0.5.0

Everything since the initial build, gathered into one version:

**Sensor nodes**
- Per-node OLED readout (WiFi name, status, user name, big voltage, version)
- WiFi config portal: rename, single-point voltage calibration (saved to flash)
- Chip-serial permanent id (`OB-7F3A`) = WiFi network name; flash identical
  firmware to every node, configure over WiFi (no per-unit edits)
- WiFi toggle on the PRG button; on/off state persists across reboots
- Name length capped at 10 chars
- Embedded brickdup logo on the config page
- OTA firmware update (`/update`)
- Triple-tap power off (deep sleep), press to wake; "POWERED DOWN" screen
- USB-C bench-test mode (`USB_TEST_MODE`)

**Receiver**
- e-ink dashboard: per-node name, voltage, SoC % + rough time-to-empty,
  3-bar RSSI, and OK / WARN / CRIT / STALE / DEAD / LOST states
- DEAD vs LOST inference (silent-after-CRIT = dead battery; LOST flashes)
- USER button: short = page, long = web dashboard, triple-tap = power off
- Live web dashboard (full node table on your phone) + "Clear node list"
- Node roster persists across reboots (NVS)
- Receiver's own battery on the header, with "+" while charging
  (rising-trend; optional `VBUS_PIN` for definitive USB detection)
- One-decimal voltages; tiny firmware-version corner
- OTA firmware update (`/update`)

**Packet format** `T:<type>,I:<permId>,V:<voltage>,S:<status>[,M:<name>]`

## 0.1.0 — initial versioned build

- Base sensor-node + receiver firmware, OLED / e-ink output, LoRa link,
  early WiFi naming portal. (Version display added here.)
