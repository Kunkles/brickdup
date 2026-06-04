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
// Nodes transmit every ~10s. Tiers below are in missed check-ins:
#define MAX_NODES    12
#define STALE_MS     30000UL   // missed ~3 → STALE (last reading shown, flagged)
#define LOST_MS      60000UL   // missed ~6 → LOST  (signal gone)
#define CHECK_MS     2000UL    // how often to re-evaluate freshness for redraw
#define DISPLAY_ROWS 5

// Freshness tiers
enum Tier { FRESH = 0, STALE = 1, LOST = 2 };

struct NodeState {
  char     type[4];   // "OB" or "BL"
  uint8_t  id;
  float    voltage;
  uint8_t  status;    // 0=OK  1=WARN  2=CRIT
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

// Display — Wireless Paper V1.2
// Library powers GPIO45 automatically; landscape() sets 250×122 orientation
EInkDisplay_WirelessPaperV1_2 display;

// ─────────────────────────────────────────────────────────────────────────────

int findOrCreateNode(uint8_t id, const char* type) {
  for (int i = 0; i < nodeCount; i++) {
    if (nodes[i].id == id && strcmp(nodes[i].type, type) == 0) return i;
  }
  if (nodeCount < MAX_NODES) {
    int idx = nodeCount++;
    nodes[idx] = {};
    nodes[idx].id = id;
    strncpy(nodes[idx].type, type, sizeof(nodes[idx].type) - 1);
    nodes[idx].active = true;
    return idx;
  }
  return -1;
}

bool parsePacket(const char* buf, char* type, uint8_t* id, float* voltage, uint8_t* status) {
  // Format: T:<type>,N:<id>,V:<voltage>,S:<status>
  char tmp[128];
  strncpy(tmp, buf, sizeof(tmp) - 1);

  char* p = strtok(tmp, ",");
  while (p) {
    if (strncmp(p, "T:", 2) == 0) strncpy(type, p + 2, 3);
    else if (strncmp(p, "N:", 2) == 0) *id      = atoi(p + 2);
    else if (strncmp(p, "V:", 2) == 0) *voltage  = atof(p + 2);
    else if (strncmp(p, "S:", 2) == 0) *status   = atoi(p + 2);
    p = strtok(nullptr, ",");
  }
  return (*id > 0 && *id < 100);
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
    sig = (sig ^ n.id) * 16777619u;
    sig = (sig ^ n.type[0]) * 16777619u;
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

  int row = 0;

  for (int i = 0; i < nodeCount && row < DISPLAY_ROWS; i++) {
    NodeState& n = nodes[i];
    Tier t = tierOf(n);

    int y = 34 + row * 20;

    // Status indicator box (left edge) — only meaningful when fresh
    if (t == FRESH) {
      if (n.status == 2) {
        display.fillRect(0, y - 12, 6, 14, BLACK);   // CRIT: solid black
      } else if (n.status == 1) {
        display.drawRect(0, y - 12, 6, 14, BLACK);   // WARN: outline
      }
      // OK: blank
    }

    display.setFont(&FreeSans9pt7b);
    display.setCursor(10, y);

    char label[40];
    if (t == LOST) {
      snprintf(label, sizeof(label), "%s-%d  *** LOST ***", n.type, n.id);
    } else if (t == STALE) {
      // Last good reading is still useful context, flagged as stale
      snprintf(label, sizeof(label), "%s-%d  %5.2fV  STALE", n.type, n.id, n.voltage);
    } else {
      const char* tag = (n.status == 2) ? "CRIT" : (n.status == 1) ? "WARN" : "OK";
      snprintf(label, sizeof(label), "%s-%d  %5.2fV  %s", n.type, n.id, n.voltage, tag);
    }
    display.print(label);

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
    uint8_t id = 0;
    float voltage = 0;
    uint8_t status = 0;

    if (parsePacket(received.c_str(), type, &id, &voltage, &status)) {
      int idx = findOrCreateNode(id, type);
      if (idx >= 0) {
        nodes[idx].voltage  = voltage;
        nodes[idx].status   = status;
        nodes[idx].rssi     = rssi;
        nodes[idx].lastSeen = millis();
        nodes[idx].active   = true;
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

  // 2. Periodically re-check freshness so STALE/LOST surface without traffic
  if (millis() - lastCheck > CHECK_MS) {
    lastCheck = millis();
    maybeRefresh();
  }
}
