# MPSmart simulation sheet — `brickdup_psu` (MP9486A)

Copy-paste inputs for validating the regulator's **closed-loop** behaviour in
[MPSmart](https://www.monolithicpower.com/en/mpsmart-v8.html) (the SPICE side
can't model the IC). Open MPSmart → search **MP9486A** → "Simulate" → enter the
design below, then run the analyses in §3 and check against the targets.

> ⚠️ **Enter DC-bias-DERATED capacitance, not the nameplate value** (§2). Ceramics
> lose most of their C under DC bias; using nameplate C makes ripple/stability
> look better than reality.

---

## 1. Operating conditions

| Field | Value | Notes |
|---|---|---|
| VIN min | **16.8 V** | 4S full |
| VIN nominal | **22.2 V** | 6S nominal (3.7 V/cell) |
| VIN max | **25.2 V** | 6S full (IC is 100 V — huge margin) |
| VOUT | **5.0 V** | |
| Feedback | RFB1 = 240 kΩ (top), RFB2 = 10 kΩ (bottom) | VFB = 0.2 V → 5.0 V |
| IOUT (see load cases §3) | 0.04 – 1.0 A | |
| Switching freq | *(IC-internal — no RT pin; leave at the model default)* | |
| EN / DIM | enabled (DIM tied to EN) | |

## 2. External components (enter these exact parts/values)

| Part | Nameplate | **Enter (derated)** | Footprint |
|---|---|---|---|
| L1 inductor | 33 µH, Isat ≥ 1.7 A, DCR ~80 mΩ | 33 µH | 7.3×7.3 mm |
| Cin (bulk) | 2 × 2.2 µF / 100 V X7R | **~2 µF total** (≈1 µF each @ 25 V) | 1210 |
| Cin (HF) | 100 nF / 100 V | 100 nF | 0603 |
| Cout | 2 × 22 µF / 25 V X7R | **~30 µF total** (≈15 µF each @ 5 V) | 1206 |
| Cbst | 100 nF | 100 nF | 0402 |
| D1 catch diode | Schottky 100 V / 2 A (SS210), Vf ~0.55 V | SS210 or equiv | SMA |
| Cff (across RFB1) | DNP | only add if §3 transient needs it (try 22 pF) | 0402 |

> If MPSmart only takes ideal caps, run it **twice**: once with nameplate C and
> once with the derated C above — the truth is the derated run.

## 3. Analyses to run + pass/fail targets

| Analysis | Conditions | Target / check |
|---|---|---|
| **Startup** | VIN 25.2 V, IOUT 0.65 A | VOUT monotonic to 5 V, overshoot < 10 %; inrush peak < 3.5 A current limit |
| **Steady-state ripple** | VIN 16.8 / 22.2 / 25.2 V × IOUT 0.1 / 0.65 / 1.0 A | VOUT ripple **< 50 mV pk-pk** (expect ~5–20 mV); inductor **IL_peak < 1.7 A** (Isat) and **< 3.5 A** (limit) |
| **Load transient** | VIN 22.2 V, step **0.15 A ↔ 0.65 A** (WiFi + charge kick-in) | VOUT deviation **< ±5 % (±250 mV)**, recovers in < ~200 µs, no ringing → if poor, fit **Cff = 22 pF** |
| **Efficiency** | VIN 22.2 V, sweep IOUT 0.05–1 A | sanity: **> 85 %** around 0.5–0.65 A |
| **Thermal (Tj)** | VIN 25.2 V, IOUT 0.65 A continuous, 25 °C ambient | **Tj < 110 °C**. The EP has no thermal vias yet → **if Tj is high, add 4–6 thermal vias under U1's EP** (keep them off the bottom-layer tracks routed under U1) |
| **AC / loop** *(if offered)* | VIN 22.2 V, IOUT 0.65 A | phase margin **> 45°**, gain margin **> 10 dB** (hysteretic parts may not give a classic Bode — the load-transient result is the practical proxy) |

## 4. Worst-case load context (where the numbers come from)

Heltec WiFi portal ~150 mA + Heltec LiPo charge ~500 mA → ~**0.65 A continuous**
worst case, brief peaks **< 1 A**; LoRa-idle is ~40 mA. So the 0.65 A and 1.0 A
cases above bound real operation. (See README §4.)

## 5. After MPSmart

If all targets pass, the remaining validation is a **bench test of the first
prototype**: scope the SW node + VOUT ripple, do a real load step, and check U1 /
inductor temperature under sustained WiFi+charge. Update the BOM (e.g., bump L1 to
a 2 A part, or fit Cff) per whatever the sim/bench shows.
