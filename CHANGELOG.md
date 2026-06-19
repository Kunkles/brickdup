# Changelog

Firmware version shown in each unit's screen corner (`FW_VERSION`). All three
sketches share the same version number. Bump `FW_VERSION` in each `.ino` when
cutting a release and add an entry here.

> Note: early development wasn't individually versioned — the version display
> shipped as `0.1.0` and stayed there while features piled on. `0.5.0` is the
> first deliberate bump and rolls up everything below. Numbers are approximate
> by design; this is pre-hardware-validation firmware.

## 0.5.7 — current

- Clear-node-list reliability (receiver): the button was a JS `fetch('/clear')`,
  which the captive-portal mini-browsers (iOS/Android) often block — so on those
  it silently did nothing and dead/lost nodes never cleared. Replaced with a
  plain form submit; `handleClear` now redirects back to the dashboard. Added a
  `[CLEAR]` serial log to confirm the handler runs.

## 0.5.6

- Fix the bridge-LiPo read for real: the GPIO37 enable was reading 0 mV on LOW
  (Heltec docs notwithstanding), so the sense divider was never connected. New
  `VBAT_ON HIGH` connects it; this board reads correctly now. `LIPO_RATIO` may
  still need a small trim against a meter once it shows a real number. (The
  `[LIPO] pin=… mV` serial line is still on for verification — remove later.)

## 0.5.5

Receiver fixes (reflash the receiver only):
- "Clear node list" now redraws the e-ink immediately instead of waiting for
  the next packet, so clearing a stale/dead node actually removes it on screen.
  (A *live* node still re-appears on its next 10s transmit — that's expected.)
- Dashboard no longer shows stale full signal bars for a disconnected (LOST)
  node — bars now read 0 unless the node is FRESH/STALE, matching the e-ink.
  Note: at close bench range every node legitimately shows 3 bars (RSSI ≥ -95);
  bars only drop with real distance/obstacles.

## 0.5.4

- Fix the bridge-LiPo read (`B:` was reporting `Li 0.0V`). The onboard
  battery-sense path had never actually run before — `DEMO_VOLTAGE_ON` masked
  the only code that used it — so its 5 ms settle was too short. Now: settle
  `LIPO_SETTLE` (20 ms), read in mV via `analogReadMilliVolts()`, scale by the
  V3 onboard divider ratio `LIPO_RATIO` (~4.9, trim against a meter).

## 0.5.3

Bridge-LiPo support / explicit dead-battery reporting:
- Node reads its bridge LiPo (Heltec onboard sense) and broadcasts it as a new
  `B:<volts>` packet field, plus a new status `S:3` ("no source") when the
  camera battery reads below `SOURCE_MIN_V` (5V). Instead of going silent when
  the camera battery is pulled/dies, the node stays alive on the LiPo and says
  so. Node OLED shows `NO BATT` + the bridge level in that state.
- Receiver parses `B:`/`S:3`, shows an **explicit DEAD** (steady inverted bar)
  for a node reporting no source — distinct from the old *inferred* DEAD
  (silent-after-CRIT), which still works. DEAD rows show the node's `Li x.xV`
  in place of a meaningless SoC; SoC/rate aren't updated from a no-source
  packet. Dashboard JSON gains `lipo`; table shows DEAD + Li level.
- Packet is forward/backward compatible (prefix-matched fields, unknowns
  ignored).

## 0.5.2

- Universal node: read GPIO7 with `analogReadMilliVolts()` (ESP32-S3 factory
  ADC calibration) instead of raw `analogRead()` × an assumed 3.3/4095. Much
  better absolute accuracy and low-end behaviour; the only scale left is the
  divider ratio (`DIVIDER_RATIO` = 222/22). Fixes the ~0.2V high reading that
  single-point calibration couldn't remove. Recalibrate (reset, then set) after
  flashing.
- Other sketches: version bump only (shared `FW_VERSION`).

## 0.5.1

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
