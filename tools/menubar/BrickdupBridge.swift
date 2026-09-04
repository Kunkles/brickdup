// Brickdup camera bridge — macOS menu bar app.
//
// A thin native shell around tools/camera_bridge.py. The Python side does all
// the real work (mDNS discovery, camera polling, gateway probe, pacing,
// airtime budget) and emits one JSON status line per second with --json; this
// app spawns it, parses those lines, and renders them in the menu bar. Keeping
// one implementation means the terminal and the menu bar can never disagree.
//
// Build:  tools/menubar/build.sh     ->  tools/menubar/BrickdupBridge.app

import AppKit
import Foundation

let bridgeScript = ProcessInfo.processInfo.environment["BRICKDUP_BRIDGE"]
    ?? "\(NSHomeDirectory())/Documents/brickwatch/tools/camera_bridge.py"

struct Camera {
    var label = "?", host = "", link = ""
    var serial: Int?
    var volts: Double?
    var pct: Int?
    var warn: Int?
    var age: Double?
    var sent = 0
}

final class Controller: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var task: Process?
    var buffer = Data()

    var cameras: [Camera] = []
    var gatewayPort: String?
    var gatewayOK = false
    var airtime = ""
    var running = false
    var lastError: String?
    var wantRunning = false      // user intent, vs. whether it happens to be up
    var retryTimer: Timer?
    var retryIn = 0

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.autoenablesItems = false
        item.menu = menu
        redraw()
        start()
    }

    // MARK: - bridge process

    func start() {
        wantRunning = true
        retryTimer?.invalidate(); retryTimer = nil; retryIn = 0
        guard task == nil else { return }
        guard FileManager.default.fileExists(atPath: bridgeScript) else {
            lastError = "bridge not found at \(bridgeScript)"
            redraw(); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // --serial with no value auto-detects the single USB-serial port.
        p.arguments = ["python3", bridgeScript, "--json", "--serial"]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(d) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            // Surface only the lines that mean something went wrong.
            for line in s.split(separator: "\n") where
                line.contains("WARNING") || line.contains("could not") ||
                line.contains("no USB-serial") || line.contains("Resource busy") {
                DispatchQueue.main.async {
                    self?.lastError = String(line).replacingOccurrences(of: "# ", with: "")
                    self?.redraw()
                }
            }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.task = nil
                self?.running = false
                // Exiting almost immediately means it never got going — most
                // often another bridge (or the IDE's serial monitor) already
                // holds the port, since only one process can.
                if proc.terminationStatus != 0 && self?.lastError == nil {
                    self?.lastError = "bridge exited — is another copy running, "
                                    + "or the IDE's Serial Monitor open?"
                }
                self?.scheduleRetry()
                self?.redraw()
            }
        }
        do {
            try p.run()
            task = p
            running = true
            lastError = nil
        } catch {
            lastError = "could not start bridge: \(error.localizedDescription)"
        }
        redraw()
    }

    func stop() {
        wantRunning = false
        retryTimer?.invalidate(); retryTimer = nil; retryIn = 0
        task?.terminate()
        task = nil
        running = false
        cameras = []
        gatewayOK = false
        lastError = nil
        redraw()
    }

    /// The gateway board comes and goes on USB, so a failed start is normal
    /// rather than fatal. Keep trying quietly until it is back, unless the
    /// user actually asked us to stop.
    func scheduleRetry() {
        guard wantRunning, retryTimer == nil else { return }
        retryIn = 10
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.retryIn -= 1
            if self.retryIn <= 0 {
                t.invalidate()
                self.retryTimer = nil
                self.start()
            } else {
                self.redraw()
            }
        }
    }

    func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line),
                  let root = obj as? [String: Any] else { continue }
            apply(root)
        }
        redraw()
    }

    func apply(_ root: [String: Any]) {
        if let gw = root["gateway"] as? [String: Any] {
            gatewayPort = gw["port"] as? String
            gatewayOK = (gw["ok"] as? Bool) ?? false
        }
        airtime = (root["airtime"] as? String) ?? ""
        cameras = ((root["cameras"] as? [[String: Any]]) ?? []).map { c in
            var cam = Camera()
            cam.label  = (c["label"] as? String) ?? "?"
            cam.host   = (c["host"] as? String) ?? ""
            cam.link   = (c["link"] as? String) ?? ""
            cam.serial = c["serial"] as? Int
            cam.volts  = c["volts"] as? Double
            cam.pct    = c["pct"] as? Int
            cam.warn   = c["warn"] as? Int
            cam.age    = c["age"] as? Double
            cam.sent   = (c["sent"] as? Int) ?? 0
            return cam
        }
    }

    // MARK: - UI

    func redraw() {
        // The glanceable number is the LOWEST camera battery — that is the one
        // that decides when someone has to go swap something.
        let live = cameras.filter { $0.link == "on_ac" || $0.link == "battery" }
        let lowest = live.compactMap { $0.pct }.min()

        // An SF Symbol reads as an app icon at a glance; bare text glyphs get
        // lost in a crowded menu bar. State is carried by BOTH the symbol and
        // the number, so it survives being squeezed.
        let symbol: String, label: String
        if !running {
            symbol = "antenna.radiowaves.left.and.right.slash"; label = ""
        } else if !gatewayOK {
            symbol = "exclamationmark.triangle.fill"; label = ""
        } else if let p = lowest {
            symbol = "antenna.radiowaves.left.and.right"; label = " \(p)%"
        } else {
            symbol = "antenna.radiowaves.left.and.right"; label = " –"
        }
        if let btn = item.button {
            let img = NSImage(systemSymbolName: symbol,
                              accessibilityDescription: "Brickdup bridge")
            img?.isTemplate = true
            btn.image = img
            btn.imagePosition = .imageLeading
            btn.title = label
            // Never leave the item with nothing to draw — an empty button is
            // invisible and looks like the app failed to launch.
            if img == nil && label.isEmpty { btn.title = "BD" }
            if let p = lowest, let minWarn = live.compactMap({ $0.warn }).min(),
               p <= minWarn {
                btn.contentTintColor = .systemRed
            } else if !gatewayOK && running {
                btn.contentTintColor = .systemOrange
            } else {
                btn.contentTintColor = nil
            }
        }

        menu.removeAllItems()

        if let e = lastError {
            add("⚠ \(e)", enabled: false)
            menu.addItem(.separator())
        }

        if !running && wantRunning {
            add(retryIn > 0 ? "Waiting for gateway… retrying in \(retryIn)s"
                            : "Starting…", enabled: false)
        } else if !running {
            add("Bridge stopped", enabled: false)
        } else if gatewayOK {
            add("Gateway: \(gatewayPort ?? "?")", enabled: false)
        } else {
            add("Gateway: NOT CONNECTED — nothing is transmitting", enabled: false)
        }
        menu.addItem(.separator())

        if cameras.isEmpty {
            add(running ? "Searching for cameras…" : "—", enabled: false)
        }
        for c in cameras {
            let pct = c.pct.map { "\($0)%" } ?? "—"
            let v = c.volts.map { String(format: "%.2fV", $0) } ?? ""
            let state: String
            switch c.link {
            case "on_ac":     state = "on AC"
            case "battery":   state = "on battery"
            case "stale":     state = "STALE"
            case "offline":   state = "OFFLINE"
            case "duplicate": state = "duplicate"
            default:          state = c.link
            }
            let row = String(format: "%@   %@   %@   %@", c.label, pct, state, v)
            let mi = NSMenuItem(title: row, action: nil, keyEquivalent: "")
            mi.isEnabled = false
            // Flag anything at or below the camera's own warning threshold.
            if let p = c.pct, let w = c.warn, p <= w {
                mi.attributedTitle = NSAttributedString(
                    string: row,
                    attributes: [.foregroundColor: NSColor.systemRed])
            } else if c.link == "offline" || c.link == "stale" {
                mi.attributedTitle = NSAttributedString(
                    string: row,
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor])
            }
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        if !airtime.isEmpty { add(airtime, enabled: false) }
        menu.addItem(.separator())
        add(wantRunning ? "Stop bridge" : "Start bridge",
            action: wantRunning ? #selector(doStop) : #selector(doStart))
        add("Quit", action: #selector(doQuit), key: "q")
    }

    func add(_ title: String, action: Selector? = nil, key: String = "",
             enabled: Bool = true) {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        mi.isEnabled = enabled && action != nil
        menu.addItem(mi)
    }

    @objc func doStart() { start() }
    @objc func doStop()  { stop() }
    @objc func doQuit()  { stop(); NSApp.terminate(nil) }
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.accessory)   // menu bar only, no dock icon
app.run()
