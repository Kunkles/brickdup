// Brickdup — Universal battery sensor node (4S onboard OR 6S block)
// One board, one firmware: a universal divider sized for 6S, and a runtime
// "battery type" (OB 4S / BL 6S) that sets the thresholds + broadcast type.
// Pick the type on the web page, or LONG-PRESS the PRG button to toggle it.
// Hardware: Heltec WiFi LoRa 32 V3 (ESP32-S3 + SX1262, 915 MHz)
// Universal voltage divider: R1=200kΩ, R2=27kΩ on GPIO7 (25.2V → ~3.0V)

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
// Stable permanent id from the chip MAC, e.g. "ND-7F3A" — never changes (even if
// you flip the battery type), is the WiFi network name, and is what the receiver
// tracks by. The battery type (OB/BL) is broadcast separately, so toggling it
// updates the node in place instead of spawning a new one.
#define FW_VERSION "0.5.0" // shown small in the OLED corner

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
//     instead of the external divider. Lets you verify TX → RX → e-ink with
//     NOTHING wired up — just power the V3 over USB-C.
// 0 = real mode: read the external universal divider on GPIO7.
#define USB_TEST_MODE  1

// ── Thresholds (volts) ────────────────────────────────────────────────────────
// Set at runtime by battery type — see warnV()/critV() below. (In USB test mode
// the source is a single cell ~4V, so single-cell levels are used instead.)
#define TEST_WARN_V  3.50f
#define TEST_CRIT_V  3.30f

// ── ADC (universal divider, R1=200k / R2=27k) ────────────────────────────────
#define VBAT_PIN    7       // external divider input (real mode)
#define ADC_SAMPLES 16
// Vout = Vin * R2/(R1+R2) = Vin * 27/(200+27); 25.2V → ~3.0V (headroom)
// ADC_SCALE = (R1+R2)/R2 * (3.3/4095)
#define ADC_SCALE  (227.0f / 27.0f * 3.3f / 4095.0f)

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
uint8_t     g_mode  = 0;            // battery type: 0 = OB (4S), 1 = BL (6S)
bool        portalActive = false;   // is the WiFi portal running?
bool        pendingWifiOff = false; // request to drop WiFi after a web response
bool        btnDown = false;        // PRG button state machine
uint32_t    btnPressedAt = 0;
bool        btnLongFired = false;
uint8_t     tapCount = 0;           // triple-tap power-off
uint32_t    lastTapMs = 0;
uint32_t    lastTx = 0;

#define LONGPRESS_MS 1000           // hold PRG this long to toggle battery type

// Battery type → broadcast string and thresholds
const char* g_type() { return g_mode ? "BL" : "OB"; }
float warnV() {
#if USB_TEST_MODE
  return TEST_WARN_V;
#else
  return g_mode ? 21.0f : 13.5f;
#endif
}
float critV() {
#if USB_TEST_MODE
  return TEST_CRIT_V;
#else
  return g_mode ? 20.0f : 12.8f;
#endif
}

// Stable permanent id from the chip's MAC: e.g. "ND-7F3A". Unique per board,
// independent of battery type.
String makePermId() {
  uint16_t suffix = (uint16_t)(ESP.getEfuseMac() & 0xFFFF);
  char buf[16];
  snprintf(buf, sizeof(buf), "ND-%04X", suffix);
  return String(buf);
}

// 7-segment bitmasks for 0–9 (bit0=a top, 1=b, 2=c, 3=d, 4=e, 5=f, 6=g middle)
const uint8_t SEG7[10] = {0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07,0x7F,0x6F};

void drawDigit7(int x, int y, int w, int h, int t, uint8_t s) {
  int mid = y + (h - t) / 2, bot = y + h - t;
  if (s & 0x01) oled.fillRect(x + t,     y,        w - 2*t, t);            // a
  if (s & 0x20) oled.fillRect(x,         y + t,    t, mid - (y + t));      // f
  if (s & 0x02) oled.fillRect(x + w - t, y + t,    t, mid - (y + t));      // b
  if (s & 0x40) oled.fillRect(x + t,     mid,      w - 2*t, t);            // g
  if (s & 0x10) oled.fillRect(x,         mid + t,  t, bot - (mid + t));    // e
  if (s & 0x04) oled.fillRect(x + w - t, mid + t,  t, bot - (mid + t));    // c
  if (s & 0x08) oled.fillRect(x + t,     bot,      w - 2*t, t);            // d
}

// Draw the voltage big in 7-seg starting at (x,y); returns the x after it.
int drawVoltage7(int x, int y, float v) {
  char str[8];
  snprintf(str, sizeof(str), "%.1f", v);
  const int W = 16, H = 30, T = 4, GAP = 6;   // GAP = space between digits
  int mid = y + (H - T) / 2, bot = y + H - T;
  for (char* p = str; *p; p++) {
    if (*p == '1') {                          // narrow cell: just the vertical
      oled.fillRect(x, y + T,     T, mid - (y + T));
      oled.fillRect(x, mid + T,   T, bot - (mid + T));
      x += T + GAP;
    } else if (*p >= '0' && *p <= '9') {
      drawDigit7(x, y, W, H, T, SEG7[*p - '0']); x += W + GAP;
    } else if (*p == '.') {
      oled.fillRect(x, y + H - T, T, T);       x += T + GAP;
    }
  }
  return x;
}

// Chunky angled "V" in the same blocky LED style as the digits.
void drawV7(int x, int y, int w, int h, int t) {
  int xm = x + w / 2;
  for (int i = 0; i < t; i++) {
    oled.drawLine(x + i,         y, xm, y + h);   // left diagonal (thickened)
    oled.drawLine(x + w - 1 - i, y, xm, y + h);   // right diagonal (thickened)
  }
}

void drawOLED(float voltage, int status) {
  const char* tag     = (status == 2) ? "CRIT" : (status == 1) ? "WARN" : "OK";
  const char* typeStr = g_mode ? "6S" : "4S";

  oled.clear();

  // Top: WiFi network name (left), status (right)
  oled.setFont(ArialMT_Plain_10);
  oled.setTextAlignment(TEXT_ALIGN_LEFT);
  if (portalActive) { String w = "Brickdup-" + g_permId; oled.drawString(0, 0, w.c_str()); }
  else              { oled.drawString(0, 0, g_permId.c_str()); }
  oled.setTextAlignment(TEXT_ALIGN_RIGHT);
  oled.drawString(128, 0, tag);

  // User name
  oled.setFont(ArialMT_Plain_16);
  oled.setTextAlignment(TEXT_ALIGN_LEFT);
  oled.drawString(0, 12, g_name.c_str());

  // Big 7-segment voltage + a matching lowercase "v" on the baseline (like the
  // logo's "14.8v"): shorter, bottom-aligned with the digits.
  int vx = drawVoltage7(2, 30, voltage);
  drawV7(vx + 3, 42, 16, 18, 4);   // y+h = 60 = digit baseline

  // Right column: battery type (where "USB TEST" used to be) + version
  oled.setFont(ArialMT_Plain_10);
  oled.setTextAlignment(TEXT_ALIGN_RIGHT);
#if USB_TEST_MODE
  oled.drawString(128, 30, "USB TEST");
  oled.drawString(128, 42, typeStr);
#else
  oled.drawString(128, 32, typeStr);
#endif
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
  s += g_type();
  s += F("</span> node</h1>"
         "<div class=wifi>WiFi network (fixed)<br><b>Brickdup-");
  s += g_permId;
  s += F("</b></div><form action='/save' method='get'>"
         "<label>Name</label><input name='name' maxlength='10' value='");
  s += g_name;
  s += F("'><label>Battery type</label>"
         "<select name='mode' style='width:100%;padding:10px;font-size:16px;"
         "border:1px solid #444;border-radius:6px;background:#222;color:#fff'>");
  s += g_mode == 0 ? F("<option value=0 selected>Onboard — 4S (up to 16.8V)</option>"
                       "<option value=1>Block — 6S (up to 25.2V)</option>")
                   : F("<option value=0>Onboard — 4S (up to 16.8V)</option>"
                       "<option value=1 selected>Block — 6S (up to 25.2V)</option>");
  s += F("</select><button type=submit>Save</button></form>");

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
         "<p class=n>The WiFi name above is fixed and never changes. Battery type "
         "sets the thresholds (4S 13.5/12.8V, 6S 21/20V) — you can also LONG-PRESS "
         "the PRG button to toggle it. To calibrate, enter the true voltage from a "
         "meter. Tap PRG to turn WiFi back on.</p><p class=n>"
         "<a href='/update' style='color:#2dd47a'>Firmware update &rarr;</a></p>"
         "</body></html>");
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
  if (server.hasArg("mode")) {
    g_mode = server.arg("mode").toInt() ? 1 : 0;
    prefs.putUChar("mode", g_mode);
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

// Toggle battery type (4S ↔ 6S), remember it, and confirm on the OLED.
void cycleMode() {
  g_mode ^= 1;
  prefs.putUChar("mode", g_mode);
  // Immediate, unmistakable confirmation
  oled.clear();
  oled.setTextAlignment(TEXT_ALIGN_CENTER);
  oled.setFont(ArialMT_Plain_24);
  oled.drawString(64, 4, g_mode ? "BL 6S" : "OB 4S");
  oled.setFont(ArialMT_Plain_10);
  oled.drawString(64, 42, g_mode ? "BLOCK (6S)" : "ONBOARD (4S)");
  oled.setTextAlignment(TEXT_ALIGN_LEFT);
  oled.display();
  delay(800);                            // hold the confirmation briefly
  lastTx = millis() - TX_INTERVAL_MS;    // transmit + redraw normally right away
}

// PRG button: short tap = WiFi toggle, long press = switch battery type,
// three quick taps = power off.
void pollButton() {
  bool down = (digitalRead(PRG_BUTTON) == LOW);
  uint32_t now = millis();
  if (down && !btnDown) {                  // press
    btnDown = true; btnPressedAt = now; btnLongFired = false;
  } else if (down && btnDown && !btnLongFired && now - btnPressedAt >= LONGPRESS_MS) {
    btnLongFired = true;                    // long press → switch battery type
    cycleMode();
  } else if (!down && btnDown) {            // release
    btnDown = false;
    if (!btnLongFired && now - btnPressedAt >= 40) {   // a tap
      tapCount = (now - lastTapMs < 600) ? tapCount + 1 : 1;
      lastTapMs = now;
      if (tapCount >= 3) powerOff();
      else setWifi(!portalActive);
    }
  }
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
  s += g_type(); s += F(" &middot; v"); s += FW_VERSION;
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
  g_mode = prefs.getUChar("mode", 0);   // 0 = OB (4S) default

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

// TEMP: force a fixed voltage on the display for a quick layout preview.
// Set DEMO_VOLTAGE_ON to 0 for normal operation.
#define DEMO_VOLTAGE_ON  1
#define DEMO_VOLTAGE     16.2f

float readVoltage() {
#if DEMO_VOLTAGE_ON
  return DEMO_VOLTAGE;
#elif USB_TEST_MODE
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
  if (v < critV()) return 2;
  if (v < warnV()) return 1;
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
             g_type(), g_permId.c_str(), voltage, status, g_name.c_str());

    Serial.printf("[TX] %s\n", packet);

    int state = radio.transmit(packet);
    if (state != RADIOLIB_ERR_NONE) {
      Serial.printf("[ERR] TX failed: %d\n", state);
    }
  }
}
