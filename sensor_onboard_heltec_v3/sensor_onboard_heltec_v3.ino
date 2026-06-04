// Brickwatch — Onboard battery sensor node (4S Li-Ion, up to 16.8V)
// Flash each unit with a unique NODE_ID (1–99).
// Hardware: Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262, 915 MHz)
// Voltage divider: R1=100kΩ, R2=22kΩ on GPIO7

#include <RadioLib.h>
#include "HT_SSD1306Wire.h"   // bundled with the Heltec ESP32 board package
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>

// ── Identity ─────────────────────────────────────────────────────────────────
// NODE_ID / name below are just *defaults*. Once a node has been named through
// its web page, the saved value (in flash) wins — so you can flash identical
// firmware to every onboard node and name each one over WiFi.
#define NODE_ID    1       // default id; override via web page
#define NODE_TYPE  "OB"    // fixed by hardware (which divider is fitted)

// ── WiFi config portal ────────────────────────────────────────────────────────
#define AP_PASSWORD  "brickdup"   // join the node's "Brickdup-OB-x" network
#define NAME_MAXLEN  16

// ── TEMPORARY: USB-C bench-test mode ──────────────────────────────────────────
// 1 = transmit the Heltec V3's onboard battery/supply voltage (~4V on USB-C)
//     instead of the external 4S divider. Lets you verify TX → RX → e-ink with
//     NOTHING wired up — just power both V3 boards over USB-C.
// 0 = real mode: read the external divider on GPIO7 for 4S monitoring.
#define USB_TEST_MODE  1

// ── Thresholds (volts) ────────────────────────────────────────────────────────
#if USB_TEST_MODE
  // Single-cell levels so a healthy USB/charge reading shows OK, not CRIT
  #define WARN_V  3.50f
  #define CRIT_V  3.30f
#else
  #define WARN_V  13.5f
  #define CRIT_V  12.8f
#endif

// ── ADC ──────────────────────────────────────────────────────────────────────
#define VBAT_PIN    7       // external 4S divider input (real mode)
#define ADC_SAMPLES 16
// Divider: Vout = Vin * R2/(R1+R2) = Vin * 22/(100+22)
// ADC_SCALE = (R1+R2)/R2 * (3.3/4095)
#define ADC_SCALE  (122.0f / 22.0f * 3.3f / 4095.0f)

// Heltec V3 onboard battery sense (test mode only)
#define VBAT_CTRL   37      // drive LOW to connect the onboard divider
#define VBAT_ADC    1       // onboard battery ADC pin
#define VBAT_CAL    0.0041f // nominal V3 divider factor (calibrate later)

// ── OLED (Heltec V3 onboard 128×64, I2C) ──────────────────────────────────────
// These macros are defined by the Heltec V3 board variant; fall back if not.
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

// ── Radio config ─────────────────────────────────────────────────────────────
#define FREQ_MHZ   915.0
#define BW_KHZ     125.0
#define SF         9
#define CR         5       // 4/5
#define SYNC_WORD  0xAB
#define TX_PWR     17
#define PREAMBLE   8

// ── Timing ───────────────────────────────────────────────────────────────────
#define TX_INTERVAL_MS  10000UL

SX1262 radio = new Module(LORA_CS, LORA_DIO1, LORA_RST, LORA_BUSY);

SSD1306Wire oled(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

// ── Runtime config (loaded from / saved to flash) ────────────────────────────
Preferences prefs;
WebServer   server(80);
String      g_name;                 // editable node name (shown + broadcast)
uint8_t     g_id   = NODE_ID;       // editable node id
uint32_t    lastTx = 0;

void drawOLED(float voltage, int status) {
  const char* tag = (status == 2) ? "CRIT" : (status == 1) ? "WARN" : "OK";
  char volt[12];
  snprintf(volt, sizeof(volt), "%.2fV", voltage);

  oled.clear();
  oled.setTextAlignment(TEXT_ALIGN_LEFT);
  oled.setFont(ArialMT_Plain_16);
  oled.drawString(0, 0, g_name.c_str());
  oled.setFont(ArialMT_Plain_24);
  oled.drawString(0, 20, volt);
  oled.setFont(ArialMT_Plain_10);
  oled.drawString(0, 52, tag);
#if USB_TEST_MODE
  oled.drawString(60, 52, "USB TEST");
#endif
  oled.display();
}

// ── Web config portal ─────────────────────────────────────────────────────────
String htmlPage() {
  String s = F("<!doctype html><html><head>"
    "<meta name=viewport content='width=device-width,initial-scale=1'>"
    "<title>Brickdup Node</title><style>"
    "body{font-family:sans-serif;background:#111;color:#eee;margin:0;padding:24px}"
    "h1{font-size:20px}label{display:block;margin:14px 0 4px;font-size:14px;color:#aaa}"
    "input{width:100%;box-sizing:border-box;padding:10px;font-size:16px;"
    "border:1px solid #444;border-radius:6px;background:#222;color:#fff}"
    "button{margin-top:20px;width:100%;padding:12px;font-size:16px;border:0;"
    "border-radius:6px;background:#2dd47a;color:#000;font-weight:bold}"
    ".t{color:#2dd47a}.n{color:#666;font-size:12px;margin-top:24px}</style></head><body>");
  s += F("<h1>Brickdup <span class=t>");
  s += NODE_TYPE;
  s += F("</span> node</h1><form action='/save' method='get'>"
         "<label>Name</label><input name='name' maxlength='16' value='");
  s += g_name;
  s += F("'><label>Node ID (1-99)</label>"
         "<input name='id' type='number' min='1' max='99' value='");
  s += String(g_id);
  s += F("'><button type=submit>Save</button></form>"
         "<p class=n>Type is fixed by hardware. Changes save to the node and "
         "take effect on the next transmission.</p></body></html>");
  return s;
}

void handleRoot() { server.send(200, "text/html", htmlPage()); }

void handleSave() {
  if (server.hasArg("name")) {
    String n = server.arg("name");
    n.replace(",", " ");                 // commas would break the packet format
    n.trim();
    if (n.length() > NAME_MAXLEN) n = n.substring(0, NAME_MAXLEN);
    if (n.length() > 0) {
      g_name = n;
      prefs.putString("name", g_name);
    }
  }
  if (server.hasArg("id")) {
    int id = server.arg("id").toInt();
    if (id >= 1 && id <= 99) {
      g_id = (uint8_t)id;
      prefs.putUChar("id", g_id);
    }
  }
  server.sendHeader("Location", "/");
  server.send(303);                       // redirect back to the form
}

void setup() {
  Serial.begin(115200);
  delay(500);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // Load saved name / id (fall back to compile-time defaults)
  prefs.begin("brickdup", false);
  g_id   = prefs.getUChar("id", NODE_ID);
  g_name = prefs.getString("name", String(NODE_TYPE) + "-" + String(g_id));

  // Power and start the onboard OLED
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, LOW);   // enable OLED power rail
  delay(50);
  oled.init();
  oled.clear();
  oled.setFont(ArialMT_Plain_10);
  oled.drawString(0, 0, "Brickdup booting...");
  oled.display();

  // WiFi config portal — always on for now. Once deep sleep lands this should
  // be gated behind a boot button so it doesn't drain the pack.
  String ssid = "Brickdup-" + String(NODE_TYPE) + "-" + String(g_id);
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ssid.c_str(), AP_PASSWORD);
  server.on("/", handleRoot);
  server.on("/save", handleSave);
  server.begin();
  Serial.printf("[CFG] AP '%s' (pw %s)  http://%s\n",
                ssid.c_str(), AP_PASSWORD, WiFi.softAPIP().toString().c_str());

#if USB_TEST_MODE
  Serial.printf("[BOOT] Brickdup OB node %d  (USB-C TEST MODE)\n", g_id);
#else
  Serial.printf("[BOOT] Brickdup OB node %d\n", g_id);
#endif

  int state = radio.begin(FREQ_MHZ, BW_KHZ, SF, CR, SYNC_WORD, TX_PWR, PREAMBLE);
  if (state != RADIOLIB_ERR_NONE) {
    Serial.printf("[ERR] Radio init failed: %d\n", state);
    while (true) delay(1000);
  }
  Serial.println("[RADIO] OK");

  lastTx = millis() - TX_INTERVAL_MS + 1500;  // first transmit ~1.5s after boot
}

float readVoltage() {
#if USB_TEST_MODE
  // Read the Heltec V3 onboard battery/supply sense
  pinMode(VBAT_CTRL, OUTPUT);
  digitalWrite(VBAT_CTRL, LOW);     // connect the onboard divider
  delay(5);
  long sum = 0;
  for (int i = 0; i < ADC_SAMPLES; i++) {
    sum += analogRead(VBAT_ADC);
    delayMicroseconds(200);
  }
  pinMode(VBAT_CTRL, INPUT);        // release (high-Z) to save power
  return (float)(sum / ADC_SAMPLES) * VBAT_CAL;
#else
  long sum = 0;
  for (int i = 0; i < ADC_SAMPLES; i++) {
    sum += analogRead(VBAT_PIN);
    delayMicroseconds(200);
  }
  return (float)(sum / ADC_SAMPLES) * ADC_SCALE;
#endif
}

int voltageStatus(float v) {
  if (v < CRIT_V) return 2;
  if (v < WARN_V) return 1;
  return 0;
}

void loop() {
  server.handleClient();        // keep the config portal responsive

  uint32_t now = millis();
  if (now - lastTx >= TX_INTERVAL_MS) {
    lastTx = now;

    float voltage = readVoltage();
    int status = voltageStatus(voltage);
    drawOLED(voltage, status);

    char packet[96];
    snprintf(packet, sizeof(packet), "T:%s,N:%d,V:%.2f,S:%d,M:%s",
             NODE_TYPE, g_id, voltage, status, g_name.c_str());

    Serial.printf("[TX] %s\n", packet);

    int state = radio.transmit(packet);
    if (state != RADIOLIB_ERR_NONE) {
      Serial.printf("[ERR] TX failed: %d\n", state);
    }
  }
}
