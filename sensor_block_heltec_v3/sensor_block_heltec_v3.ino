// Brickwatch — Block/floor battery sensor node (6S Li-Ion, up to 25.2V)
// Flash each unit with a unique NODE_ID (1–99).
// Hardware: Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262, 915 MHz)
// Voltage divider: R1=180kΩ, R2=27kΩ on GPIO7

#include <RadioLib.h>
#include "HT_SSD1306Wire.h"   // bundled with the Heltec ESP32 board package

// ── Identity ─────────────────────────────────────────────────────────────────
#define NODE_ID    1       // CHANGE before flashing each unit
#define NODE_TYPE  "BL"

// ── Thresholds (volts) ────────────────────────────────────────────────────────
#define WARN_V  21.0f
#define CRIT_V  20.0f

// ── ADC ──────────────────────────────────────────────────────────────────────
#define VBAT_PIN   7
#define ADC_SAMPLES 16
// Divider: Vout = Vin * R2/(R1+R2) = Vin * 27/(180+27)
// ADC_SCALE = (R1+R2)/R2 * (3.3/4095)
#define ADC_SCALE  (207.0f / 27.0f * 3.3f / 4095.0f)

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

void drawOLED(float voltage, int status) {
  const char* tag = (status == 2) ? "CRIT" : (status == 1) ? "WARN" : "OK";
  char name[12], volt[12];
  snprintf(name, sizeof(name), "%s-%d", NODE_TYPE, NODE_ID);
  snprintf(volt, sizeof(volt), "%.2fV", voltage);

  oled.clear();
  oled.setTextAlignment(TEXT_ALIGN_LEFT);
  oled.setFont(ArialMT_Plain_16);
  oled.drawString(0, 0, name);
  oled.setFont(ArialMT_Plain_24);
  oled.drawString(0, 20, volt);
  oled.setFont(ArialMT_Plain_10);
  oled.drawString(0, 52, tag);
  oled.display();
}

void setup() {
  Serial.begin(115200);
  delay(500);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // Power and start the onboard OLED
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, LOW);   // enable OLED power rail
  delay(50);
  oled.init();
  oled.clear();
  oled.setFont(ArialMT_Plain_10);
  oled.drawString(0, 0, "Brickdup booting...");
  oled.display();

  Serial.printf("[BOOT] Brickdup BL node %d\n", NODE_ID);

  int state = radio.begin(FREQ_MHZ, BW_KHZ, SF, CR, SYNC_WORD, TX_PWR, PREAMBLE);
  if (state != RADIOLIB_ERR_NONE) {
    Serial.printf("[ERR] Radio init failed: %d\n", state);
    while (true) delay(1000);
  }
  Serial.println("[RADIO] OK");
}

float readVoltage() {
  long sum = 0;
  for (int i = 0; i < ADC_SAMPLES; i++) {
    sum += analogRead(VBAT_PIN);
    delayMicroseconds(200);
  }
  return (float)(sum / ADC_SAMPLES) * ADC_SCALE;
}

int voltageStatus(float v) {
  if (v < CRIT_V) return 2;
  if (v < WARN_V) return 1;
  return 0;
}

void loop() {
  float voltage = readVoltage();
  int status = voltageStatus(voltage);

  drawOLED(voltage, status);

  char packet[64];
  snprintf(packet, sizeof(packet), "T:%s,N:%d,V:%.2f,S:%d",
           NODE_TYPE, NODE_ID, voltage, status);

  Serial.printf("[TX] %s\n", packet);

  int state = radio.transmit(packet);
  if (state != RADIOLIB_ERR_NONE) {
    Serial.printf("[ERR] TX failed: %d\n", state);
  }

  delay(TX_INTERVAL_MS);
}
