// Brickdup — Onboard battery sensor node (4S Li-Ion, up to 16.8V)
// Flash the SAME firmware to every onboard node — each self-assigns a unique
// permanent id from its chip MAC, and you name it over WiFi. No per-unit edits.
// Hardware: Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262, 915 MHz)
// Voltage divider: R1=100kΩ, R2=22kΩ on GPIO7

#include <RadioLib.h>
#include "HT_SSD1306Wire.h"   // bundled with the Heltec ESP32 board package
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>        // captive portal (page auto-pops on connect)
#include <Preferences.h>
#include <Update.h>           // built-in OTA (web firmware update)
#include <esp_sleep.h>        // deep sleep (triple-tap power off)
#include "brickdup_logo.h"    // embedded logo served from /logo.jpg

// ── Identity ─────────────────────────────────────────────────────────────────
// Two names per node:
//   • PERMANENT id  — derived from the chip's unique MAC at boot, e.g. "OB-7F3A".
//     Never changes, guaranteed unique, and is the WiFi network name. This means
//     you flash the SAME firmware to every node — no per-unit edits, ever.
//   • USER name     — friendly label you assign over WiFi ("Cam A"). Defaults to
//     the permanent id until you set one. Shown on screens + broadcast.
#define NODE_TYPE  "OB"    // fixed by hardware (which divider is fitted)
#define FW_VERSION "0.5.2" // shown small in the OLED corner

// ── WiFi config portal ────────────────────────────────────────────────────────
#define AP_PASSWORD      "brickdup" // password for the node's WiFi network
#define NAME_MAXLEN      10
// WiFi draws ~80mA, so it can be toggled off to save power — no extra hardware:
//   • Tap the onboard PRG button (GPIO0) any time to toggle WiFi on/off.
//   • Or hit "Turn off WiFi" on the config page when you're done naming.
// The on/off choice is remembered across reboots — a node switched off stays
// off after a power cycle. WIFI_ON_AT_BOOT is only the first-ever-boot default.
#define WIFI_ON_AT_BOOT  1
#define PRG_BUTTON       0          // Heltec V3 onboard USER/PRG button (GPIO0)

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

// ── Runtime config ────────────────────────────────────────────────────────────
Preferences prefs;
WebServer   server(80);
DNSServer   dnsServer;              // wildcard DNS for the captive portal
String      g_permId;               // permanent unique id from chip MAC (SSID)
String      g_name;                 // editable user name (shown + broadcast)
float       g_cal   = 1.0f;         // calibration gain factor (1.0 = uncalibrated)
bool        portalActive = false;   // is the WiFi portal running?
bool        pendingWifiOff = false; // request to drop WiFi after a web response
bool        lastBtn = HIGH;         // PRG button edge tracking
uint32_t    lastBtnMs = 0;
uint8_t     tapCount = 0;           // triple-tap power-off
uint32_t    lastTapMs = 0;
uint32_t    lastTx = 0;

// Build the permanent id from the chip's MAC: e.g. "OB-7F3A". Unique per board.
String makePermId() {
  uint16_t suffix = (uint16_t)(ESP.getEfuseMac() & 0xFFFF);
  char buf[16];
  snprintf(buf, sizeof(buf), "%s-%04X", NODE_TYPE, suffix);
  return String(buf);
}

void drawOLED(float voltage, int status) {
  const char* tag = (status == 2) ? "CRIT" : (status == 1) ? "WARN" : "OK";
  char volt[12];
  snprintf(volt, sizeof(volt), "%.1fV", voltage);   // e.g. "14.7V"

  oled.clear();

  // Top line: WiFi network name on the left (so you can always find it),
  // status tag on the right.
  oled.setFont(ArialMT_Plain_10);
  oled.setTextAlignment(TEXT_ALIGN_LEFT);
  if (portalActive) {
    String w = "Brickdup-" + g_permId;
    oled.drawString(0, 0, w.c_str());
  } else {
    oled.drawString(0, 0, g_permId.c_str());   // WiFi off: just the device id
  }
  oled.setTextAlignment(TEXT_ALIGN_RIGHT);
  oled.drawString(128, 0, tag);
  oled.setTextAlignment(TEXT_ALIGN_LEFT);

  // User name, then the big voltage readout
  oled.setFont(ArialMT_Plain_16);
  oled.drawString(0, 14, g_name.c_str());
  oled.setFont(ArialMT_Plain_24);
  oled.drawString(0, 34, volt);

#if USB_TEST_MODE
  oled.setFont(ArialMT_Plain_10);
  oled.setTextAlignment(TEXT_ALIGN_RIGHT);
  oled.drawString(128, 40, "USB TEST");
  oled.setTextAlignment(TEXT_ALIGN_LEFT);
#endif
  // Firmware version, tiny in the bottom-right corner
  oled.setFont(ArialMT_Plain_10);
  oled.setTextAlignment(TEXT_ALIGN_RIGHT);
  oled.drawString(128, 53, "v" FW_VERSION);
  oled.setTextAlignment(TEXT_ALIGN_LEFT);
  oled.display();
}

// ── Web config portal ─────────────────────────────────────────────────────────
float readVoltage();   // fwd decl (htmlPage shows the live reading)

String htmlPage() {
  String s = F("<!doctype html><html><head>"
    "<meta name=viewport content='width=device-width,initial-scale=1'>"
    "<title>Brickdup Node</title><style>"
    "body{font-family:sans-serif;background:#000;color:#eee;margin:0;padding:24px}"
    "h1{font-size:20px}label{display:block;margin:14px 0 4px;font-size:14px;color:#aaa}"
    "img.logo{display:block;width:240px;max-width:100%;margin:0 auto 8px}"
    "input{width:100%;box-sizing:border-box;padding:10px;font-size:16px;"
    "border:1px solid #444;border-radius:6px;background:#222;color:#fff}"
    "button{margin-top:20px;width:100%;padding:12px;font-size:16px;border:0;"
    "border-radius:6px;background:#2dd47a;color:#000;font-weight:bold}"
    ".off{background:#444;color:#fff;margin-top:10px}"
    ".t{color:#2dd47a}.n{color:#666;font-size:12px;margin-top:24px}"
    ".wifi{margin:14px 0;padding:12px;border:1px solid #333;border-radius:6px;"
    "color:#aaa;font-size:13px}.wifi b{color:#2dd47a;font-size:16px}"
    "</style></head><body>");
  s += F("<img class=logo src='/logo.jpg'>");
  s += F("<h1>Brickdup <span class=t>");
  s += NODE_TYPE;
  s += F("</span> node</h1>"
         "<div class=wifi>WiFi network (fixed)<br><b>Brickdup-");
  s += g_permId;
  s += F("</b></div><form action='/save' method='get'>"
         "<label>Name</label><input name='name' maxlength='10' value='");
  s += g_name;
  s += F("'><button type=submit>Save</button></form>");

  // Calibration section
  s += F("<label>Calibration</label><p class=n>Reading now: <b>");
  s += String(readVoltage(), 2);
  s += F(" V</b> &nbsp;·&nbsp; factor ");
  s += String(g_cal, 3);
  s += F("</p><form action='/cal' method='get'>"
         "<input name='v' type='number' step='0.01' "
         "placeholder='Actual volts from meter'>"
         "<button type=submit>Calibrate</button></form>"
         "<form action='/calreset'><button class=off type=submit>"
         "Reset calibration</button></form>");

  s += F("<form action='/wifioff'><button class=off type=submit>"
         "Turn off WiFi</button></form>"
         "<p class=n>The WiFi name above is fixed in hardware and never changes. "
         "To calibrate, enter the true voltage from a multimeter and the node "
         "trims its reading to match. Press the node's PRG button to turn WiFi "
         "back on.</p><p class=n><a href='/update' style='color:#2dd47a'>"
         "Firmware update &rarr;</a></p></body></html>");
  return s;
}

void handleRoot() { server.send(200, "text/html", htmlPage()); }

// Catch-all: any other URL (incl. the OS captive-portal probes) → the config
// page, which makes phones pop the portal automatically on connect.
void handleNotFound() {
  server.sendHeader("Location", "http://192.168.4.1/", true);
  server.send(302, "text/plain", "");
}

void handleLogo() {
  server.sendHeader("Cache-Control", "max-age=86400");
  server.send_P(200, "image/jpeg", (const char*)logo_jpg, logo_jpg_len);
}

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
  server.sendHeader("Location", "/");
  server.send(303);                       // redirect back to the form
}

// Single-point gain calibration: enter the true voltage from a meter; the node
// trims its reading to match. Stored in flash so it survives reboots.
void handleCal() {
  if (server.hasArg("v")) {
    float actual  = server.arg("v").toFloat();
    float reading = readVoltage();                 // current (calibrated) reading
    if (actual > 0.5f && reading > 0.5f) {
      float f = g_cal * (actual / reading);        // fold into the existing factor
      if (f > 0.5f && f < 2.0f) {                  // sanity clamp
        g_cal = f;
        prefs.putFloat("cal", g_cal);
      }
    }
  }
  server.sendHeader("Location", "/");
  server.send(303);
}

void handleCalReset() {
  g_cal = 1.0f;
  prefs.putFloat("cal", g_cal);
  server.sendHeader("Location", "/");
  server.send(303);
}

// ── WiFi on/off (no extra hardware) ───────────────────────────────────────────
void wifiStart() {
  String ssid = "Brickdup-" + g_permId;
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ssid.c_str(), AP_PASSWORD);
  dnsServer.start(53, "*", WiFi.softAPIP());   // resolve all names → portal
  server.begin();
  portalActive = true;
  Serial.printf("[CFG] WiFi ON: '%s'  http://%s\n",
                ssid.c_str(), WiFi.softAPIP().toString().c_str());
}

void wifiStop() {
  dnsServer.stop();
  server.stop();
  WiFi.softAPdisconnect(true);
  WiFi.mode(WIFI_OFF);
  portalActive = false;
  Serial.println("[CFG] WiFi OFF (press PRG to re-enable)");
}

// Toggle WiFi and remember the choice across reboots.
void setWifi(bool on) {
  if (on) wifiStart(); else wifiStop();
  prefs.putBool("wifi", on);
}

void handleWifiOff() {
  server.send(200, "text/html",
    "<meta name=viewport content='width=device-width,initial-scale=1'>"
    "<body style='font-family:sans-serif;background:#111;color:#eee;padding:24px'>"
    "WiFi is turning off to save power.<br><br>"
    "Press the <b>PRG</b> button on the node to turn it back on.</body>");
  pendingWifiOff = true;   // drop the AP after this response is sent
}

// Deep sleep ("off"). Wakes on a button press; the node reboots fresh.
void powerOff() {
  oled.clear();                                 // white text on a black screen
  oled.setTextAlignment(TEXT_ALIGN_CENTER);
  oled.setFont(ArialMT_Plain_16);
  oled.drawString(64, 24, "POWERED DOWN");
  oled.setTextAlignment(TEXT_ALIGN_LEFT);
  oled.display();
  while (digitalRead(PRG_BUTTON) == LOW) delay(10);   // wait for release
  delay(1200);                                  // let the message be read
  digitalWrite(VEXT_PIN, HIGH);                 // cut the OLED rail
  delay(50);
  esp_sleep_enable_ext0_wakeup((gpio_num_t)PRG_BUTTON, 0);  // wake on next press (low)
  esp_deep_sleep_start();
}

// PRG button: single tap toggles WiFi, three quick taps power the unit off.
void pollButton() {
  bool b = digitalRead(PRG_BUTTON);
  if (b == LOW && lastBtn == HIGH && (millis() - lastBtnMs) > 80) {
    uint32_t now = millis();
    lastBtnMs = now;
    tapCount = (now - lastTapMs < 600) ? tapCount + 1 : 1;
    lastTapMs = now;
    if (tapCount >= 3) powerOff();
    else setWifi(!portalActive);
  }
  lastBtn = b;
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
    "<p class=n>This unit: <b>");
  s += NODE_TYPE; s += F(" &middot; v"); s += FW_VERSION;
  s += F("</b><br>Upload the matching .bin (Sketch -&gt; Export Compiled Binary).</p>"
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

void setup() {
  Serial.begin(115200);
  delay(500);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // Permanent id from the chip MAC, and the saved user name (defaults to it)
  g_permId = makePermId();
  prefs.begin("brickdup", false);
  g_name = prefs.getString("name", g_permId);
  g_cal  = prefs.getFloat("cal", 1.0f);

  // Power and start the onboard OLED
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, LOW);   // enable OLED power rail
  delay(50);
  oled.init();
  oled.clear();
  oled.setFont(ArialMT_Plain_10);
  oled.drawString(0, 0, "Brickdup booting...");
  oled.drawString(0, 14, g_permId.c_str());
  oled.display();

  // WiFi config portal. Toggle any time with the PRG button (no extra hardware)
  // or from the web page. The permanent id is the network name.
  pinMode(PRG_BUTTON, INPUT_PULLUP);
  server.on("/", handleRoot);
  server.on("/logo.jpg", handleLogo);
  server.on("/save", handleSave);
  server.on("/cal", handleCal);
  server.on("/calreset", handleCalReset);
  server.on("/wifioff", handleWifiOff);
  server.on("/update", HTTP_GET, handleUpdatePage);
  server.on("/update", HTTP_POST, handleUpdateDone, handleUpdateUpload);
  server.onNotFound(handleNotFound);   // captive-portal catch-all
  // Restore the saved WiFi state (off stays off across reboots)
  if (prefs.getBool("wifi", WIFI_ON_AT_BOOT)) {
    wifiStart();
  } else {
    WiFi.mode(WIFI_OFF);
    Serial.println("[CFG] WiFi off (saved) — press PRG to enable");
  }

#if USB_TEST_MODE
  Serial.printf("[BOOT] Brickdup %s '%s'  (USB-C TEST MODE)\n", g_permId.c_str(), g_name.c_str());
#else
  Serial.printf("[BOOT] Brickdup %s '%s'\n", g_permId.c_str(), g_name.c_str());
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
  return (float)(sum / ADC_SAMPLES) * VBAT_CAL * g_cal;
#else
  long sum = 0;
  for (int i = 0; i < ADC_SAMPLES; i++) {
    sum += analogRead(VBAT_PIN);
    delayMicroseconds(200);
  }
  return (float)(sum / ADC_SAMPLES) * ADC_SCALE * g_cal;
#endif
}

int voltageStatus(float v) {
  if (v < CRIT_V) return 2;
  if (v < WARN_V) return 1;
  return 0;
}

void loop() {
  pollButton();                               // PRG toggles WiFi on/off
  if (pendingWifiOff) { pendingWifiOff = false; delay(150); setWifi(false); }
  if (portalActive) { dnsServer.processNextRequest(); server.handleClient(); }

  uint32_t now = millis();
  if (now - lastTx >= TX_INTERVAL_MS) {
    lastTx = now;

    float voltage = readVoltage();
    int status = voltageStatus(voltage);
    drawOLED(voltage, status);

    char packet[96];
    snprintf(packet, sizeof(packet), "T:%s,I:%s,V:%.2f,S:%d,M:%s",
             NODE_TYPE, g_permId.c_str(), voltage, status, g_name.c_str());

    Serial.printf("[TX] %s\n", packet);

    int state = radio.transmit(packet);
    if (state != RADIOLIB_ERR_NONE) {
      Serial.printf("[ERR] TX failed: %d\n", state);
    }
  }
}
