// Brickwatch — Onboard battery sensor node (4S Li-Ion, up to 16.8V)
// Flash each unit with a unique NODE_ID (1–99).
// Hardware: Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262, 915 MHz)
// Voltage divider: R1=100kΩ, R2=22kΩ on GPIO7

#include <RadioLib.h>

// ── Identity ─────────────────────────────────────────────────────────────────
#define NODE_ID    1       // CHANGE before flashing each unit
#define NODE_TYPE  "OB"

// ── Thresholds (volts) ────────────────────────────────────────────────────────
#define WARN_V  13.5f
#define CRIT_V  12.8f

// ── ADC ──────────────────────────────────────────────────────────────────────
#define VBAT_PIN   7
#define ADC_SAMPLES 16
// Divider: Vout = Vin * R2/(R1+R2) = Vin * 22/(100+22)
// ADC_SCALE = (R1+R2)/R2 * (3.3/4095)
#define ADC_SCALE  (122.0f / 22.0f * 3.3f / 4095.0f)

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

void setup() {
  Serial.begin(115200);
  delay(500);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  Serial.printf("[BOOT] Brickwatch OB node %d\n", NODE_ID);

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
