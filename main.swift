import AppKit
import ApplicationServices
import IOKit.hid

// Off unless asked for: defaults write local.notchmic log -bool YES
let logging = UserDefaults.standard.bool(forKey: "log")
func trace(_ m: String) {
    guard logging else { return }
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
    let line = "\(f.string(from: Date())) \(m)\n"
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/NotchMic.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

// A click strip just right of the notch that toggles Dictation in the frontmost app.
final class HotZone: NSView {
    var hovering = false { didSet { needsDisplay = true } }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func draw(_ r: NSRect) {
        guard let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictate") else { return }
        let s: CGFloat = 13
        img.isTemplate = true
        let rect = NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
        NSColor.white.withAlphaComponent(hovering ? 1 : 0.35).set()
        img.draw(in: rect)
        rect.fill(using: .sourceAtop)
    }
    // The panel is never key, so without this the first click is swallowed.
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {}   // act on release: a key press sent mid-click gets lost
    override func mouseUp(with e: NSEvent) { toggleDictation() }
    override func rightMouseUp(with e: NSEvent) {
        let m = NSMenu()
        m.addItem(withTitle: "Quit NotchMic", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(m, with: e, for: self)
    }
}

func menuChildren(_ el: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v)
    return (v as? [AXUIElement]) ?? []
}
func title(_ el: AXUIElement) -> String {
    var v: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &v)
    return (v as? String) ?? ""
}

// A second Start Dictation press does not stop it, so "off" sends Escape, which ends Dictation.
// shortcut: the on/off state is NotchMic's own guess; if Dictation stops by itself, the next double tap sends a stray Escape. Upgrade by reading Dictation's real state if a signal is found.
var dictating = false
func toggleDictation() {
    if dictating {
        dictating = false
        trace("off: sending Escape")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap) }
        }
    } else if startDictation() {
        dictating = true
    }
}

@discardableResult
func startDictation() -> Bool {
    trace("click")
    guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else { trace("not trusted (Accessibility off)"); return false }
    guard let app = NSWorkspace.shared.frontmostApplication else { trace("no frontmost app"); return false }
    trace("frontmost: \(app.localizedName ?? "?")")
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    var bar: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(ax, kAXMenuBarAttribute as CFString, &bar)
    guard err == .success else { trace("menubar error \(err.rawValue)"); NSSound.beep(); return false }
    // Search every top menu (Edit is usual) for "Start Dictation…"; a missing item means Dictation is off or the app has none.
    for top in menuChildren(bar as! AXUIElement) {
        for menu in menuChildren(top) {
            for item in menuChildren(menu) where title(item).hasPrefix("Start Dictation") || title(item).hasPrefix("Stop Dictation") {
                let r = AXUIElementPerformAction(item, kAXPressAction as CFString)
                trace("pressed '\(title(item))' in \(title(top)) -> \(r.rawValue)")
                return r == .success
            }
        }
    }
    trace("no Start Dictation item; menus: \(menuChildren(bar as! AXUIElement).map(title))")
    NSSound.beep()
    return false
}


// Double tap on the laptop body, sensed by the built-in accelerometer (vendor page 0xFF00, usage 3).
final class KnockSensor {
    // Tunable without a rebuild (a rebuild resets Accessibility): defaults write local.notchmic <key> <value>, then relaunch.
    let d = UserDefaults.standard
    lazy var threshold = d.object(forKey: "threshold") as? Double ?? 0.02   // g; resting jitter peaks near 0.002 g
    lazy var ring = d.object(forKey: "ring") as? Double ?? 0.1              // s; bumps this close to the last one are the same tap ringing
    lazy var gap = (d.object(forKey: "gapMin") as? Double ?? 0.12)...(d.object(forKey: "gapMax") as? Double ?? 0.6)
    lazy var taps = d.object(forKey: "taps") as? Int ?? 2                   // 1 = single tap, 2 = double tap
    lazy var cooldown = d.object(forKey: "cooldown") as? Double ?? 1.5      // s after a trigger when taps are ignored
    lazy var quiet = d.object(forKey: "quiet") as? Double ?? 0.3            // s; bumps this close to a key or click are typing
    lazy var sideways = d.object(forKey: "sideways") as? Double ?? 1.0      // a tap's sideways jolt must stay below this times its vertical jolt
    let settle = 0.15                                                       // s to wait so a late key event can still veto the bump
    var lastBump = 0.0, lastFire = 0.0
    var avg: (Double, Double, Double)?
    var lastKnock = 0.0, lastInput = 0.0
    var spikePeak = 0.0, spikeVert = 0.0, spikeSide = 0.0
    var manager: IOHIDManager!
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    func start() {
        var it: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &it)
        var s = IOIteratorNext(it)
        while s != 0 {
            for (k, v) in [("SensorPropertyReportingState", 1), ("SensorPropertyPowerState", 1), ("ReportInterval", 1000)] {
                IORegistryEntrySetCFProperty(s, k as CFString, v as CFNumber)
            }
            IOObjectRelease(s); s = IOIteratorNext(it)
        }
        IOObjectRelease(it)
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 3] as CFDictionary)
        IOHIDManagerOpen(manager, 0)
        let devs = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        trace("knock sensor: \(devs.count) device(s), threshold \(threshold) g, sideways \(sideways), ring \(ring) s, taps \(taps), gap \(gap)")
        let me = Unmanaged.passUnretained(self).toOpaque()
        for d in devs {
            IOHIDDeviceRegisterInputReportCallback(d, buf, 64, { ctx, _, _, _, _, p, len in
                guard len >= 18 else { return }
                Unmanaged<KnockSensor>.fromOpaque(ctx!).takeUnretainedValue().sample(p)
            }, me)
        }
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        watchInput()
        // Key events reach a global monitor only if Accessibility was on when it was installed; re-arm once it is granted.
        if !AXIsProcessTrusted() {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
                guard AXIsProcessTrusted() else { return }
                t.invalidate(); self.watchInput(); trace("accessibility granted, typing filter re-armed")
            }
        }
    }

    // Typing and clicking shake the laptop too; bumps next to them are ignored. Which event types count: defaults key "veto" (array of NSEvent type numbers).
    lazy var veto = Set((d.array(forKey: "veto") as? [Int]) ?? [10, 11, 12, 1, 2, 3, 25, 22, 34])
    var monitor: Any?
    var lastInputWhat = ""
    func watchInput() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .scrollWheel, .pressure]) { e in
            guard self.veto.contains(Int(e.type.rawValue)) else { return }
            self.lastInput = ProcessInfo.processInfo.systemUptime
            self.lastInputWhat = "event type \(e.type.rawValue)"   // never which key: this is not a keylogger
        }
    }

    func sample(_ p: UnsafeMutablePointer<UInt8>) {
        func g(_ o: Int) -> Double {
            Double(Int32(bitPattern: UInt32(p[o]) | UInt32(p[o+1]) << 8 | UInt32(p[o+2]) << 16 | UInt32(p[o+3]) << 24)) / 65536
        }
        let v = (g(6), g(10), g(14))
        guard var a = avg else { avg = v; return }
        let jolt = (v.0-a.0, v.1-a.1, v.2-a.2)
        let dist = (jolt.0*jolt.0 + jolt.1*jolt.1 + jolt.2*jolt.2).squareRoot()
        // The running average is gravity, so it marks "down" even on a tilted laptop: split the jolt into vertical and sideways.
        let gl = max((a.0*a.0 + a.1*a.1 + a.2*a.2).squareRoot(), 1e-6)
        let vert = abs((jolt.0*a.0 + jolt.1*a.1 + jolt.2*a.2) / gl)
        let side = max(dist*dist - vert*vert, 0).squareRoot()
        a = (a.0*0.98 + v.0*0.02, a.1*0.98 + v.1*0.02, a.2*0.98 + v.2*0.02); avg = a
        guard dist > threshold else { return }
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastBump = now }
        if now - lastBump < ring {   // same bump still ringing
            spikePeak = max(spikePeak, dist); spikeVert = max(spikeVert, vert); spikeSide = max(spikeSide, side)
            return
        }
        spikePeak = dist; spikeVert = vert; spikeSide = side
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { self.knock(at: now) }
    }

    func knock(at t: Double) {
        let peak = String(format: "%.3f g (vertical %.3f, sideways %.3f)", spikePeak, spikeVert, spikeSide)
        if abs(lastInput - t) < quiet { lastKnock = 0; return trace("bump \(peak) ignored (input: \(lastInputWhat))") }
        // Only a tap down on the body counts; sliding or bumping the laptop sideways does not.
        if spikeVert < threshold || spikeSide > sideways * spikeVert { lastKnock = 0; return trace("bump \(peak) ignored (sideways)") }
        if t - lastFire < cooldown { return trace("tap \(peak) ignored (cooldown)") }
        trace("tap \(peak)")
        if taps == 1 || gap.contains(t - lastKnock) {
            trace("taps -> toggle dictation"); lastKnock = 0; lastFire = t
            toggleDictation()
        } else { lastKnock = t }
    }
}
let knocks = KnockSensor()

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    func applicationDidFinishLaunching(_ n: Notification) {
        place()
        knocks.start()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in self.place() }
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }
    func place() {
        panel?.close()
        guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopRightArea != nil }),
              let right = screen.auxiliaryTopRightArea else { return }  // no notched screen attached
        let f = screen.frame
        let w: CGFloat = 34
        let rect = NSRect(x: f.minX + right.minX, y: f.maxY - right.height, width: w, height: right.height)
        panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar + 1
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = HotZone(frame: NSRect(origin: .zero, size: rect.size))
        panel.orderFrontRegardless()
        trace("launched, strip at \(rect), accessibility=\(AXIsProcessTrusted())")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
