// Brickdup — Serial→LoRa gateway node
// Hardware: Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262, 915 MHz)
//
// The missing link between tools/camera_bridge.py and the handheld receiver:
//
//     computer ──USB serial──▶ THIS ──LoRa──▶ receiver
//
// A computer that can see data the sensor nodes can't (camera batteries over
// Ethernet, for one) writes brickdup packet lines to this board's USB serial
// port; the board puts them on the air using exactly the same radio settings
// the sensor nodes use, so the receiver treats them like any other node.
//
// It is deliberately dumb: it does NOT invent, reformat, or rate-shape
// packets. Whatever the host sends is what goes out. Pacing is the host's
// job (camera_bridge.py staggers its cameras and defaults to 30 s each) —
// airtime is shared with the real sensor nodes and there is no
// listen-before-talk, so a host that floods this will degrade the whole link.
//
// Line protocol (newline-terminated, both directions):
//     in   T:CAM,I:CAM-63373,V:28.483,P:97,S:0,A:1,M:A
//     out  [OK] <n> <line>        transmitted, n = running count
//          [ERR] tx <code>        RadioLib refused it
//          [SKIP] <reason>        rejected before transmit
//
// Board settings: "Heltec WiFi LoRa 32(V3)", USB CDC On Boot = Enabled.

#include <RadioLib.h>
#include "HT_SSD1306Wire.h"   // bundled with the Heltec ESP32 board package

#define FW_VERSION "0.6.0"

// ── OLED (Heltec V3 onboard 128×64, I2C) ─────────────────────────────────────
#ifndef SDA_OLED
  #define SDA_OLED 17
#endif
#ifndef SCL_OLED
  #define SCL_OLED 18
#endif
#ifndef RST_OLED
  #define RST_OLED 21
#endif
#define VEXT_PIN 36          // powers the OLED rail; LOW = on

// ── LoRa pins (Heltec V3 HSPI) ───────────────────────────────────────────────
#define LORA_CS    8
#define LORA_DIO1  14
#define LORA_RST   12
#define LORA_BUSY  13

// ── Radio config — MUST match the sensor nodes and receiver exactly ──────────
#define FREQ_MHZ   915.0
#define BW_KHZ     125.0
#define SF         9
#define CR         5       // 4/5
#define SYNC_WORD  0xAB
#define TX_PWR     17
#define PREAMBLE   8

// A packet is ~288 ms on air at these settings. Never transmit back to back:
// leave the channel free for the sensor nodes between packets.
#define MIN_TX_GAP_MS  400UL

#define MAX_LINE  120      // receiver's parse buffer is 128; stay under it

SX1262 radio = new Module(LORA_CS, LORA_DIO1, LORA_RST, LORA_BUSY);
SSD1306Wire oled(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

char     line[MAX_LINE + 1];
size_t   lineLen  = 0;
uint32_t sentCount = 0;
uint32_t errCount  = 0;
uint32_t lastTxMs  = 0;
char     lastId[24]  = "—";
char     lastInfo[24] = "";
bool     radioOK = false;

void drawScreen() {
  oled.clear();
  oled.setFont(ArialMT_Plain_10);
  oled.drawString(0, 0, "brickdup gateway");
  oled.drawString(96, 0, "v" FW_VERSION);

  if (!radioOK) {
    oled.setFont(ArialMT_Plain_16);
    oled.drawString(0, 24, "RADIO FAIL");
    oled.display();
    return;
  }

  char l1[32];
  snprintf(l1, sizeof(l1), "sent %lu   err %lu",
           (unsigned long)sentCount, (unsigned long)errCount);
  oled.drawString(0, 16, l1);

  oled.setFont(ArialMT_Plain_16);
  oled.drawString(0, 28, lastId);
  oled.setFont(ArialMT_Plain_10);
  oled.drawString(0, 48, lastInfo);

  if (sentCount) {
    char age[16];
    snprintf(age, sizeof(age), "%lus", (unsigned long)((millis() - lastTxMs) / 1000));
    oled.drawString(100, 48, age);
  }
  oled.display();
}

// Pull "I:" and the most useful readout out of a packet, just for the screen.
void summarize(const char* pkt) {
  const char* p = strstr(pkt, "I:");
  if (p) {
    p += 2;
    size_t n = 0;
    while (p[n] && p[n] != ',' && n < sizeof(lastId) - 1) n++;
    memcpy(lastId, p, n);
    lastId[n] = '\0';
  } else {
    strncpy(lastId, "?", sizeof(lastId) - 1);
  }

  // Prefer a reported percent (P:) — that is the headline for camera packets.
  const char* q = strstr(pkt, ",P:");
  const char* v = strstr(pkt, ",V:");
  if (q)      snprintf(lastInfo, sizeof(lastInfo), "%.*s%%", 3, q + 3);
  else if (v) snprintf(lastInfo, sizeof(lastInfo), "%.*sV", 6, v + 3);
  else        lastInfo[0] = '\0';
}

void handleLine() {
  line[lineLen] = '\0';

  // Trim trailing CR so CRLF hosts work too.
  while (lineLen && (line[lineLen - 1] == '\r' || line[lineLen - 1] == ' '))
    line[--lineLen] = '\0';

  if (lineLen == 0) return;
  if (line[0] == '#') return;                 // host comment, ignore silently

  // Minimal sanity check: it has to look like a brickdup packet, or the
  // receiver will just discard it after we have spent 288 ms of airtime.
  if (strncmp(line, "T:", 2) != 0 || strstr(line, "I:") == nullptr) {
    Serial.printf("[SKIP] not a packet: %s\n", line);
    return;
  }

  // Keep a courteous gap so the sensor nodes get a look at the channel.
  uint32_t since = millis() - lastTxMs;
  if (sentCount && since < MIN_TX_GAP_MS) delay(MIN_TX_GAP_MS - since);

  int state = radio.transmit(line);           // blocks ~288 ms at SF9
  if (state == RADIOLIB_ERR_NONE) {
    sentCount++;
    lastTxMs = millis();
    summarize(line);
    Serial.printf("[OK] %lu %s\n", (unsigned long)sentCount, line);
  } else {
    errCount++;
    Serial.printf("[ERR] tx %d\n", state);
  }
  drawScreen();
}

void setup() {
  Serial.begin(115200);
  delay(200);

  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, LOW);   // enable OLED power rail
  delay(50);
  oled.init();
  oled.clear();
  oled.setFont(ArialMT_Plain_10);
  oled.drawString(0, 0, "brickdup gateway");
  oled.drawString(0, 16, "starting radio...");
  oled.display();

  Serial.println("[BOOT] Brickdup serial->LoRa gateway v" FW_VERSION);

  int state = radio.begin(FREQ_MHZ, BW_KHZ, SF, CR, SYNC_WORD, TX_PWR, PREAMBLE);
  radioOK = (state == RADIOLIB_ERR_NONE);
  if (!radioOK) {
    Serial.printf("[ERR] Radio init failed: %d\n", state);
  } else {
    Serial.println("[RADIO] OK — send packet lines, one per line");
  }
  drawScreen();
}

void loop() {
  while (Serial.available()) {
    int ch = Serial.read();
    if (ch < 0) break;
    if (ch == '\n') {
      handleLine();
      lineLen = 0;
    } else if (lineLen < MAX_LINE) {
      line[lineLen++] = (char)ch;
    } else {
      // Overlong line: drop it rather than transmit a truncated packet.
      lineLen = 0;
      Serial.println("[SKIP] line too long");
      while (Serial.available() && Serial.peek() != '\n') Serial.read();
    }
  }

  static uint32_t lastDraw = 0;
  if (millis() - lastDraw > 1000) {   // keep the "age" counter ticking
    lastDraw = millis();
    drawScreen();
  }
}
