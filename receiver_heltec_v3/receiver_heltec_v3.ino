// Brickdup — Handheld receiver
// Hardware: Heltec Wireless Paper (ESP32-S3 + SX1262 + built-in 2.13" e-ink)
//
// Board version note: this targets V1.1 (display: LCMEN2R13EFC1).
// If you have V1.0 swap EInkDisplay_WirelessPaperV1_1 → EInkDisplay_WirelessPaperV1
// If you have V1.1.1 swap → EInkDisplay_WirelessPaperV1_1_1
// Check the version number silkscreened on the PCB.
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
#define MAX_NODES    12
#define STALE_MS     30000UL
#define DISPLAY_ROWS 5

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

// Display — Wireless Paper V1.1
// Library powers GPIO45 automatically; landscape() sets 250×122 orientation
EInkDisplay_WirelessPaperV1_1 display;

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

void updateDisplay() {
  display.landscape();
  display.clearMemory();

  // Header
  display.setFont(&FreeSansBold9pt7b);
  display.setTextColor(BLACK);
  display.setCursor(2, 14);
  display.print("BRICKDUP");

  display.drawFastHLine(0, 18, 250, BLACK);

  uint32_t now = millis();
  int row = 0;

  for (int i = 0; i < nodeCount && row < DISPLAY_ROWS; i++) {
    NodeState& n = nodes[i];
    bool stale = (now - n.lastSeen) > STALE_MS;

    int y = 34 + row * 20;

    // Status indicator box (left edge)
    if (!stale) {
      if (n.status == 2) {
        display.fillRect(0, y - 12, 6, 14, BLACK);   // CRIT: solid black
      } else if (n.status == 1) {
        display.drawRect(0, y - 12, 6, 14, BLACK);   // WARN: outline
      }
      // OK: blank
    }

    display.setFont(&FreeSans9pt7b);
    display.setCursor(10, y);

    char label[32];
    if (stale) {
      snprintf(label, sizeof(label), "%s-%d  --.-  STALE", n.type, n.id);
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
  Serial.println("[RADIO] Listening...");
}

void loop() {
  String received;
  int state = radio.receive(received);

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
      updateDisplay();
    }
  } else if (state != RADIOLIB_ERR_RX_TIMEOUT) {
    Serial.printf("[ERR] RX: %d\n", state);
  }
}
