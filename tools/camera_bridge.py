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

Usage:
    python3 camera_bridge.py                          # discover + print
    python3 camera_bridge.py --serial /dev/tty.usbserial-0001
    python3 camera_bridge.py --cameras 10.2.2.200,10.2.2.201   # skip discovery
    python3 camera_bridge.py --no-scan                # mDNS only, never sweep
"""

import argparse
import json
import math
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
    "SystemCameraSerial", "CameraIndexDual",
)


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
        try:
            found.append(socket.gethostbyname(host))  # prefer the resolved IP
        except OSError:
            found.append(host)                        # let urllib try the name
    if found:
        return sorted(set(found))
    if allow_sweep:
        print("# mDNS found nothing — sweeping the local subnet",
              file=sys.stderr, flush=True)
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
                print(f"# {self.host} connected: serial="
                      f"{ident.get('SystemCameraSerial')} "
                      f"cam={ident.get('CameraIndexDual')}",
                      file=sys.stderr, flush=True)
                uid = d.get("id", 0)
                while True:
                    r = self._get(f"/update.cgi?id={uid}", timeout=POLL_TIMEOUT)
                    uid = r.get("id", uid)
                    self._absorb(r.get("variables", {}))
            except (urllib.error.URLError, OSError, json.JSONDecodeError,
                    TimeoutError) as e:
                if self.online:
                    print(f"# {self.host} lost ({e}); reconnecting",
                          file=sys.stderr, flush=True)
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
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cameras", default=None,
                    help="comma-separated camera IPs/hostnames; skips discovery")
    ap.add_argument("--interval", type=float, default=TX_INTERVAL,
                    help="seconds between packets PER CAMERA (default 30; see the "
                         "airtime note at the top before lowering it)")
    ap.add_argument("--serial", metavar="PORT",
                    help="write packets to this serial port (the LoRa gateway) "
                         "as well as stdout")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--no-scan", action="store_true",
                    help="never sweep the subnet; rely on mDNS alone")
    args = ap.parse_args()

    port = None
    if args.serial:
        try:
            import serial          # pyserial
        except ImportError:
            sys.exit("--serial needs pyserial:  pip3 install pyserial")
        port = serial.Serial(args.serial, args.baud, timeout=1)
        time.sleep(2)              # ESP32 resets when the port opens
        print(f"# gateway on {args.serial} @ {args.baud}", file=sys.stderr)

    fixed = None
    if args.cameras:
        fixed = [h.strip() for h in args.cameras.split(",") if h.strip()]

    cams = {}                      # host -> Camera thread

    def sync_cameras():
        hosts = fixed if fixed is not None else discover(not args.no_scan)
        for h in hosts:
            if h not in cams:
                print(f"# discovered {h}", file=sys.stderr, flush=True)
                c = Camera(h)
                c.start()
                cams[h] = c
        if not cams:
            print("# no cameras found yet", file=sys.stderr, flush=True)
        else:
            print(f"# airtime: {airtime_report(len(cams), args.interval)}",
                  file=sys.stderr, flush=True)

    sync_cameras()
    time.sleep(2)                  # let the first snapshots land
    last_discovery = time.monotonic()

    try:
        while True:
            # cameras powered up mid-day get picked up here; existing threads
            # reconnect on their own, so this only ever ADDS
            if fixed is None and time.monotonic() - last_discovery > DISCOVER_EVERY:
                sync_cameras()
                last_discovery = time.monotonic()

            # STAGGER: give each camera its own slot in the interval rather
            # than emitting them back to back. N cameras bursting together
            # would hold the channel for N x ~288 ms straight and stomp on any
            # node transmitting in that window; spreading them keeps the
            # gateway's occupancy in short, widely separated bursts.
            batch = list(cams.items())
            slot = args.interval / max(1, len(batch))
            if not batch:
                time.sleep(args.interval)
                continue
            for host, c in batch:
                line = packet_for(c)
                if line is not None:
                    print(line, flush=True)
                    if port:
                        port.write((line + "\n").encode())
                time.sleep(slot)   # sleep even when skipped, to keep cadence
    except KeyboardInterrupt:
        pass
    finally:
        if port:
            port.close()


if __name__ == "__main__":
    main()
