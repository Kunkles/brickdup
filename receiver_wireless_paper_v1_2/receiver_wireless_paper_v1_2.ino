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

// ── LoRa pins (same as Heltec V3) ────────────────────────────────────────────
#define LORA_CS    8
#define LORA_DIO1  14
#define LORA_RST   12
#define LORA_BUSY  13
// HSPI: SCK=9, MISO=11, MOSI=10

// ── E-ink pins (internal wiring on Wireless Paper, for reference only) ───────
// RST=6, DC=5, CS=4, BUSY=7, SCK=3, MOSI=2 — handled by library, do not redefine

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
};

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
    if (t == FRESH) {
      sig = (sig ^ n.status) * 16777619u;
      sig = (sig ^ (uint32_t)(n.voltage * 100)) * 16777619u;
    }
  }
  return sig;
}

void updateDisplay() {
  display.landscape();
  display.clearMemory();

  // Header
  display.setFont(&FreeSansBold9pt7b);
  display.setTextColor(BLACK);
  display.setCursor(2, 14);
  display.print("BRICKDUP");

  display.drawLine(0, 18, 249, 18, BLACK);   // header underline

  const int RIGHT = 248;   // right edge for the voltage readout
  int row = 0;

  for (int i = 0; i < nodeCount && row < DISPLAY_ROWS; i++) {
    NodeState& n = nodes[i];
    Tier t = tierOf(n);

    int y = 34 + row * 20;

    // Alert rows invert to read across a room. CRIT is a steady inverted bar;
    // LOST flashes (invert only on alternate phases).
    bool invert = (t == LOST) ? flashState : (t == FRESH && n.status == 2);
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

    // Small "stale" flag just after the name when the reading is going cold
    if (t == STALE) {
      int16_t bx, by; uint16_t bw, bh;
      display.getTextBounds(nm, 0, 0, &bx, &by, &bw, &bh);
      display.setCursor(10 + bw + 8, y);
      display.print("stale");
    }

    // Right-aligned readout. LOST uses a smaller bold font so it never clips.
    char readout[12];
    const GFXfont* vfont;
    if (t == LOST) {
      snprintf(readout, sizeof(readout), "LOST");
      vfont = &FreeSansBold9pt7b;
    } else {
      snprintf(readout, sizeof(readout), "%.2fV", n.voltage);
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

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("[BOOT] Brickdup receiver");

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
        nodes[idx].voltage  = voltage;
        nodes[idx].status   = status;
        nodes[idx].rssi     = rssi;
        nodes[idx].lastSeen = millis();
        nodes[idx].active   = true;
        if (name[0]) strncpy(nodes[idx].name, name, sizeof(nodes[idx].name) - 1);
      }
    }
  } else {
    Serial.printf("[ERR] RX: %d\n", state);
  }

  radio.startReceive();   // re-arm for the next packet
}

void loop() {
  // 1. Drain any received packet
  if (packetFlag) {
    packetFlag = false;
    handlePacket();
    maybeRefresh();       // show new data promptly
  }

  // 2. Is any node currently LOST? Those rows flash.
  bool anyLost = false;
  for (int i = 0; i < nodeCount; i++) {
    if (tierOf(nodes[i]) == LOST) { anyLost = true; break; }
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
