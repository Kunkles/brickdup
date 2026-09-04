#!/usr/bin/env python3
"""
camera_bridge.py — ARRI camera battery -> brickdup packet bridge.

Reads battery telemetry from one or more ARRI cameras over the network and
emits brickdup packet lines on the normal 10 s heartbeat. Each camera shows
up on the handheld as its own node.

Why bridge instead of measure: the camera's own reading is ~13 mV resolution
inside a ~65 mV band (measured on an ALEXA 35 at 28.5 V, ~1.2 Hz). A node's
200k/22k divider into the ESP32-S3 ADC can't match that, least of all near
the top of its range where a 7S B-mount lands. And the camera has already
mapped volts -> percent with the correct curve for its own battery, so
passing that percent through is what makes the handheld agree with what the
crew reads off the camera.

Camera API (no auth, plain HTTP):
    GET /all.cgi            -> full snapshot + an "id"
    GET /update.cgi?id=N    -> only what changed since N, + a new id (long-poll)
  (/set.cgi and /call.cgi are writes — this tool never touches them.)

Output line:
    T:CAM,I:CAM-63373,V:28.483,P:97,S:0,M:A

    T  packet type (CAM = camera-sourced, not a measured node)
    I  stable id from the camera serial
    V  Bat1LevelVolt — RESTING while on AC, ~0.9 V lower once it takes load
    P  Bat1LevelPercent — the camera's own number, NOT derived from V
    S  0 OK / 1 WARN / 2 CRIT, from the camera's own warn thresholds
    A  1 = running on AC (battery idle), 0 = running on the battery
    M  camera letter from CameraIndexDual ("A_" -> "A")

Why P: matters (measured on an ALEXA 35, 2026-09-02): idle on AC the
voltage sits in a 65 mV band, but once the battery carries the camera it
swings 403 mV as draw varies — several percent of a 7S pack's usable range.
Deriving SoC from that would jitter constantly. The camera's own percent
walked 94 -> 93 -> 91 -> 90 over the same window with no jitter at all, so
it is both steadier and the number the crew is reading off the camera.

Cameras are found automatically. ARRI bodies advertise themselves over
mDNS as "alexa35-<serial>" on _cap._tcp (ARRI's Camera Access Protocol), so
no IPs need configuring and cameras powered up mid-day get picked up on the
next discovery pass. If mDNS returns nothing (some set networks block
multicast between VLANs) the bridge falls back to sweeping the local /24 for
hosts serving the ARRI Web Remote.

Run it with a terminal attached and you get a live status board — which
cameras are connected, whether each is on AC or its battery, the current
reading, and when the next packet goes out. Pipe it anywhere (or pass
--plain) and it falls back to one packet per line, so feeding a gateway or
a log file is unchanged.

No third-party packages are required — --serial works without pyserial
(Homebrew and Debian Pythons refuse `pip install` into the system
environment under PEP 668, and the usual workarounds risk breaking the
Python install; not needing the package at all sidesteps that).

Usage:
    python3 camera_bridge.py                          # live status board
    python3 camera_bridge.py --serial /dev/tty.usbserial-0001
    python3 camera_bridge.py --cameras 10.2.2.200,10.2.2.201   # skip discovery
    python3 camera_bridge.py --no-scan                # mDNS only, never sweep
"""

import argparse
import collections
import select
import json
import math
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# One radio speaks for every camera, and it shares the channel with the real
# battery nodes -- so each camera is a recurring airtime cost, not a free ride.
# A 43-byte camera packet is ~288 ms on air at SF9/BW125/CR4-5. Cameras move
# a few percent per TEN MINUTES, so 30 s is plenty and costs a third of what
# the 10 s node heartbeat would: 6 cameras at 30 s load the channel less than
# 2 cameras at 10 s. Raise --interval before adding bodies, not after.
LOG = collections.deque(maxlen=6)
LIVE = False              # set once we know stdout is a terminal


def log(msg):
    """Status chatter. Goes to the log pane when live, stderr when piped."""
    if LIVE:
        LOG.append((time.strftime("%H:%M:%S"), msg))
    else:
        print(f"# {msg}", file=sys.stderr, flush=True)


TX_INTERVAL = 30.0
STALE_AFTER = 30.0        # no fresh data for this long -> stop transmitting
POLL_TIMEOUT = 20         # long-poll timeout; update.cgi blocks until change
RECONNECT_WAIT = 3.0      # after a network error (the link does blip)
DISCOVER_EVERY = 60.0     # re-run discovery this often, to catch late power-ups
MDNS_SERVICE = "_cap._tcp"    # ARRI Camera Access Protocol

# Variables we care about. Everything else in the ~1360-variable model is
# ignored, but the delta stream hands it to us for free if it ever matters.
# NOTE: Bat1* is the real battery on the mount. Bat2* is NOT a battery --
# it is the Pwr/AC input rail reported through battery-shaped names (proved
# 2026-09-02: unplugging AC drove Bat2LevelVolt to 0 and Bat2State to 2).
# Never rebroadcast Bat2; a permanent 0 % would be actively misleading.
WATCH = (
    "Bat1LevelVolt", "Bat1LevelPercent",
    "Bat1WarnLevelVolt", "Bat1WarnLevelPercent",
    "PowerInputBatInUse", "PowerInputPwrPresent",
    "Bat2LevelVolt",           # the AC/Pwr INPUT rail, not a battery

    "SystemCameraSerial", "CameraIndexDual",
)


# ------------------------------------------------------------- serial output --

def autodetect_port():
    """The single attached USB-serial port, or a clear error saying why not.

    The gateway shows up as /dev/cu.usbserial-* (the V3's CP2102) or
    /dev/cu.usbmodem* (native USB). Bluetooth and internal ports are excluded
    — they are always present and never the gateway.
    """
    import glob
    cands = sorted(set(glob.glob("/dev/cu.usbserial*") +
                       glob.glob("/dev/cu.usbmodem*") +
                       glob.glob("/dev/ttyUSB*") + glob.glob("/dev/ttyACM*")))
    if not cands:
        raise SystemExit(
            "no USB-serial port found — is the gateway plugged in?\n"
            "  check with:  ls /dev/cu.*\n"
            "  if it comes and goes, try plugging it straight into the machine "
            "rather than through a hub or dock.")
    if len(cands) > 1:
        raise SystemExit("several USB-serial ports found; name the one you want "
                         "with --serial PORT:\n  " + "\n  ".join(cands))
    return cands[0]




class SerialOut:
    """Write-only serial port, with no third-party dependency.

    Uses pyserial when it happens to be installed, but doesn't need it: all
    this tool ever does is push newline-terminated ASCII at a tty, which is
    plain file I/O once `stty` has set the line discipline. That matters
    because Homebrew/Debian Pythons refuse `pip install` into the system
    environment (PEP 668), and the workarounds there are worse than the
    problem.

    Open the device BEFORE running stty so our handle keeps the settings
    alive; on macOS use the /dev/cu.* (callout) name, which doesn't block
    waiting for carrier detect the way /dev/tty.* does.
    """

    def __init__(self, port, baud):
        self.port, self.how = port, ""
        self._ser = None
        self._fd = None
        try:
            import serial                                  # noqa: F401
            self._ser = serial.Serial(port, baud, timeout=1)
            self.how = "pyserial"
            return
        except ImportError:
            pass
        except Exception as e:
            raise SystemExit(f"could not open {port}: {e}")

        try:
            self._fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        except OSError as e:
            raise SystemExit(f"could not open {port}: {e}")
        flag = "-f" if sys.platform == "darwin" else "-F"
        r = subprocess.run(["stty", flag, port, str(baud), "raw", "-echo"],
                           capture_output=True, text=True)
        if r.returncode:
            os.close(self._fd)
            raise SystemExit(f"stty failed on {port}: {r.stderr.strip()}")
        self.how = "raw tty"

    def write_line(self, line):
        data = (line + "\n").encode()
        if self._ser:
            self._ser.write(data)
        else:
            os.write(self._fd, data)

    def read_available(self, seconds):
        """Whatever the far end says within `seconds`."""
        buf = b""
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if self._ser:
                buf += self._ser.read(4096) or b""
                time.sleep(0.1)
            else:
                r, _, _ = select.select([self._fd], [], [], 0.2)
                if r:
                    try:
                        buf += os.read(self._fd, 4096)
                    except BlockingIOError:
                        pass
        return buf.decode("utf-8", "replace")

    def probe_gateway(self):
        """Confirm a brickdup GATEWAY is on the far end, not some other board.

        Sending packets at whatever happens to be plugged in fails silently:
        a sensor node ignores serial input entirely, so the bridge looks
        healthy while nothing reaches the air. The gateway answers any
        non-packet line with `[SKIP]`, which costs no airtime, so one probe
        settles it. Returns (ok, what_we_heard).
        """
        self.read_available(0.3)                     # clear anything pending
        self.write_line("PING")                      # not a packet -> [SKIP]
        heard = self.read_available(2.0)
        ok = ("[SKIP]" in heard or "[OK]" in heard or "[BOOT]" in heard)
        return ok, heard.strip()

    def close(self):
        if self._ser:
            self._ser.close()
        elif self._fd is not None:
            os.close(self._fd)


# ------------------------------------------------------------------ airtime --

# Must match the node/receiver radio config (see sensor_universal sketch).
SF, BW_HZ, CR, PREAMBLE = 9, 125000, 1, 8
NODE_PACKET_MS = 329      # a typical measured-node packet, for the budget line


def airtime_ms(payload_len):
    """LoRa time-on-air for a payload, per the SX1262 datasheet formula."""
    ts = (2 ** SF) / BW_HZ
    de = 1 if (SF >= 11 and BW_HZ == 125000) else 0
    n = 8 + max(0, math.ceil((8 * payload_len - 4 * SF + 28 + 16) /
                             (4 * (SF - 2 * de))) * (CR + 4))
    return ((PREAMBLE + 4.25) * ts + n * ts) * 1000


def airtime_report(n_cams, interval, assumed_nodes=5):
    """One line on what these cameras cost the shared channel."""
    if not n_cams:
        return "no cameras yet"
    per = airtime_ms(43)
    cam_load = n_cams * per / (interval * 1000)
    node_load = assumed_nodes * NODE_PACKET_MS / 10000
    total = cam_load + node_load
    # pure ALOHA: no listen-before-talk in this design, so success ~ e^-2G
    success = math.exp(-2 * total) * 100
    note = "  <-- raise --interval" if total > 0.25 else ""
    return (f"{n_cams} camera(s) x {per:.0f} ms / {interval:.0f}s = "
            f"{cam_load*100:.1f}% channel; with ~{assumed_nodes} nodes "
            f"~{total*100:.0f}% load, ~{success:.0f}% packet success{note}")


# -------------------------------------------------------------- status feed --

def status_dict(cams, args, port, gw_state):
    """Everything a UI needs, as plain data. One dict per tick."""
    now = time.monotonic()
    out = []
    for c in cams.values():
        st = c.snapshot()
        age = (now - c.updated) if c.updated else None
        fresh = age is not None and age <= STALE_AFTER
        if c.dup_of:
            link = "duplicate"
        elif not c.online:
            link = "offline"
        elif not fresh:
            link = "stale"
        elif st.get("PowerInputPwrPresent") and not st.get("PowerInputBatInUse"):
            link = "on_ac"
        else:
            link = "battery"
        out.append({
            "label":  (st.get("CameraIndexDual") or "?").replace("_", ""),
            "host":   c.host,
            "serial": st.get("SystemCameraSerial"),
            "link":   link,
            "volts":  st.get("Bat1LevelVolt"),
            "pct":    st.get("Bat1LevelPercent"),
            # Input rail shown alongside the pack: a camera on mains can still
            # be draining its onboard battery through accessories, so knowing
            # only "it's on AC" is not enough. Local-only — not worth airtime.
            "in_volts": st.get("Bat2LevelVolt"),
            "warn":   st.get("Bat1WarnLevelPercent"),
            "age":    round(age, 1) if age is not None else None,
            "sent":   c.sent,
            "next":   round(max(0, c.next_tx - now), 1),
            "last":   c.last_line,
        })
    out.sort(key=lambda r: (r["label"] or "~"))
    return {
        "gateway": {"port": args.serial if port else None,
                    "how": port.how if port else None,
                    "ok": bool(gw_state)},
        "interval": args.interval,
        "airtime": airtime_report(len(cams), args.interval),
        "cameras": out,
    }


# ------------------------------------------------------------------ display --

C = {"dim": "\033[2m", "red": "\033[31m", "yel": "\033[33m",
     "grn": "\033[32m", "cyn": "\033[36m", "bold": "\033[1m", "off": "\033[0m"}


def _c(name, text):
    return f"{C[name]}{text}{C['off']}" if LIVE else text


def render(cams, interval, gateway=None):
    """Full-screen status: are the cameras connected, and what are they saying."""
    out = ["\033[H\033[J"]                       # home + clear
    out.append(_c("bold", "brickdup camera bridge") +
               _c("dim", f"   interval {interval:.0f}s   "
                         f"{airtime_report(len(cams), interval)}"))
    # Seeing cameras here means nothing if the packets aren't reaching the
    # radio — without a gateway this is a viewer, not a bridge, and the
    # handheld will show every camera LOST.
    if gateway:
        out.append(_c("grn", f"  gateway  {gateway}  (confirmed)"))
    elif gateway is False:
        out.append(_c("red", "  gateway  PORT OPEN BUT NOT A GATEWAY — "
                             "nothing is being transmitted"))
    else:
        out.append(_c("yel", "  gateway  NOT CONNECTED — nothing is being "
                             "transmitted (pass --serial PORT)"))
    out.append("")
    out.append(_c("dim", f"  {'CAM':<4} {'HOST':<15} {'SERIAL':<8} {'LINK':<13}"
                         f" {'BATTERY':<15} {'DATA':<7} {'SENT':<6} NEXT"))

    now = time.monotonic()
    if not cams:
        out.append(_c("dim", "  (searching…)"))
    for c in cams.values():
        st = c.snapshot()
        age = now - c.updated if c.updated else None
        fresh = age is not None and age <= STALE_AFTER

        # Pad the PLAIN text first, then colour it — ANSI escapes count
        # toward a format width, so colouring first makes columns jump as
        # states change length.
        if c.dup_of:
            link_txt, link_col = "● dup", "dim"
        elif not c.online:
            link_txt, link_col = "● offline", "red"
        elif not fresh:
            link_txt, link_col = "● stale", "yel"
        elif st.get("PowerInputPwrPresent") and not st.get("PowerInputBatInUse"):
            link_txt, link_col = "● on AC", "cyn"
        else:
            link_txt, link_col = "● battery", "grn"

        v, pct = st.get("Bat1LevelVolt"), st.get("Bat1LevelPercent")
        if v is None:
            batt_txt, batt_col = "—", "dim"
        else:
            warn = st.get("Bat1WarnLevelPercent") or 10
            batt_txt = f"{v:6.2f}V " + (f"{pct:3}%" if pct is not None else "   ?")
            batt_col = ("red" if pct is not None and pct <= max(1, warn // 2)
                        else "yel" if pct is not None and pct <= warn else "grn")

        label = (st.get("CameraIndexDual") or "?").replace("_", "")
        serial = str(st.get("SystemCameraSerial") or "—")
        age_txt = f"{age:.1f}s" if age is not None else "—"
        nxt_txt = "—" if c.dup_of else f"{max(0, c.next_tx - now):.1f}s"
        out.append(f"  {label:<4} {c.host:<16} {serial:<8} "
                   + _c(link_col, f"{link_txt:<13}") + " "
                   + _c(batt_col, f"{batt_txt:<15}") +
                   f" {age_txt:<7} {c.sent:<6} {nxt_txt}")

    last = max((c for c in cams.values() if c.last_tx_wall),
               key=lambda c: c.last_tx_wall, default=None)
    out.append("")
    out.append(_c("dim", "  last sent  ") +
               (last.last_line if last else _c("dim", "—")))
    if LOG:
        out.append("")
        for ts, msg in LOG:
            out.append(_c("dim", f"  {ts}  {msg}"))
    out.append("")
    out.append(_c("dim", "  ctrl-c to stop"))
    sys.stdout.write("\n".join(out) + "\n")
    sys.stdout.flush()


# ---------------------------------------------------------------- discovery --

def _mdns_instances(timeout=5.0):
    """Instance names advertised on _cap._tcp (e.g. 'alexa35-63373')."""
    if shutil.which("dns-sd"):                       # macOS
        cmd, parse_add = ["dns-sd", "-B", MDNS_SERVICE, "local."], True
    elif shutil.which("avahi-browse"):               # Linux
        cmd, parse_add = ["avahi-browse", "-p", "-t", MDNS_SERVICE], False
    else:
        return []

    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True)
        try:
            out, _ = p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            p.kill()                                 # dns-sd -B never exits
            out, _ = p.communicate()
    except OSError:
        return []

    names = []
    for line in out.splitlines():
        if parse_add:
            # dns-sd: "... Add  3  25 local.  _cap._tcp.  alexa35-63373"
            m = re.search(r"\bAdd\b.*\s(\S+)\s*$", line)
            if m:
                names.append(m.group(1))
        else:
            # avahi -p: "+;eth0;IPv4;alexa35-63373;_cap._tcp;local"
            f = line.split(";")
            if len(f) > 3 and line.startswith("+"):
                names.append(f[3])
    return sorted(set(names))


def _local_subnets():
    """/24 prefixes of this host's IPv4 addresses, e.g. ['10.2.2.']."""
    nets = set()
    for fam, _, _, _, sa in socket.getaddrinfo(socket.gethostname(), None):
        if fam == socket.AF_INET:
            ip = sa[0]
            if not ip.startswith("127."):
                nets.add(ip.rsplit(".", 1)[0] + ".")
    return sorted(nets)


def _is_arri(host, timeout=1.5):
    """Cheap fingerprint: the root page is the ARRI Web Remote (~2 kB)."""
    try:
        with urllib.request.urlopen(f"http://{host}/", timeout=timeout) as r:
            return b"ARRI" in r.read(4096)
    except Exception:
        return False


def _sweep(timeout=1.5):
    """Last resort: probe every host on our /24 for the ARRI Web Remote."""
    hosts = [f"{net}{i}" for net in _local_subnets() for i in range(1, 255)]
    if not hosts:
        return []
    with ThreadPoolExecutor(max_workers=128) as ex:
        hits = ex.map(lambda h: (h, _is_arri(h, timeout)), hosts)
        return sorted(h for h, ok in hits if ok)


def discover(allow_sweep=True):
    """Return camera hosts. mDNS first; sweep only if that finds nothing."""
    found = []
    for name in _mdns_instances():
        host = f"{name}.local"
        for attempt in range(2):                      # .local answers are flaky
            try:
                found.append(socket.gethostbyname(host))   # prefer the IP
                break
            except OSError:
                if attempt:
                    found.append(host)                # let urllib try the name
                else:
                    time.sleep(0.3)
    if found:
        return sorted(set(found))
    if allow_sweep:
        log("mDNS found nothing — sweeping the local subnet")
        return _sweep()
    return []



class Camera(threading.Thread):
    """Long-polls one camera, keeping the latest values in .state."""

    daemon = True

    def __init__(self, host):
        super().__init__(name=f"cam-{host}")
        self.host = host
        self.state = {}
        self.updated = 0.0        # monotonic time of last good read
        self.online = False
        self.next_tx = 0.0        # monotonic time this camera next transmits
        self.sent = 0             # packets emitted
        self.dup_of = None        # set when another host is the same body
        self.last_line = ""       # most recent packet, for the display
        self.last_tx_wall = None
        self._lock = threading.Lock()

    def _get(self, path, timeout):
        url = f"http://{self.host}{path}"
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return json.load(r)

    def _absorb(self, variables):
        with self._lock:
            for k, v in variables.items():
                if k in WATCH:
                    self.state[k] = v.get("value")
        self.updated = time.monotonic()

    def snapshot(self):
        with self._lock:
            return dict(self.state)

    def run(self):
        while True:
            try:
                d = self._get("/all.cgi", timeout=15)
                self._absorb(d.get("variables", {}))
                ident = self.snapshot()
                self.online = True
                log(f"{self.host} connected: serial="
                    f"{ident.get('SystemCameraSerial')} "
                    f"cam={(ident.get('CameraIndexDual') or '?').replace('_','')}")
                uid = d.get("id", 0)
                while True:
                    r = self._get(f"/update.cgi?id={uid}", timeout=POLL_TIMEOUT)
                    uid = r.get("id", uid)
                    self._absorb(r.get("variables", {}))
            except (urllib.error.URLError, OSError, json.JSONDecodeError,
                    TimeoutError) as e:
                if self.online:
                    log(f"{self.host} lost ({e}); reconnecting")
                self.online = False
                time.sleep(RECONNECT_WAIT)


def status_for(pct, volt, warn_pct, warn_volt):
    """Map to brickdup status using the CAMERA's own thresholds.

    The camera exposes one warn level per unit; CRIT is taken as half of it,
    so the handheld escalates on the same schedule the camera does rather
    than on brickdup's 6S block numbers, which don't fit a 7S B-mount.
    """
    if pct is not None and warn_pct:
        if pct <= max(1, warn_pct // 2):
            return 2
        if pct <= warn_pct:
            return 1
        return 0
    if volt is not None and warn_volt:
        if volt <= warn_volt - 1.0:
            return 2
        if volt <= warn_volt:
            return 1
    return 0


def packet_for(cam):
    """Build one brickdup line, or None if the camera has nothing fresh."""
    if time.monotonic() - cam.updated > STALE_AFTER:
        return None       # go quiet; the receiver's own STALE/LOST handles it
    s = cam.snapshot()
    serial = s.get("SystemCameraSerial")
    volt = s.get("Bat1LevelVolt")
    if serial is None or volt is None:
        return None

    pct = s.get("Bat1LevelPercent")
    st = status_for(pct, volt,
                    s.get("Bat1WarnLevelPercent"), s.get("Bat1WarnLevelVolt"))

    fields = [f"T:CAM", f"I:CAM-{serial}", f"V:{volt:.3f}"]
    if pct is not None:
        fields.append(f"P:{pct}")
    fields.append(f"S:{st}")

    # On AC the battery is idle: V is a resting reading and the pack is not
    # draining. Sent so the handheld can distinguish "low but parked on AC"
    # (hot-swap isn't ready) from "low and actively discharging" (act now).
    on_ac = s.get("PowerInputPwrPresent") and not s.get("PowerInputBatInUse")
    if s.get("PowerInputPwrPresent") is not None:
        fields.append(f"A:{1 if on_ac else 0}")

    # "A_" -> "A"; the trailing underscore is the dual-camera slot separator
    label = (s.get("CameraIndexDual") or "").replace("_", "").strip()
    if label:
        fields.append(f"M:{label}")
    return ",".join(fields)


def main():
    global LIVE
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cameras", default=None,
                    help="comma-separated camera IPs/hostnames; skips discovery")
    ap.add_argument("--interval", type=float, default=TX_INTERVAL,
                    help="seconds between packets PER CAMERA (default 30; see the "
                         "airtime note at the top before lowering it)")
    ap.add_argument("--serial", metavar="PORT", nargs="?", const="auto",
                    help="write packets to the LoRa gateway on this serial port. "
                         "Give no value to auto-detect the single attached "
                         "USB-serial port. No pyserial needed.")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--no-scan", action="store_true",
                    help="never sweep the subnet; rely on mDNS alone")
    ap.add_argument("--json", action="store_true", dest="as_json",
                    help="emit one JSON status line per second on stdout "
                         "instead of packets — the menu bar app's feed")
    ap.add_argument("--plain", action="store_true",
                    help="one packet per line on stdout, no live display "
                         "(automatic when stdout is not a terminal)")
    args = ap.parse_args()

    # Live dashboard only when a human is watching. Piping to a gateway or a
    # log file keeps the old line-per-packet behaviour untouched.
    LIVE = sys.stdout.isatty() and not args.plain and not args.as_json

    port = None
    if args.serial:
        if args.serial == "auto":
            args.serial = autodetect_port()
            log(f"auto-detected gateway port {args.serial}")
        port = SerialOut(args.serial, args.baud)
        time.sleep(2)              # the ESP32 reboots when the port opens
        ok, heard = port.probe_gateway()
        if ok:
            gw_state = f"{args.serial} ({port.how})"
            log(f"gateway confirmed on {args.serial} ({port.how})")
        else:
            gw_state = False
            first = (heard.splitlines() or ["nothing"])[0][:60]
            log(f"WARNING: {args.serial} did not answer as a gateway "
                f"(heard: {first}) — packets may be going nowhere")
            if "[TX]" in heard or "[LIPO]" in heard:
                log("that looks like a SENSOR NODE, not the gateway — "
                    "it ignores serial input, so nothing will be transmitted")
    else:
        gw_state = None            # no --serial: not connected, not failed

    fixed = None
    if args.cameras:
        fixed = [h.strip() for h in args.cameras.split(",") if h.strip()]

    cams = {}

    def sync_cameras():
        """Add newly-seen cameras and re-space everyone's transmit slots."""
        hosts = fixed if fixed is not None else discover(not args.no_scan)
        added = False
        for h in hosts:
            if h not in cams:
                log(f"discovered {h}")
                c = Camera(h)
                c.start()
                cams[h] = c
                added = True
        if added:
            # STAGGER: one camera per slot across the interval. Emitting them
            # back to back would hold the channel for N x ~288 ms straight and
            # stomp on any node transmitting in that window.
            now = time.monotonic()
            for i, c in enumerate(cams.values()):
                c.next_tx = now + i * args.interval / len(cams)
            log(airtime_report(len(cams), args.interval))

    def dedupe():
        """One body can be discovered twice (by IP one pass, by .local the
        next) — that would double-transmit it. The camera serial is the real
        identity, so keep the first host to claim each serial."""
        first = {}
        for host, c in cams.items():
            sn = c.snapshot().get("SystemCameraSerial")
            if sn is None:
                continue
            if sn in first:
                if c.dup_of is None:
                    c.dup_of = first[sn]
                    log(f"{host} is the same body as {first[sn]} (serial {sn});"
                        f" not transmitting it twice")
            else:
                first[sn] = host
                c.dup_of = None

    def emit(c):
        """Returns True if a packet actually went out."""
        if c.dup_of:
            return True            # counted as done; the original transmits
        line = packet_for(c)
        if line is None:
            return False           # no data yet, or stale — stay quiet
        c.last_line = line
        c.last_tx_wall = time.time()
        c.sent += 1
        if port:
            port.write_line(line)
        if not LIVE:
            print(line, flush=True)
        return True

    if LIVE:
        sys.stdout.write("\033[?25l")     # hide cursor
    sync_cameras()
    last_discovery = time.monotonic()

    try:
        while True:
            now = time.monotonic()
            if fixed is None and now - last_discovery > DISCOVER_EVERY:
                sync_cameras()
                last_discovery = now

            dedupe()
            for c in list(cams.values()):
                if now >= c.next_tx:
                    # A camera still fetching its first snapshot shouldn't
                    # forfeit a whole interval — retry it shortly instead.
                    c.next_tx = now + (args.interval if emit(c) else 1.0)

            if LIVE:
                render(cams, args.interval, gw_state)
                time.sleep(0.4)            # redraw faster than we transmit
            elif args.as_json:
                # One self-contained status object per second: the menu bar
                # app reads these and never needs to know how any of this works.
                print(json.dumps(status_dict(cams, args, port, gw_state)),
                      flush=True)
                time.sleep(1.0)
            else:
                time.sleep(0.25)
    except KeyboardInterrupt:
        pass
    finally:
        if LIVE:
            sys.stdout.write("\033[?25h\n")   # restore cursor
        if port:
            port.close()


if __name__ == "__main__":
    main()
