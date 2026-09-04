# Changelog

Firmware version shown in each unit's screen corner (`FW_VERSION`). All three
sketches share the same version number. Bump `FW_VERSION` in each `.ino` when
cutting a release and add an entry here.

> Note: early development wasn't individually versioned — the version display
> shipped as `0.1.0` and stayed there while features piled on. `0.5.0` is the
> first deliberate bump and rolls up everything below. Numbers are approximate
> by design; this is pre-hardware-validation firmware.

## 0.6.5 — current

- **Charging detection actually works now.** The trend test could never fire
  at a real charge rate: a 3000 mAh cell rising 3.7→4.2 V over ~4 h moves
  ~0.5 mV per 15 s sample, and the reference EMA at α=0.2 lags a steady ramp
  by only 4 samples (~2 mV) against a 12 mV threshold — off by 6×. It fired
  only on the voltage step when USB was first plugged in, then went dark, so
  the indicator (and the `"+"` before it) was effectively dead code. The
  reference average is now α=0.02: ~49 samples of lag (~25 mV), which clears
  the threshold with 2× margin and still drops out immediately on unplug,
  since the cell steps *down*.

  Still inherent without hardware: the bolt means "the cell is climbing", so
  it goes dark once the battery tops off with USB still connected — a full
  cell reads ~4.2 V either way. Wire `VBUS_PIN` for "the cable is in".

## 0.6.4

- Receiver header shows a **charging bolt** beside its own battery voltage
  instead of a `"+"` prefix.

  Caveat worth knowing: `VBUS_PIN` is `-1` on this build, so charging is
  *inferred* from the cell voltage rising, not read from USB directly. A full
  battery reads ~4.2 V whether it is on the charger or just came off it, so
  the bolt drops away once the cell tops off even with USB still connected.
  To make it mean "USB is plugged in", wire a divider off VBUS
  (~100k/220k → 3.3 V) to a spare GPIO and set `VBUS_PIN`; that path already
  exists, is definitive, and works while WiFi is up (the battery ADC does
  not, being on ADC2).

## 0.6.3

- **"on AC" no longer hides a draining onboard battery.** The receiver used
  to suppress time-to-empty whenever a camera reported mains power, assuming
  an idle pack. Wrong: accessories can draw from the onboard battery while
  the camera runs on AC, and that is precisely the case worth flagging — a
  pack quietly emptying behind a reassuring "AC". If the gauge is actually
  falling the estimate is shown (`95% AC~40m`); only a genuinely static pack
  shows a bare `95% AC`.

- Bridge and menu bar now report **both rails** — the onboard pack and the
  input feeding the camera (`Bat2` is the AC/Pwr rail, not a battery; its
  0 % is the tell). Local only, no extra airtime: the packet over LoRa still
  carries just the battery, since the handheld's job is battery warnings.

## 0.6.2

- **Gateway is now a runtime role of the universal node sketch.** One
  firmware, two jobs, never both at once: a "Role" selector in the config
  portal switches a board between *Sensor node* (reads its divider and
  broadcasts its own battery — unchanged default) and *Gateway* (ignores the
  divider entirely, broadcasts nothing of its own, and relays packet lines
  arriving on USB serial from `tools/camera_bridge.py`).

  The point is that a gateway and a sensor are the same hardware. Previously
  becoming a gateway meant flashing a different sketch and losing the board's
  identity, name and calibration; now it is an NVS setting that survives a
  reboot and flips back with no reflash. The OLED shows `GATEWAY` with
  relayed/error counts instead of a voltage, and the portal, OTA and naming
  all keep working in that role.

  Relay guards carried over from the standalone sketch: a line must look like
  a packet (`T:` prefix + `I:` field) before it costs ~288 ms of airtime,
  400 ms minimum gap between transmits, overlong lines dropped rather than
  truncated, and every line acked so a failure lands on the right side of the
  USB link. `gateway_heltec_v3/` is kept as a reference but marked superseded.

## 0.6.1

- **Camera nodes get cadence-appropriate timeouts.** The receiver declared
  any node LOST after 28 s, but camera packets are paced at 30 s (their data
  moves a few percent per ten minutes and each packet costs shared airtime).
  A camera therefore went LOST between every single packet. `T:CAM` nodes now
  use 45 s stale / 95 s lost, keeping the same "1-2 missed / 3 missed"
  meaning at their slower cadence.

- Bridge: the status board now says whether packets are actually reaching a
  radio. Without `--serial` it showed cameras connected while transmitting
  nothing, which reads as working. `--serial` also takes no argument now and
  auto-detects the single attached USB-serial port.

- Gateway: host link pinned to UART0, so it can't land on the native-USB
  path and talk out a port that isn't enumerated.

> Note on 0.6.0: the timeout fix above shipped without a version bump, so a
> unit reporting 0.6.0 may or may not contain it. 0.6.1 exists to make the
> two distinguishable — if a receiver reads 0.6.0, reflash it.

## 0.6.0

- **Camera-sourced readings (receiver).** New packet type `T:CAM` lets a
  source that gauges itself report its own state of charge instead of having
  the receiver derive one from pack voltage. Two new optional fields:
  `P:<percent>` (source-reported %) and `A:<0|1>` (1 = running on mains).
  When `P:` is present it becomes the SoC directly; a source on mains shows
  e.g. `97% AC` and suppresses the time-to-empty, which means nothing for a
  battery that isn't draining. `/data` JSON gains `"ac"`.

  Why not derive it: measured on an ARRI ALEXA 35, a B-mount pack idle on AC
  sits in a 65 mV band, but once it carries the camera the voltage swings
  **403 mV** — several percent of a 7S pack's usable range — while the
  camera's own gauge walks down smoothly. The reported number is both
  steadier and the one the crew reads off the camera body.

  Companion tool `tools/camera_bridge.py` discovers ARRI bodies over mDNS and
  emits these packets; the LoRa gateway sketch that feeds them to the radio is
  still to come.

- Fixed: `parsePacket()` left `*voltage` and `*status` at whatever the caller
  held, unlike the other out-params which were reset. Harmless while every
  packet carried `V:` and `S:`, but a packet type that omits either would have
  inherited stale values.

- Fixed: `cellsFor`/`fullFor`/`critFor` fell through to the 4S onboard curve
  for any unrecognised type, so a 28 V pack would pin at 100 %. `CAM` now has
  a 7S B-mount case.

- Node sketches are unchanged in this release; the version moves with the
  receiver to keep all four sketches on one number.

## 0.5.9

- Editable alert thresholds in the node portal. WARN/CRIT are no longer
  hardcoded — the config page has WARN/CRIT fields for the current battery type,
  saved per type (OB and BL each keep their own) in NVS. Defaults unchanged
  (OB 13.5/12.8V, BL 21.0/20.0V); `/thresh` validates WARN > CRIT within a sane
  range. Switch battery type to edit the other type's pair.

## 0.5.8

- Clear node list now works in the captive-portal popup, not just Safari. The
  form's `onsubmit="return confirm(...)"` was the blocker: iOS's captive
  mini-browser (CNA) doesn't run `confirm()`, so it returned false and
  cancelled the submit. Dropped the confirm (clearing is low-stakes — live
  nodes just re-appear) and made handleClear's redirect an absolute URL.

## 0.5.7

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
