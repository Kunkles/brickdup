// Brickdup — Handheld receiver
// Hardware: Heltec Wireless Paper (ESP32-S3 + SX1262 + built-in 2.13" e-ink)
//
// Board version: V1.2 (confirmed from PCB silkscreen).
// If you ever swap boards: V1.0 → EInkDisplay_WirelessPaperV1,
// V1.1 → EInkDisplay_WirelessPaperV1_1, V1.1.1 → EInkDisplay_WirelessPaperV1_1_1
//
// Libraries needed (Library Manager):
//   - RadioLib by Jan Gromeš
//   - heltec-eink-modules by todd-herbert  ← replaces GxEPD2

#include <RadioLib.h>
#include <heltec-eink-modules.h>
#include <Fonts/FreeSansBold12pt7b.h>
#include <Fonts/FreeSansBold9pt7b.h>
#include <Fonts/FreeSans9pt7b.h>
#include <Fonts/TomThumb.h>          // tiny 3x5 font for the version corner

#define FW_VERSION "0.1.0"

// ── LoRa pins (same as Heltec V3) ────────────────────────────────────────────
#define LORA_CS    8
#define LORA_DIO1  14
#define LORA_RST   12
#define LORA_BUSY  13
// HSPI: SCK=9, MISO=11, MOSI=10

// ── E-ink pins (internal wiring on Wireless Paper, for reference only) ───────
// RST=6, DC=5, CS=4, BUSY=7, SCK=3, MOSI=2 — handled by library, do not redefine

// ── Controls ──────────────────────────────────────────────────────────────────
#define BTN_PIN  0          // Wireless Paper onboard USER button (GPIO0)

// ── Receiver's own battery sense (Wireless Paper) ─────────────────────────────
// From the Meshtastic variant: ADC_CTRL=19 (enable LOW), VBAT on GPIO20 (ADC2),
// divider is ~1:2 so multiply the pin voltage by 2. ADC2 is OK — no WiFi here.
#define VBAT_CTRL     19
#define VBAT_ADC      20
#define VBAT_MULT     2.0f
#define BATT_SAMPLE_MS 30000UL   // battery changes slowly; sample every 30s

// ── Radio config (must match all nodes) ──────────────────────────────────────
#define FREQ_MHZ   915.0
#define BW_KHZ     125.0
#define SF         9
#define CR         5       // 4/5
#define SYNC_WORD  0xAB
#define TX_PWR     17
#define PREAMBLE   8

// ── Node tracking ─────────────────────────────────────────────────────────────
// Nodes transmit every ~10s. Tiers are timed to ride out a single dropped
// packet (a ~20s gap) without false alarms, but flag a real loss quickly:
#define MAX_NODES    12
#define STALE_MS     15000UL   // ~1-2 missed → STALE (last reading shown, flagged)
#define LOST_MS      28000UL   // ~3 missed   → LOST  (signal gone)
#define CHECK_MS     1000UL    // re-evaluate freshness every 1s for a prompt redraw
#define DISPLAY_ROWS 5

// Freshness tiers
enum Tier { FRESH = 0, STALE = 1, LOST = 2 };

struct NodeState {
  char     permId[16];  // permanent unique id from the node, e.g. "OB-7F3A" (key)
  char     type[4];     // "OB" or "BL"
  char     name[20];    // friendly name broadcast by the node (empty if none)
  float    voltage;
  uint8_t  status;      // 0=OK  1=WARN  2=CRIT
  int16_t  rssi;
  uint32_t lastSeen;
  bool     active;
  // Fuel-gauge estimate (computed on the receiver)
  float    soc;         // state of charge %, 100=full … 0=CRIT (practical dead)
  float    socRate;     // %/min, smoothed; negative = depleting (0 = unknown)
  float    socAtCalc;   // soc at the last rate calculation
  uint32_t lastRateMs;  // when the rate was last recomputed
};

// ── Battery fuel gauge ────────────────────────────────────────────────────────
// Per-cell Li-ion discharge curve (volts → raw % of cell charge). Roughly S-
// shaped: most of the charge lives in the upper voltages, then a knee.
struct VP { float v; float p; };
const VP CELL_CURVE[] = {
  {3.00, 0}, {3.30, 5}, {3.45, 10}, {3.58, 20}, {3.68, 30}, {3.74, 40},
  {3.79, 50}, {3.86, 60}, {3.92, 70}, {4.00, 80}, {4.10, 90}, {4.20, 100},
};
const int CELL_CURVE_N = sizeof(CELL_CURVE) / sizeof(CELL_CURVE[0]);

int   cellsFor(const char* t) { return strcmp(t, "BL") == 0 ? 6 : 4; }
float fullFor (const char* t) { return strcmp(t, "BL") == 0 ? 25.2f : 16.8f; }
float critFor (const char* t) { return strcmp(t, "BL") == 0 ? 20.0f : 12.8f; }

float rawCellSoc(float vcell) {
  if (vcell <= CELL_CURVE[0].v)             return CELL_CURVE[0].p;
  if (vcell >= CELL_CURVE[CELL_CURVE_N-1].v) return CELL_CURVE[CELL_CURVE_N-1].p;
  for (int i = 1; i < CELL_CURVE_N; i++) {
    if (vcell < CELL_CURVE[i].v) {
      float f = (vcell - CELL_CURVE[i-1].v) / (CELL_CURVE[i].v - CELL_CURVE[i-1].v);
      return CELL_CURVE[i-1].p + f * (CELL_CURVE[i].p - CELL_CURVE[i-1].p);
    }
  }
  return 100;
}

// Pack voltage → usable %, rescaled so 100% = full and 0% = CRIT (the swap point).
float socFor(const char* type, float packV) {
  int cells   = cellsFor(type);
  float raw   = rawCellSoc(packV / cells);
  float rawC  = rawCellSoc(critFor(type) / cells);
  float rawF  = rawCellSoc(fullFor(type) / cells);
  float pct   = (raw - rawC) / (rawF - rawC) * 100.0f;
  return pct < 0 ? 0 : pct > 100 ? 100 : pct;
}

// Rough minutes until 0% (CRIT / swap point), or -1 if not clearly depleting.
int etaMinutes(const NodeState& n) {
  if (n.socRate < -0.02f) return (int)(n.soc / (-n.socRate));
  return -1;
}

NodeState nodes[MAX_NODES];
int nodeCount = 0;

SX1262 radio = new Module(LORA_CS, LORA_DIO1, LORA_RST, LORA_BUSY);

// Set by the DIO1 ISR when a packet lands; loop() drains it.
volatile bool packetFlag = false;
void IRAM_ATTR onPacket() { packetFlag = true; }

// Tracks what's currently on the e-ink so we only refresh on real change.
uint32_t lastSig    = 0xFFFFFFFF;
uint32_t lastCheck  = 0;

// LOST rows flash by inverting every ~500ms (uses the panel's fast refresh mode).
#define FLASH_MS  500
bool     flashState = false;   // current flash phase
bool     flashing   = false;   // are we in fast-refresh flashing mode?
uint32_t lastFlash  = 0;

// Receiver's own battery
float    battVoltage  = 0;     // last reading (volts)
float    battEMA      = 0;     // slow average, for charging-trend detection
bool     battCharging = false; // inferred from a rising trend
uint32_t lastBatt     = 0;

// Paging through nodes (5 rows per page)
int      page       = 0;
bool     lastPgBtn  = HIGH;
uint32_t lastPgBtnMs = 0;

// Display — Wireless Paper V1.2
// Library powers GPIO45 automatically; landscape() sets 250×122 orientation
EInkDisplay_WirelessPaperV1_2 display;

// ─────────────────────────────────────────────────────────────────────────────

int findOrCreateNode(const char* permId, const char* type) {
  for (int i = 0; i < nodeCount; i++) {
    if (strcmp(nodes[i].permId, permId) == 0) return i;
  }
  if (nodeCount < MAX_NODES) {
    int idx = nodeCount++;
    nodes[idx] = {};
    strncpy(nodes[idx].permId, permId, sizeof(nodes[idx].permId) - 1);
    strncpy(nodes[idx].type, type, sizeof(nodes[idx].type) - 1);
    nodes[idx].active = true;
    return idx;
  }
  return -1;
}

bool parsePacket(const char* buf, char* type, char* permId, size_t permLen,
                 float* voltage, uint8_t* status, char* name, size_t nameLen) {
  // Format: T:<type>,I:<permId>,V:<voltage>,S:<status>[,M:<name>]
  char tmp[128];
  strncpy(tmp, buf, sizeof(tmp) - 1);
  permId[0] = '\0';
  name[0]   = '\0';

  char* p = strtok(tmp, ",");
  while (p) {
    if (strncmp(p, "T:", 2) == 0) strncpy(type, p + 2, 3);
    else if (strncmp(p, "I:", 2) == 0) strncpy(permId, p + 2, permLen - 1);
    else if (strncmp(p, "V:", 2) == 0) *voltage = atof(p + 2);
    else if (strncmp(p, "S:", 2) == 0) *status  = atoi(p + 2);
    else if (strncmp(p, "M:", 2) == 0) strncpy(name, p + 2, nameLen - 1);
    p = strtok(nullptr, ",");
  }
  return (permId[0] != '\0');
}

const char* friendlyName(const NodeState& n) {
  // The node's own friendly name, or its permanent id if it hasn't been named.
  return n.name[0] ? n.name : n.permId;
}

// Read the receiver's own LiPo voltage (enable divider via ADC_CTRL, then ADC2).
float readReceiverBattery() {
  pinMode(VBAT_CTRL, OUTPUT);
  digitalWrite(VBAT_CTRL, LOW);          // enable the battery divider
  delay(5);
  uint32_t mv = 0;
  for (int i = 0; i < 8; i++) { mv += analogReadMilliVolts(VBAT_ADC); delay(2); }
  pinMode(VBAT_CTRL, INPUT);             // release (high-Z) to save power
  return (mv / 8.0f) * VBAT_MULT / 1000.0f;
}

// Sample periodically; infer "charging" from a rising trend vs the slow average.
void updateBattery() {
  battVoltage = readReceiverBattery();
  if (battEMA == 0) battEMA = battVoltage;        // seed
  battCharging = (battVoltage > battEMA + 0.03f); // rising ⇒ on charge
  battEMA = battEMA * 0.8f + battVoltage * 0.2f;
}

Tier tierOf(const NodeState& n) {
  uint32_t age = millis() - n.lastSeen;
  if (age > LOST_MS)  return LOST;
  if (age > STALE_MS) return STALE;
  return FRESH;
}

// Compact signature of everything visible. If it hasn't changed, the e-ink
// doesn't need a (slow, panel-wearing) refresh.
uint32_t displaySignature() {
  uint32_t sig = 2166136261u;             // FNV-1a basis
  sig = (sig ^ (uint32_t)nodeCount) * 16777619u;
  for (int i = 0; i < nodeCount; i++) {
    NodeState& n = nodes[i];
    Tier t = tierOf(n);
    for (const char* c = n.permId; *c; c++) sig = (sig ^ (uint8_t)*c) * 16777619u;
    for (const char* c = n.name;   *c; c++) sig = (sig ^ (uint8_t)*c) * 16777619u;
    sig = (sig ^ (uint32_t)t) * 16777619u;
    sig = (sig ^ n.status) * 16777619u;   // also distinguishes LOST vs DEAD
    if (t == FRESH) {
      sig = (sig ^ (uint32_t)(n.voltage * 10)) * 16777619u;  // 0.1V = displayed res
      sig = (sig ^ (uint32_t)(n.soc / 5)) * 16777619u;       // 5% buckets
      int eta = etaMinutes(n);                               // 10-min buckets
      sig = (sig ^ (uint32_t)((eta < 0 ? 9999 : eta) / 10 + 1)) * 16777619u;
    }
  }
  // Receiver battery (0.1V resolution) + charging flag, so the header refreshes
  // only when the displayed value actually changes.
  sig = (sig ^ (uint32_t)(battVoltage * 10)) * 16777619u;
  sig = (sig ^ (uint32_t)battCharging) * 16777619u;
  sig = (sig ^ (uint32_t)page) * 16777619u;   // redraw when the page changes
  return sig;
}

void updateDisplay() {
  display.landscape();
  display.clearMemory();

  const int RIGHT = 248;   // right edge for readouts

  // Paging: clamp the current page to the node count (5 rows per page)
  int totalPages = (nodeCount + DISPLAY_ROWS - 1) / DISPLAY_ROWS;
  if (totalPages < 1) totalPages = 1;
  if (page >= totalPages) page = 0;
  int startIdx = page * DISPLAY_ROWS;

  // Header
  display.setFont(&FreeSansBold9pt7b);
  display.setTextColor(BLACK);
  display.setCursor(2, 14);
  display.print("BRICKDUP");

  // Page indicator (only when there's more than one page)
  if (totalPages > 1) {
    char pg[8];
    snprintf(pg, sizeof(pg), "%d/%d", page + 1, totalPages);
    display.setFont(&FreeSans9pt7b);
    display.setCursor(92, 14);
    display.print(pg);
  }

  // Receiver's own battery, right-aligned on the header line. "+" while charging.
  char batt[16];
  snprintf(batt, sizeof(batt), "%s%.1fV", battCharging ? "+" : "", battVoltage);
  display.setFont(&FreeSans9pt7b);
  int16_t hbx, hby; uint16_t hbw, hbh;
  display.getTextBounds(batt, 0, 0, &hbx, &hby, &hbw, &hbh);
  display.setCursor(RIGHT - hbw - hbx, 14);
  display.print(batt);

  display.drawLine(0, 18, 249, 18, BLACK);   // header underline

  int row = 0;

  for (int i = startIdx; i < nodeCount && row < DISPLAY_ROWS; i++) {
    NodeState& n = nodes[i];
    Tier t = tierOf(n);

    int y = 34 + row * 20;

    // A node gone silent right after a CRIT reading = its battery died (it was
    // powered by that battery). Otherwise it's a genuine connection loss.
    bool isDead = (t == LOST && n.status == 2);

    // Alert rows invert to read across a room. CRIT and DEAD are steady inverted
    // bars; a true LOST flashes (invert only on alternate phases) to stand out.
    bool invert = (t == LOST) ? (isDead ? true : flashState)
                              : (t == FRESH && n.status == 2);
    if (invert) {
      display.fillRect(0, y - 14, 250, 18, BLACK);
      display.setTextColor(WHITE);
    } else {
      display.setTextColor(BLACK);
      // WARN gets a small outline marker; OK stays blank
      if (t == FRESH && n.status == 1) {
        display.drawRect(0, y - 12, 6, 14, BLACK);
      }
    }

    // Friendly node name on the left
    const char* nm = friendlyName(n);
    display.setFont(&FreeSans9pt7b);
    display.setCursor(10, y);
    display.print(nm);

    // Middle slot: % + rough time-to-empty when fresh, or a "stale" flag
    int16_t nbx, nby; uint16_t nbw, nbh;
    display.getTextBounds(nm, 0, 0, &nbx, &nby, &nbw, &nbh);
    int infoX = 10 + nbw + 10;
    if (t == STALE) {
      display.setCursor(infoX, y);
      display.print("stale");
    } else if (t == FRESH) {
      char info[20];
      int eta = etaMinutes(n);
      if      (eta < 0)     snprintf(info, sizeof(info), "%.0f%%", n.soc);
      else if (eta >= 600)  snprintf(info, sizeof(info), "%.0f%% >9h", n.soc);
      else if (eta >= 100)  snprintf(info, sizeof(info), "%.0f%% ~%.1fh", n.soc, eta / 60.0);
      else                  snprintf(info, sizeof(info), "%.0f%% ~%dm", n.soc, eta);
      display.setCursor(infoX, y);
      display.print(info);
    }

    // Right-aligned readout. LOST/DEAD use a smaller bold font so they don't clip.
    char readout[12];
    const GFXfont* vfont;
    if (t == LOST) {
      snprintf(readout, sizeof(readout), isDead ? "DEAD" : "LOST");
      vfont = &FreeSansBold9pt7b;
    } else {
      snprintf(readout, sizeof(readout), "%.1fV", n.voltage);   // e.g. "14.7V"
      vfont = &FreeSansBold12pt7b;
    }
    display.setFont(vfont);
    int16_t bx, by; uint16_t bw, bh;
    display.getTextBounds(readout, 0, 0, &bx, &by, &bw, &bh);
    // Account for the glyph's left-bearing (bx) so the right edge lands at RIGHT
    display.setCursor(RIGHT - bw - bx, y);
    display.print(readout);

    display.setTextColor(BLACK);   // reset for next row
    row++;
  }

  if (nodeCount == 0) {
    display.setFont(&FreeSans9pt7b);
    display.setCursor(10, 55);
    display.print("Waiting for nodes...");
  }

  // Firmware version, tiny in the bottom-right corner
  display.setFont(&TomThumb);
  display.setTextColor(BLACK);
  {
    int16_t vbx, vby; uint16_t vbw, vbh;
    display.getTextBounds("v" FW_VERSION, 0, 0, &vbx, &vby, &vbw, &vbh);
    display.setCursor(249 - vbw - vbx, 121);
    display.print("v" FW_VERSION);
  }

  display.update();
}

// Redraw only when the visible state actually changed.
void maybeRefresh() {
  uint32_t sig = displaySignature();
  if (sig != lastSig) {
    lastSig = sig;
    updateDisplay();
  }
}

// Tap the USER button to page through nodes (when more than 5 are connected).
void pollPageButton() {
  bool b = digitalRead(BTN_PIN);
  if (b == LOW && lastPgBtn == HIGH && (millis() - lastPgBtnMs) > 250) {
    lastPgBtnMs = millis();
    int totalPages = (nodeCount + DISPLAY_ROWS - 1) / DISPLAY_ROWS;
    if (totalPages < 1) totalPages = 1;
    page = (page + 1) % totalPages;
    maybeRefresh();   // page is in the signature, so this redraws
  }
  lastPgBtn = b;
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("[BOOT] Brickdup receiver");

  pinMode(BTN_PIN, INPUT_PULLUP);   // USER button for paging

  // ADC for the receiver's own battery (high divider output → 12dB attenuation)
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  updateBattery();
  lastBatt = millis();

  // Display init — library handles Vext (GPIO45) automatically
  updateDisplay();

  // LoRa uses HSPI (separate SPI bus from e-ink)
  SPI.begin(9, 11, 10, LORA_CS);
  int state = radio.begin(FREQ_MHZ, BW_KHZ, SF, CR, SYNC_WORD, TX_PWR, PREAMBLE);
  if (state != RADIOLIB_ERR_NONE) {
    Serial.printf("[ERR] Radio init failed: %d\n", state);
    while (true) delay(1000);
  }

  // Interrupt-driven RX so the loop stays free to run timeout checks
  radio.setDio1Action(onPacket);
  radio.startReceive();
  Serial.println("[RADIO] Listening...");
}

void handlePacket() {
  String received;
  int state = radio.readData(received);

  if (state == RADIOLIB_ERR_NONE) {
    int16_t rssi = radio.getRSSI();
    Serial.printf("[RX] %s  RSSI=%d\n", received.c_str(), rssi);

    char type[4] = {};
    char permId[16] = {};
    float voltage = 0;
    uint8_t status = 0;
    char name[20] = {};

    if (parsePacket(received.c_str(), type, permId, sizeof(permId),
                    &voltage, &status, name, sizeof(name))) {
      int idx = findOrCreateNode(permId, type);
      if (idx >= 0) {
        NodeState& nd = nodes[idx];
        nd.voltage  = voltage;
        nd.status   = status;
        nd.rssi     = rssi;
        nd.lastSeen = millis();
        nd.active   = true;
        if (name[0]) strncpy(nd.name, name, sizeof(nd.name) - 1);

        // Fuel gauge: state of charge, and a smoothed depletion rate (%/min).
        nd.soc = socFor(nd.type, voltage);
        uint32_t now = millis();
        if (nd.lastRateMs == 0) {               // first sample: seed
          nd.socAtCalc = nd.soc;
          nd.lastRateMs = now;
        } else if (now - nd.lastRateMs >= 60000UL) {   // recompute ~once a minute
          float dtMin = (now - nd.lastRateMs) / 60000.0f;
          float rate  = (nd.soc - nd.socAtCalc) / dtMin;        // %/min
          nd.socRate  = (nd.socRate == 0) ? rate
                                          : nd.socRate * 0.6f + rate * 0.4f;
          nd.socAtCalc  = nd.soc;
          nd.lastRateMs = now;
        }
      }
    }
  } else {
    Serial.printf("[ERR] RX: %d\n", state);
  }

  radio.startReceive();   // re-arm for the next packet
}

void loop() {
  pollPageButton();       // USER button cycles pages

  // 1. Drain any received packet
  if (packetFlag) {
    packetFlag = false;
    handlePacket();
    maybeRefresh();       // show new data promptly
  }

  // Sample the receiver's own battery now and then
  if (millis() - lastBatt > BATT_SAMPLE_MS) {
    lastBatt = millis();
    updateBattery();
  }

  // 2. Any node in a *true* LOST state (gone silent while still healthy)?
  // Those rows flash. A DEAD node (silent after CRIT) renders steady instead.
  bool anyLost = false;
  for (int i = 0; i < nodeCount; i++) {
    if (tierOf(nodes[i]) == LOST && nodes[i].status != 2) { anyLost = true; break; }
  }

  if (anyLost) {
    // Flash the LOST row(s) by inverting every FLASH_MS, using fast refresh.
    if (!flashing) { flashing = true; display.fastmodeOn(); }
    if (millis() - lastFlash >= FLASH_MS) {
      lastFlash  = millis();
      flashState = !flashState;
      updateDisplay();
    }
  } else {
    // Nothing lost — leave fast mode and return to change-only full refreshes.
    if (flashing) {
      flashing   = false;
      flashState = false;
      display.fastmodeOff();
      lastSig = 0xFFFFFFFF;     // force one clean redraw
    }
    if (millis() - lastCheck > CHECK_MS) {
      lastCheck = millis();
      maybeRefresh();
    }
  }
}
