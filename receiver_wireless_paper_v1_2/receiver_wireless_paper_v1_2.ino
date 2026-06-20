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
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>       // captive portal (dashboard auto-pops on connect)
#include <Preferences.h>
#include <Update.h>          // built-in OTA (web firmware update)
#include <esp_sleep.h>       // deep sleep (triple-tap power off)
#include <Fonts/FreeSansBold12pt7b.h>
#include <Fonts/FreeSansBold9pt7b.h>
#include <Fonts/FreeSans9pt7b.h>
#include <Fonts/TomThumb.h>          // tiny 3x5 font for the version corner

#define FW_VERSION "0.5.9"

// ── LoRa pins (same as Heltec V3) ────────────────────────────────────────────
#define LORA_CS    8
#define LORA_DIO1  14
#define LORA_RST   12
#define LORA_BUSY  13
// HSPI: SCK=9, MISO=11, MOSI=10

// ── E-ink pins (internal wiring on Wireless Paper, for reference only) ───────
// RST=6, DC=5, CS=4, BUSY=7, SCK=3, MOSI=2 — handled by library, do not redefine

// ── Controls ──────────────────────────────────────────────────────────────────
#define BTN_PIN      0          // Wireless Paper onboard USER button (GPIO0)
#define LONGPRESS_MS 1200       // hold this long to toggle the web dashboard

// ── Web dashboard ─────────────────────────────────────────────────────────────
#define AP_PASSWORD  "brickdup" // password for the receiver's WiFi network

// ── Receiver's own battery sense (Wireless Paper) ─────────────────────────────
// From the Meshtastic variant: ADC_CTRL=19 (enable LOW), VBAT on GPIO20 (ADC2),
// divider is ~1:2 so multiply the pin voltage by 2. ADC2 is OK — no WiFi here.
#define VBAT_CTRL     19
#define VBAT_ADC      20
#define VBAT_MULT     2.0f
#define BATT_SAMPLE_MS 15000UL   // sample every 15s (so "+" clears promptly)

// Optional definitive USB detection. Wire the board's 5V/VBUS pin through a
// divider (e.g. 100k/220k → ~3.3V) to a spare GPIO and set VBUS_PIN to it; the
// pin reads HIGH whenever USB is plugged in. Leave at -1 to use the voltage
// trend instead (which only catches an actively-rising charge).
#define VBUS_PIN      -1

// ── DEMO: populate fake nodes to preview the display. Set to 0 for normal use.
#define DEMO_NODES    0

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
#define STATUS_NOSRC 3         // node S: value = camera battery removed/dead
                               // (node stays alive on its bridge LiPo to report it)
#define CHECK_MS     1000UL    // re-evaluate freshness every 1s for a prompt redraw
#define DISPLAY_ROWS 5

// Freshness tiers
enum Tier { FRESH = 0, STALE = 1, LOST = 2 };

struct NodeState {
  char     permId[16];  // permanent unique id from the node, e.g. "OB-7F3A" (key)
  char     type[4];     // "OB" or "BL"
  char     name[20];    // friendly name broadcast by the node (empty if none)
  float    voltage;
  uint8_t  status;      // 0=OK  1=WARN  2=CRIT  3=NO SOURCE (battery removed/dead)
  float    lipo;        // node's bridge LiPo volts (B: field; 0 if not reported)
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

// Signal strength → 0..3 bars (SX1262 @ SF9 is usable down to roughly -120 dBm).
int signalLevel(int16_t rssi) {
  if (rssi >= -95)  return 3;
  if (rssi >= -110) return 2;
  if (rssi >= -120) return 1;
  return 0;
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

// Paging + button state (short = page, long = dashboard, triple-tap = off)
int      page         = 0;
bool     btnDown      = false;
uint32_t btnPressedAt = 0;
bool     btnLongFired = false;
uint8_t  tapCount     = 0;
uint32_t lastTapMs    = 0;

// Web dashboard
Preferences prefs;
WebServer   server(80);
DNSServer   dnsServer;            // wildcard DNS for the captive portal
bool        portalActive = false;
String      apSsid;

// Node-roster persistence (remember nodes across receiver reboots)
#define  ROSTER_SAVE_MS 120000UL   // flush to NVS at most this often
bool     rosterDirty    = false;
uint32_t lastRosterSave = 0;

// Display — Wireless Paper V1.2
// Library powers GPIO45 automatically; landscape() sets 250×122 orientation
EInkDisplay_WirelessPaperV1_2 display;

// ─────────────────────────────────────────────────────────────────────────────

// ── Roster persistence ────────────────────────────────────────────────────────
// Serialize the node list to NVS as tab/newline-delimited records so the receiver
// remembers which nodes exist across a reboot (shown stale until they re-check-in).
void saveRoster() {
  String blob;
  for (int i = 0; i < nodeCount; i++) {
    NodeState& n = nodes[i];
    blob += n.permId; blob += '\t';
    blob += n.type;   blob += '\t';
    blob += n.name;   blob += '\t';
    blob += String(n.voltage, 2); blob += '\t';
    blob += String(n.status);     blob += '\n';
  }
  prefs.putString("roster", blob);
}

void loadRoster() {
  String blob = prefs.getString("roster", "");
  int start = 0;
  while (start < (int)blob.length() && nodeCount < MAX_NODES) {
    int nl = blob.indexOf('\n', start);
    if (nl < 0) break;
    String line = blob.substring(start, nl);
    start = nl + 1;
    int a = line.indexOf('\t');
    int b = line.indexOf('\t', a + 1);
    int c = line.indexOf('\t', b + 1);
    int d = line.indexOf('\t', c + 1);
    if (a < 0 || b < 0 || c < 0 || d < 0) continue;
    int idx = nodeCount++;
    nodes[idx] = {};
    strncpy(nodes[idx].permId, line.substring(0, a).c_str(),     sizeof(nodes[idx].permId) - 1);
    strncpy(nodes[idx].type,   line.substring(a + 1, b).c_str(), sizeof(nodes[idx].type) - 1);
    strncpy(nodes[idx].name,   line.substring(b + 1, c).c_str(), sizeof(nodes[idx].name) - 1);
    nodes[idx].voltage  = line.substring(c + 1, d).toFloat();
    nodes[idx].status   = line.substring(d + 1).toInt();
    nodes[idx].soc      = socFor(nodes[idx].type, nodes[idx].voltage);
    nodes[idx].active   = true;
    nodes[idx].lastSeen = millis() - STALE_MS - 1000;  // start STALE, grace to re-check-in
  }
}

#if DEMO_NODES
// Fill the table with 5 fake nodes spanning OK / WARN / CRIT for a preview.
void seedDemoNodes() {
  struct Demo { const char* id; const char* type; const char* name;
                float v; uint8_t st; int16_t rssi; float soc; float rate; };
  static const Demo d[5] = {
    {"OB-A001","OB","Cam A",   14.8f, 0,  -68, 92, -0.6f},
    {"OB-B002","OB","B-Cam",   15.1f, 0,  -82, 78, -0.9f},
    {"BL-C003","BL","Floor 1", 21.4f, 1,  -98, 40, -1.4f},
    {"OB-D004","OB","Drone",   12.9f, 2, -112,  9, -2.5f},
    {"OB-E005","OB","Steadi",  14.2f, 0, -105, 64, -0.7f},
  };
  for (int i = 0; i < 5; i++) {
    nodes[i] = {};
    strncpy(nodes[i].permId, d[i].id,   sizeof(nodes[i].permId) - 1);
    strncpy(nodes[i].type,   d[i].type, sizeof(nodes[i].type) - 1);
    strncpy(nodes[i].name,   d[i].name, sizeof(nodes[i].name) - 1);
    nodes[i].voltage  = d[i].v;
    nodes[i].status   = d[i].st;
    nodes[i].rssi     = d[i].rssi;
    nodes[i].soc      = d[i].soc;
    nodes[i].socRate  = d[i].rate;
    nodes[i].active   = true;
    nodes[i].lastSeen = millis();
  }
  nodeCount = 5;
}
#endif

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
                 float* voltage, uint8_t* status, float* lipo,
                 char* name, size_t nameLen) {
  // Format: T:<type>,I:<permId>,V:<voltage>,S:<status>[,B:<lipo>][,M:<name>]
  // Fields are matched by prefix, so order doesn't matter and unknown fields
  // (from older/newer firmware) are simply ignored.
  char tmp[128];
  strncpy(tmp, buf, sizeof(tmp) - 1);
  permId[0] = '\0';
  name[0]   = '\0';
  *lipo     = 0;

  char* p = strtok(tmp, ",");
  while (p) {
    if (strncmp(p, "T:", 2) == 0) strncpy(type, p + 2, 3);
    else if (strncmp(p, "I:", 2) == 0) strncpy(permId, p + 2, permLen - 1);
    else if (strncmp(p, "V:", 2) == 0) *voltage = atof(p + 2);
    else if (strncmp(p, "S:", 2) == 0) *status  = atoi(p + 2);
    else if (strncmp(p, "B:", 2) == 0) *lipo    = atof(p + 2);
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
  // The battery is on GPIO20 = ADC2, which can't be read reliably while WiFi is
  // up (ADC2 is shared with the radio on ESP32-S3). Hold the last good value
  // while the dashboard is active; the battery moves slowly so this is fine.
  if (portalActive) return;

#if VBUS_PIN >= 0
  // Definitive: a divider off VBUS reads HIGH whenever USB is plugged in.
  // This is a plain GPIO, so it works even while WiFi is up.
  battCharging = (digitalRead(VBUS_PIN) == HIGH);
#endif

  // The battery ADC (GPIO20 = ADC2) can't be read reliably while WiFi is up.
  if (portalActive) return;
  battVoltage = readReceiverBattery();
  if (battEMA == 0) battEMA = battVoltage;        // seed
#if VBUS_PIN < 0
  // No VBUS pin wired: "+" only while the cell is actually rising. No absolute-
  // voltage clause, because a full battery reads ~4.2V whether on the charger or
  // just unplugged — so the only honest signal is whether it's climbing.
  battCharging = (battVoltage > battEMA + 0.012f);
#endif
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
    sig = (sig ^ (uint32_t)(n.lipo * 10)) * 16777619u;  // bridge-Li readout (DEAD rows)
    if (t == FRESH) {
      sig = (sig ^ (uint32_t)(n.voltage * 10)) * 16777619u;  // 0.1V = displayed res
      sig = (sig ^ (uint32_t)(n.soc / 5)) * 16777619u;       // 5% buckets
      int eta = etaMinutes(n);                               // 10-min buckets
      sig = (sig ^ (uint32_t)((eta < 0 ? 9999 : eta) / 10 + 1)) * 16777619u;
      sig = (sig ^ (uint32_t)signalLevel(n.rssi)) * 16777619u;
    }
  }
  // Receiver battery (0.1V resolution) + charging flag, so the header refreshes
  // only when the displayed value actually changes.
  sig = (sig ^ (uint32_t)(battVoltage * 10)) * 16777619u;
  sig = (sig ^ (uint32_t)battCharging) * 16777619u;
  sig = (sig ^ (uint32_t)page) * 16777619u;          // redraw when the page changes
  sig = (sig ^ (uint32_t)portalActive) * 16777619u;  // show/hide WiFi indicator
  return sig;
}

// Three signal bars of increasing height; filled = active, outline = empty.
void drawBars(int x, int baseY, int level, uint16_t color) {
  const int bw = 3, gap = 2, h[3] = {4, 8, 12};
  for (int i = 0; i < 3; i++) {
    int bx = x + i * (bw + gap);
    int by = baseY - h[i] + 1;
    if (i < level) display.fillRect(bx, by, bw, h[i], color);
    else           display.drawRect(bx, by, bw, h[i], color);
  }
}

void updateDisplay() {
  display.landscape();
  display.clearMemory();

  const int RIGHT  = 248;  // right edge (header battery)
  const int VRIGHT = 226;  // right edge for row voltage (leaves room for bars)

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
  int16_t hx, hy; uint16_t hw, hh;
  display.getTextBounds("BRICKDUP", 0, 0, &hx, &hy, &hw, &hh);
  int cursorX = 2 + hw + 8;   // just past the title

  // Firmware version, small, right after the title
  display.setFont(&TomThumb);
  display.setTextSize(2);
  display.setCursor(cursorX, 14);
  display.print("v" FW_VERSION);
  display.getTextBounds("v" FW_VERSION, 0, 0, &hx, &hy, &hw, &hh);
  cursorX += hw + 10;
  display.setTextSize(1);

  // Page indicator (only when there's more than one page), after the version
  if (totalPages > 1) {
    char pg[8];
    snprintf(pg, sizeof(pg), "%d/%d", page + 1, totalPages);
    display.setFont(&FreeSans9pt7b);
    display.setCursor(cursorX, 14);
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

    // Two ways a node reads DEAD:
    //  • Explicit (S:3): the node is alive on its bridge LiPo and reporting the
    //    camera battery is gone — DEAD even though it's still transmitting.
    //  • Inferred: a node that went silent right after a CRIT reading (it was
    //    powered by that battery).
    bool noSrc  = (n.status == STATUS_NOSRC);
    bool isDead = noSrc || (t == LOST && n.status == 2);

    // Alert rows invert to read across a room. CRIT and DEAD are steady inverted
    // bars; a true LOST flashes (invert only on alternate phases) to stand out.
    bool invert = isDead ? true
                : (t == LOST) ? flashState
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

    // Friendly node name on the left (truncated with "..." if over 10 chars —
    // names are capped at 10 at entry, but older firmware could send longer)
    char nm[16];
    const char* nmRaw = friendlyName(n);
    if (strlen(nmRaw) > 10) {
      strncpy(nm, nmRaw, 9); nm[9] = '\0'; strcat(nm, "...");
    } else {
      strncpy(nm, nmRaw, sizeof(nm) - 1); nm[sizeof(nm) - 1] = '\0';
    }
    display.setFont(&FreeSans9pt7b);
    display.setCursor(10, y);
    display.print(nm);

    // Middle slot: % + rough time-to-empty when fresh, or a "stale" flag
    int16_t nbx, nby; uint16_t nbw, nbh;
    display.getTextBounds(nm, 0, 0, &nbx, &nby, &nbw, &nbh);
    int infoX = 10 + nbw + 10;
    if (noSrc && t != LOST) {
      // Node alive on its bridge cell — show that instead of a meaningless SoC.
      char info[20];
      snprintf(info, sizeof(info), "Li %.1fV", n.lipo);
      display.setCursor(infoX, y);
      display.print(info);
    } else if (t == STALE) {
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
    if (isDead) {
      snprintf(readout, sizeof(readout), "DEAD");
      vfont = &FreeSansBold9pt7b;
    } else if (t == LOST) {
      snprintf(readout, sizeof(readout), "LOST");
      vfont = &FreeSansBold9pt7b;
    } else {
      snprintf(readout, sizeof(readout), "%.1fV", n.voltage);   // e.g. "14.7V"
      vfont = &FreeSansBold12pt7b;
    }
    display.setFont(vfont);
    int16_t bx, by; uint16_t bw, bh;
    display.getTextBounds(readout, 0, 0, &bx, &by, &bw, &bh);
    // Account for the glyph's left-bearing (bx) so the right edge lands at VRIGHT
    display.setCursor(VRIGHT - bw - bx, y);
    display.print(readout);

    // Signal bars at the far right (only while we have a recent RSSI)
    if (t == FRESH || t == STALE) {
      drawBars(232, y, signalLevel(n.rssi), invert ? WHITE : BLACK);
    }

    display.setTextColor(BLACK);   // reset for next row
    row++;
  }

  if (nodeCount == 0) {
    display.setFont(&FreeSans9pt7b);
    display.setCursor(10, 55);
    display.print("Waiting for nodes...");
  }

  // Dashboard / WiFi indicator, tiny in the bottom-left corner when active
  if (portalActive) {
    display.setFont(&TomThumb);
    display.setCursor(1, 121);
    display.print(("WiFi: " + apSsid).c_str());
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

// ── Web dashboard ─────────────────────────────────────────────────────────────
// Single-page live view: polls /data (JSON) every 2s and redraws the table.
const char DASH_HTML[] PROGMEM = R"HTML(<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1"><title>brickdup</title><style>
body{font-family:system-ui,sans-serif;background:#000;color:#eee;margin:0;padding:16px}
h1{color:#2dd47a;font-size:22px;margin:0 0 2px;letter-spacing:1px}
.sub{color:#777;font-size:12px;margin-bottom:14px}
table{width:100%;border-collapse:collapse}
th,td{text-align:left;padding:8px 6px;border-bottom:1px solid #1c1c1c}
th{color:#888;font-size:11px;text-transform:uppercase;letter-spacing:.5px}
td.v{font-weight:700;font-size:18px}
.ok{color:#2dd47a}.warn{color:#fc3}.crit{color:#f55}.stale{color:#888}.lost{color:#f55}
.bars span{display:inline-block;width:4px;margin-right:1px;background:#2dd47a;vertical-align:bottom}
.bars span.off{background:#333}
.empty{color:#666;text-align:center;padding:32px}
</style></head><body>
<h1>BRICKDUP</h1><div class=sub id=sub>connecting…</div>
<table><thead><tr><th>Name</th><th>Voltage</th><th>%</th><th>Time</th><th>Sig</th><th>Status</th></tr></thead>
<tbody id=rows></tbody></table>
<p style="margin-top:18px">
<form action="/clear" style="display:inline"><button type="submit" style="background:#333;color:#eee;border:0;border-radius:6px;padding:8px 12px;font-size:13px">Clear node list</button></form>
&nbsp; <a href="/update" style="color:#2dd47a;font-size:13px">firmware update &rarr;</a></p>
<script>
function bars(n){let s='';for(let i=0;i<3;i++){let h=4+i*4;s+=`<span class="${i<n?'':'off'}" style="height:${h}px"></span>`}return `<span class=bars>${s}</span>`}
function stat(d){if(d.dead)return['DEAD','lost'];if(d.tier==2)return['LOST','lost'];if(d.tier==1)return['STALE','stale'];return[['OK','WARN','CRIT'][d.st],['ok','warn','crit'][d.st]]}
async function tick(){try{let j=await(await fetch('/data')).json();
document.getElementById('sub').textContent=`${j.nodes.length} node(s) · receiver ${j.batt.toFixed(1)}V${j.chg?' (charging)':''}`;
let h='';if(!j.nodes.length)h='<tr><td colspan=6 class=empty>Waiting for nodes…</td></tr>';
for(let d of j.nodes){let[t,c]=stat(d);
let tm=d.eta<0?'':(d.eta>=100?'~'+(d.eta/60).toFixed(1)+'h':'~'+d.eta+'m');
let pct=d.dead?'Li '+d.lipo.toFixed(1)+'V':(d.tier==0?d.soc+'%':'');
let v=d.dead?'DEAD':(d.tier==2?'LOST':d.v.toFixed(1)+'V');
h+=`<tr><td>${d.name}</td><td class="v ${c}">${v}</td><td>${pct}</td><td>${tm}</td><td>${bars(d.bars)}</td><td class="${c}">${t}</td></tr>`}
document.getElementById('rows').innerHTML=h;}catch(e){document.getElementById('sub').textContent='disconnected'}}
tick();setInterval(tick,2000);
</script></body></html>)HTML";

void jsonEsc(String& out, const char* s) {
  for (const char* p = s; *p; p++) {
    if (*p == '"' || *p == '\\') out += '\\';
    out += *p;
  }
}

void handleDash() { server.send_P(200, "text/html", DASH_HTML); }

// Catch-all (incl. OS captive-portal probes) → the dashboard, so phones pop it
// automatically on connect.
void handleNotFound() {
  server.sendHeader("Location", "http://192.168.4.1/", true);
  server.send(302, "text/plain", "");
}

void handleClear() {
  Serial.printf("[CLEAR] node list cleared (was %d nodes)\n", nodeCount);
  nodeCount   = 0;
  rosterDirty = false;
  prefs.remove("roster");
  if (flashing) { display.fastmodeOff(); flashing = false; }  // leave flash mode
  lastSig = 0xFFFFFFFF;        // force the e-ink to redraw empty
  maybeRefresh();             // redraw NOW — don't wait for the next packet
  // Redirect back to the dashboard so the page reflects the cleared list. A
  // plain form submit + absolute redirect is reliable inside the captive-portal
  // mini-browsers (iOS CNA / Android), where fetch()/confirm() are often
  // blocked — that JS-cancelled submit was why clear only worked in Safari.
  server.sendHeader("Location", "http://192.168.4.1/");
  server.send(303, "text/plain", "");
}

void handleData() {
  String j = "{\"batt\":" + String(battVoltage, 2)
           + ",\"chg\":" + (battCharging ? "true" : "false")
           + ",\"nodes\":[";
  for (int i = 0; i < nodeCount; i++) {
    NodeState& n = nodes[i];
    Tier t = tierOf(n);
    bool dead = (n.status == STATUS_NOSRC) || (t == LOST && n.status == 2);
    if (i) j += ',';
    j += "{\"name\":\"";  jsonEsc(j, friendlyName(n));
    j += "\",\"v\":"   + String(n.voltage, 2);
    j += ",\"st\":"    + String(n.status);
    j += ",\"soc\":"   + String((int)n.soc);
    j += ",\"eta\":"   + String(etaMinutes(n));
    j += ",\"bars\":"  + String((t == FRESH || t == STALE) ? signalLevel(n.rssi) : 0);
    j += ",\"rssi\":"  + String(n.rssi);
    j += ",\"tier\":"  + String((int)t);
    j += ",\"lipo\":"  + String(n.lipo, 2);
    j += ",\"dead\":"  + String(dead ? "true" : "false");
    j += "}";
  }
  j += "]}";
  server.send(200, "application/json", j);
}

void rxWifiStart() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(apSsid.c_str(), AP_PASSWORD);
  dnsServer.start(53, "*", WiFi.softAPIP());   // resolve all names → dashboard
  server.begin();
  portalActive = true;
  prefs.putBool("rxwifi", true);
  lastSig = 0xFFFFFFFF;   // force a redraw to show the WiFi indicator
  Serial.printf("[CFG] Dashboard ON: '%s'  http://%s\n",
                apSsid.c_str(), WiFi.softAPIP().toString().c_str());
}

void rxWifiStop() {
  dnsServer.stop();
  server.stop();
  WiFi.softAPdisconnect(true);
  WiFi.mode(WIFI_OFF);
  portalActive = false;
  prefs.putBool("rxwifi", false);
  lastBatt = 0;            // re-sample the battery now that ADC2 is free
  lastSig = 0xFFFFFFFF;
  Serial.println("[CFG] Dashboard OFF");
}

// ── OTA firmware update (web) ─────────────────────────────────────────────────
String updatePage() {
  String s = F("<!doctype html><html><head>"
    "<meta name=viewport content='width=device-width,initial-scale=1'>"
    "<title>Brickdup Update</title><style>"
    "body{font-family:sans-serif;background:#000;color:#eee;margin:0;padding:24px}"
    "h1{font-size:20px}a{color:#2dd47a}input{margin-top:10px}"
    "button{margin-top:12px;padding:10px 16px;font-size:16px;border:0;border-radius:6px;"
    "background:#2dd47a;color:#000;font-weight:bold}"
    "progress{width:100%;height:18px;margin-top:14px}.n{color:#777;font-size:12px;margin-top:18px}"
    "</style></head><body><h1>Firmware Update</h1>"
    "<p class=n>This unit: <b>Receiver &middot; v");
  s += FW_VERSION;
  s += F("</b><br>Upload the receiver .bin (Sketch -&gt; Export Compiled Binary).</p>"
    "<form id=f method=POST action=/update enctype=multipart/form-data>"
    "<input type=file name=update accept=.bin required><br>"
    "<button type=submit>Flash</button></form>"
    "<progress id=p value=0 max=100 hidden></progress><div id=s></div>"
    "<p class=n><a href=/>&larr; back</a></p>"
    "<script>var f=document.getElementById('f');"
    "f.onsubmit=function(e){e.preventDefault();"
    "var x=new XMLHttpRequest(),d=new FormData(f),p=document.getElementById('p'),s=document.getElementById('s');"
    "p.hidden=false;"
    "x.upload.onprogress=function(ev){var v=Math.round(ev.loaded/ev.total*100);p.value=v;s.textContent=v+'%';};"
    "x.onload=function(){s.textContent=(x.responseText=='OK')?'Done - rebooting...':'Update failed';};"
    "x.onerror=function(){s.textContent='Upload error';};"
    "x.open('POST','/update');x.send(d);};</script></body></html>");
  return s;
}

void handleUpdatePage() { server.send(200, "text/html", updatePage()); }

void handleUpdateDone() {
  bool ok = !Update.hasError();
  server.sendHeader("Connection", "close");
  server.send(200, "text/plain", ok ? "OK" : "FAIL");
  delay(300);
  if (ok) ESP.restart();
}

void handleUpdateUpload() {
  HTTPUpload& up = server.upload();
  if (up.status == UPLOAD_FILE_START) {
    Serial.printf("[OTA] %s\n", up.filename.c_str());
    if (!Update.begin(UPDATE_SIZE_UNKNOWN)) Update.printError(Serial);
  } else if (up.status == UPLOAD_FILE_WRITE) {
    if (Update.write(up.buf, up.currentSize) != up.currentSize) Update.printError(Serial);
  } else if (up.status == UPLOAD_FILE_END) {
    if (Update.end(true)) Serial.printf("[OTA] done: %u bytes\n", up.totalSize);
    else Update.printError(Serial);
  }
}

// Deep sleep ("off"). The e-ink keeps the OFF screen while asleep; a button
// press wakes it and the receiver reboots fresh.
void powerOff() {
  display.landscape();
  display.clearMemory();
  display.fillRect(0, 0, 250, 122, BLACK);       // black screen
  display.setTextColor(WHITE);
  display.setFont(&FreeSansBold12pt7b);
  int16_t bx, by; uint16_t bw, bh;
  display.getTextBounds("POWERED DOWN", 0, 0, &bx, &by, &bw, &bh);
  display.setCursor((250 - (int)bw) / 2 - bx, 68);   // centered white text
  display.print("POWERED DOWN");
  display.update();
  while (digitalRead(BTN_PIN) == LOW) delay(10);   // wait for release
  delay(50);
  esp_sleep_enable_ext0_wakeup((gpio_num_t)BTN_PIN, 0);   // wake on next press (low)
  esp_deep_sleep_start();
}

// Short press pages; long press toggles the dashboard; 3 quick taps power off.
void pollButton() {
  bool down = (digitalRead(BTN_PIN) == LOW);
  uint32_t now = millis();
  if (down && !btnDown) {                 // press
    btnDown = true; btnPressedAt = now; btnLongFired = false;
  } else if (down && btnDown && !btnLongFired && now - btnPressedAt >= LONGPRESS_MS) {
    btnLongFired = true;                   // long press fires once, while held
    portalActive ? rxWifiStop() : rxWifiStart();
  } else if (!down && btnDown) {           // release
    btnDown = false;
    if (!btnLongFired && now - btnPressedAt >= 40) {   // short press
      tapCount = (now - lastTapMs < 600) ? tapCount + 1 : 1;
      lastTapMs = now;
      if (tapCount >= 3) { powerOff(); return; }
      int totalPages = (nodeCount + DISPLAY_ROWS - 1) / DISPLAY_ROWS;
      if (totalPages < 1) totalPages = 1;
      page = (page + 1) % totalPages;
      maybeRefresh();
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("[BOOT] Brickdup receiver");

  pinMode(BTN_PIN, INPUT_PULLUP);   // USER button (short=page, long=dashboard)
#if VBUS_PIN >= 0
  pinMode(VBUS_PIN, INPUT);         // USB-present detection (divider off VBUS)
#endif

  // Unique AP name from the chip MAC, e.g. "Brickdup-RX-7F3A"
  prefs.begin("brickdup", false);
  { char buf[20];
    snprintf(buf, sizeof(buf), "Brickdup-RX-%04X", (uint16_t)(ESP.getEfuseMac() & 0xFFFF));
    apSsid = buf; }
  server.on("/", handleDash);
  server.on("/data", handleData);
  server.on("/clear", handleClear);
  server.on("/update", HTTP_GET, handleUpdatePage);
  server.on("/update", HTTP_POST, handleUpdateDone, handleUpdateUpload);
  server.onNotFound(handleNotFound);   // captive-portal catch-all

#if DEMO_NODES
  seedDemoNodes();   // preview: 5 fake nodes
#else
  loadRoster();   // restore remembered nodes (shown stale until they re-check-in)
#endif

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

  // Restore the dashboard's saved on/off state (default off to save power)
  if (prefs.getBool("rxwifi", false)) rxWifiStart();
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
    float lipo = 0;
    char name[20] = {};

    if (parsePacket(received.c_str(), type, permId, sizeof(permId),
                    &voltage, &status, &lipo, name, sizeof(name))) {
      int idx = findOrCreateNode(permId, type);
      if (idx >= 0) {
        NodeState& nd = nodes[idx];
        nd.voltage  = voltage;
        nd.status   = status;
        nd.lipo     = lipo;
        nd.rssi     = rssi;
        nd.lastSeen = millis();
        nd.active   = true;
        if (name[0]) strncpy(nd.name, name, sizeof(nd.name) - 1);

        // Fuel gauge only means something with a real source present. With no
        // camera battery (S:3) the camera reading is ~0V, so hold the last SoC
        // and don't poison the depletion rate.
        if (status != STATUS_NOSRC) {
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
        rosterDirty = true;   // persist this roster soon
      }
    }
  } else {
    Serial.printf("[ERR] RX: %d\n", state);
  }

  radio.startReceive();   // re-arm for the next packet
}

void loop() {
  pollButton();                              // short=page, long=toggle dashboard
  if (portalActive) { dnsServer.processNextRequest(); server.handleClient(); }

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

#if DEMO_NODES
  // Keep the fake nodes fresh so the preview doesn't age into STALE/LOST
  for (int i = 0; i < nodeCount; i++) nodes[i].lastSeen = millis();
#else
  // Flush the roster to NVS occasionally (throttled to limit flash wear)
  if (rosterDirty && millis() - lastRosterSave > ROSTER_SAVE_MS) {
    lastRosterSave = millis();
    rosterDirty = false;
    saveRoster();
  }
#endif

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
