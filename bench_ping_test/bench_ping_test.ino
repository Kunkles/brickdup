// Brickdup — Bench ping test
// Verifies the LoRa link between two Heltec V3 boards before any analog
// wiring exists. No divider, no e-ink — just radios + USB-C serial.
//
// Flash this same sketch to BOTH boards:
//   - One board: set ROLE_PINGER 1  (sends PING, waits for PONG, prints RTT + RSSI)
//   - Other board: set ROLE_PINGER 0 (waits for PING, replies PONG)
//
// Open both serial monitors at 115200. The pinger should show steady
// round-trips with an RSSI value; the ponger should echo each ping.

#include <RadioLib.h>

// ── Role ─────────────────────────────────────────────────────────────────────
#define ROLE_PINGER  1     // 1 on one board, 0 on the other

// ── LoRa pins (Heltec V3 HSPI) ───────────────────────────────────────────────
#define LORA_CS    8
#define LORA_DIO1  14
#define LORA_RST   12
#define LORA_BUSY  13

// ── Radio config (matches the real nodes) ────────────────────────────────────
#define FREQ_MHZ   915.0
#define BW_KHZ     125.0
#define SF         9
#define CR         5       // 4/5
#define SYNC_WORD  0xAB
#define TX_PWR     17
#define PREAMBLE   8

// ── Timing ───────────────────────────────────────────────────────────────────
#define PING_INTERVAL_MS  1000UL
#define REPLY_TIMEOUT_MS  800UL

SX1262 radio = new Module(LORA_CS, LORA_DIO1, LORA_RST, LORA_BUSY);

uint32_t pingCount = 0;

void setup() {
  Serial.begin(115200);
  delay(500);

  SPI.begin(9, 11, 10, LORA_CS);  // HSPI

#if ROLE_PINGER
  Serial.println("[BOOT] Brickdup ping test — PINGER");
#else
  Serial.println("[BOOT] Brickdup ping test — PONGER");
#endif

  int state = radio.begin(FREQ_MHZ, BW_KHZ, SF, CR, SYNC_WORD, TX_PWR, PREAMBLE);
  if (state != RADIOLIB_ERR_NONE) {
    Serial.printf("[ERR] Radio init failed: %d\n", state);
    while (true) delay(1000);
  }
  Serial.println("[RADIO] OK");
}

#if ROLE_PINGER
// ── PINGER ───────────────────────────────────────────────────────────────────
void loop() {
  char out[16];
  snprintf(out, sizeof(out), "PING %lu", (unsigned long)++pingCount);

  uint32_t t0 = millis();
  Serial.printf("[TX] %s\n", out);
  radio.transmit(out);

  // Wait for the matching PONG
  uint32_t deadline = millis() + REPLY_TIMEOUT_MS;
  bool got = false;
  while (millis() < deadline) {
    String in;
    int state = radio.receive(in, 0);  // non-blocking-ish single attempt
    if (state == RADIOLIB_ERR_NONE) {
      uint32_t rtt = millis() - t0;
      float rssi = radio.getRSSI();
      float snr  = radio.getSNR();
      Serial.printf("[RX] %s  RTT=%lums  RSSI=%.0fdBm  SNR=%.1fdB\n",
                    in.c_str(), (unsigned long)rtt, rssi, snr);
      got = true;
      break;
    }
  }
  if (!got) Serial.println("[!!] no PONG (timeout)");

  delay(PING_INTERVAL_MS);
}

#else
// ── PONGER ───────────────────────────────────────────────────────────────────
void loop() {
  String in;
  int state = radio.receive(in);

  if (state == RADIOLIB_ERR_NONE) {
    float rssi = radio.getRSSI();
    Serial.printf("[RX] %s  RSSI=%.0fdBm\n", in.c_str(), rssi);

    // Echo back as PONG with the same number
    String reply = in;
    reply.replace("PING", "PONG");
    delay(20);  // brief turnaround so the pinger is listening
    radio.transmit(reply);
    Serial.printf("[TX] %s\n", reply.c_str());
  } else if (state != RADIOLIB_ERR_RX_TIMEOUT) {
    Serial.printf("[ERR] RX: %d\n", state);
  }
}
#endif
