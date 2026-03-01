import Cocoa
import ApplicationServices
import AVFoundation

let logPath = "/tmp/dictate_app.log"

func log(_ msg: String) {
    let line = "\(Date()): \(msg)\n"
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        h.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
}

func sfSymbol(_ name: String) -> NSImage {
    let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        ?? NSImage(size: NSSize(width: 18, height: 18))
    img.isTemplate = true
    return img
}

// MARK: - Hotkey config

struct HotkeyConfig {
    enum Mode: String { case hold, toggle }

    var flags: CGEventFlags
    var mode: Mode

    static let flagOptions: [(label: String, flags: CGEventFlags)] = [
        ("Control (⌃)",          .maskControl),
        ("Option (⌥)",           .maskAlternate),
        ("Control + Option (⌃⌥)", CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)),
        ("Command + Option (⌘⌥)", CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue  | CGEventFlags.maskAlternate.rawValue)),
    ]

    static func load() -> HotkeyConfig {
        let defaults = UserDefaults.standard
        let rawFlags = defaults.object(forKey: "hotkeyFlags") as? NSNumber
        let flags = rawFlags.map { CGEventFlags(rawValue: $0.uint64Value) } ?? .maskControl
        let modeStr = defaults.string(forKey: "hotkeyMode") ?? Mode.hold.rawValue
        let mode = Mode(rawValue: modeStr) ?? .hold
        return HotkeyConfig(flags: flags, mode: mode)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(NSNumber(value: flags.rawValue), forKey: "hotkeyFlags")
        defaults.set(mode.rawValue, forKey: "hotkeyMode")
    }

    var displayName: String {
        var parts: [String] = []
        if flags.rawValue & CGEventFlags.maskControl.rawValue   != 0 { parts.append("⌃") }
        if flags.rawValue & CGEventFlags.maskAlternate.rawValue != 0 { parts.append("⌥") }
        if flags.rawValue & CGEventFlags.maskCommand.rawValue   != 0 { parts.append("⌘") }
        return parts.joined()
    }
}

// MARK: - Preferences window

class PreferencesWindow: NSObject {
    let window: NSWindow
    var onApply: ((HotkeyConfig) -> Void)?

    private let keyPop: NSPopUpButton
    private let modeSeg: NSSegmentedControl

    init(current: HotkeyConfig) {
        let w: CGFloat = 300
        let h: CGFloat = 130

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dictate Preferences"
        window.isReleasedWhenClosed = false
        window.center()

        // Key selector
        keyPop = NSPopUpButton(frame: .zero, pullsDown: false)
        for opt in HotkeyConfig.flagOptions { keyPop.addItem(withTitle: opt.label) }

        // Select current
        let currentIdx = HotkeyConfig.flagOptions.firstIndex { $0.flags.rawValue == current.flags.rawValue } ?? 0
        keyPop.selectItem(at: currentIdx)

        // Mode segmented control
        modeSeg = NSSegmentedControl(labels: ["Hold", "Toggle"], trackingMode: .selectOne, target: nil, action: nil)
        modeSeg.selectedSegment = current.mode == .hold ? 0 : 1

        super.init()

        // Layout
        let content = window.contentView!

        let keyLabel = NSTextField(labelWithString: "Modifier key:")
        let modeLabel = NSTextField(labelWithString: "Mode:")
        let applyBtn = NSButton(title: "Apply", target: self, action: #selector(apply))
        applyBtn.keyEquivalent = "\r"
        applyBtn.bezelStyle = .rounded

        for v in [keyLabel, keyPop, modeLabel, modeSeg, applyBtn] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        NSLayoutConstraint.activate([
            keyLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            keyLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),

            keyPop.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 8),
            keyPop.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            keyPop.centerYAnchor.constraint(equalTo: keyLabel.centerYAnchor),

            modeLabel.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            modeLabel.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 12),

            modeSeg.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 8),
            modeSeg.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),

            applyBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            applyBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
    }

    @objc private func apply() {
        let idx = keyPop.indexOfSelectedItem
        let flags = HotkeyConfig.flagOptions[idx].flags
        let mode: HotkeyConfig.Mode = modeSeg.selectedSegment == 0 ? .hold : .toggle
        let config = HotkeyConfig(flags: flags, mode: mode)
        config.save()
        onApply?(config)
        window.orderOut(nil)
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Waveform overlay

class WaveformView: NSView {
    static let barCount = 30
    var currentLevel: CGFloat = 0
    private let phases: [CGFloat] = (0..<barCount).map { _ in CGFloat.random(in: 0...1) }
    private var tick: CGFloat = 0

    func push(_ rms: CGFloat) {
        if rms > currentLevel {
            currentLevel = currentLevel * 0.3 + rms * 0.7
        } else {
            currentLevel = currentLevel * 0.85 + rms * 0.15
        }
        tick += 1
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height
        let padding: CGFloat = 12
        let drawW = w - padding * 2
        let barW = drawW / CGFloat(WaveformView.barCount)
        let gap: CGFloat = 2
        let minH: CGFloat = 3

        ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        for i in 0..<WaveformView.barCount {
            let center = CGFloat(WaveformView.barCount) / 2
            let dist = abs(CGFloat(i) - center) / center
            let envelope = 1.0 - dist * 0.5
            let wave = 0.6 + 0.4 * sin(tick * 0.15 + phases[i] * .pi * 2)
            let barH = max(minH, currentLevel * envelope * wave * (h - 12))
            let x = padding + CGFloat(i) * barW
            let y = (h - barH) / 2
            let rect = CGRect(x: x + gap / 2, y: y, width: barW - gap, height: barH)
            let path = CGPath(roundedRect: rect, cornerWidth: (barW - gap) / 2, cornerHeight: (barW - gap) / 2, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        }
    }
}

class WaveformPanel {
    let panel: NSPanel
    let waveformView: WaveformView
    private var timer: Timer?
    private var lastFileSize: UInt64 = 0
    private let rawPath = "/tmp/dictate_recording.raw"

    init() {
        let panelW: CGFloat = 160
        let panelH: CGFloat = 48

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        waveformView = WaveformView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        effect.addSubview(waveformView)

        panel.contentView = effect
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        let sx = screen.frame.midX - panel.frame.width / 2
        let sy = screen.visibleFrame.origin.y + 80
        panel.setFrameOrigin(NSPoint(x: sx, y: sy))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        startFileMonitor()
    }

    func hide() {
        stopFileMonitor()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            self.panel.orderOut(nil)
            self.waveformView.currentLevel = 0
        })
    }

    private func startFileMonitor() {
        lastFileSize = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.readLatestSamples()
        }
    }

    private func stopFileMonitor() {
        timer?.invalidate()
        timer = nil
    }

    private func readLatestSamples() {
        guard let fh = FileHandle(forReadingAtPath: rawPath) else {
            waveformView.push(0)
            return
        }
        defer { fh.closeFile() }

        let fileSize = fh.seekToEndOfFile()
        let chunkSize: UInt64 = 3200
        if fileSize < chunkSize { return }

        fh.seek(toFileOffset: fileSize - chunkSize)
        let data = fh.readData(ofLength: Int(chunkSize))
        lastFileSize = fileSize

        // PCM 16-bit signed LE → RMS
        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return }

        var sum: Float = 0
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let s = Float(samples[i]) / 32768.0
                sum += s * s
            }
        }
        let rms = sqrtf(sum / Float(sampleCount))
        let db = 20 * log10f(max(rms, 1e-7))
        // -85dB (silence) → 0, -55dB (speech) → 1
        let normalized = CGFloat(max(0, (db + 85) / 30))
        let scaled = min(normalized, 1.0)

        waveformView.push(scaled)
    }
}

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var isRecording = false
    var eventTap: CFMachPort?
    var waveformPanel: WaveformPanel?
    var hotkeyConfig: HotkeyConfig = HotkeyConfig.load()
    var prevModifierActive = false
    var prefsWindow: PreferencesWindow?

    let script: String = Bundle.main.path(forResource: "dictate", ofType: "sh")
        ?? Bundle.main.bundlePath + "/../dictate.sh"  // fallback pro dev

    func applicationDidFinishLaunching(_ n: Notification) {
        log("App launched, home=\(NSHomeDirectory())")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = sfSymbol("mic")
        updateTooltip()

        let menu = NSMenu()
        menu.autoenablesItems = false
        let prefsItem = NSMenuItem(title: "Preferences\u{2026}", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        prefsItem.isEnabled = true
        menu.addItem(prefsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        statusItem.menu = menu

        // Request microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            log("Microphone: authorized")
        case .notDetermined:
            log("Microphone: requesting...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                log("Microphone: \(granted ? "granted" : "denied")")
            }
        case .denied, .restricted:
            log("Microphone: denied/restricted")
        @unknown default:
            log("Microphone: unknown status")
        }

        let trusted = AXIsProcessTrusted()
        log("AXIsProcessTrusted=\(trusted)")

        if !trusted {
            log("Requesting accessibility...")
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            )
            statusItem.button?.image = sfSymbol("exclamationmark.triangle")
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                if AXIsProcessTrusted() {
                    t.invalidate()
                    log("Accessibility GRANTED")
                    self.createTap()
                }
            }
            return
        }

        createTap()
    }

    @objc func openPreferences() {
        if prefsWindow == nil {
            prefsWindow = PreferencesWindow(current: hotkeyConfig)
            prefsWindow?.onApply = { [weak self] config in
                guard let self else { return }
                self.hotkeyConfig = config
                self.prevModifierActive = false
                self.updateTooltip()
                log("Config updated: \(config.displayName) mode=\(config.mode.rawValue)")
            }
        }
        prefsWindow?.show()
    }

    func createTap() {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCB,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("tapCreate FAILED")
            statusItem.button?.image = sfSymbol("xmark.circle")
            return
        }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        statusItem.button?.image = sfSymbol("mic")
        log("Event tap OK")
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = eventTap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passRetained(event)
        }

        let modifierActive = (event.flags.rawValue & hotkeyConfig.flags.rawValue) == hotkeyConfig.flags.rawValue

        switch hotkeyConfig.mode {
        case .hold:
            if modifierActive && !isRecording {
                startRecording()
            } else if !modifierActive && isRecording {
                stopRecording()
            }
        case .toggle:
            if modifierActive && !prevModifierActive {
                if isRecording { stopRecording() } else { startRecording() }
            }
        }

        prevModifierActive = modifierActive
        return Unmanaged.passRetained(event)
    }

    private func startRecording() {
        log("START")
        isRecording = true
        DispatchQueue.main.async {
            self.statusItem.button?.image = sfSymbol("mic.fill")
            if self.waveformPanel == nil { self.waveformPanel = WaveformPanel() }
            self.waveformPanel?.show()
        }
        DispatchQueue.global().async { self.run("start") }
    }

    private func stopRecording() {
        log("STOP")
        isRecording = false
        DispatchQueue.main.async {
            self.statusItem.button?.image = sfSymbol("mic")
            self.waveformPanel?.hide()
        }
        DispatchQueue.global().async { self.run("stop") }
    }

    private func updateTooltip() {
        statusItem.button?.toolTip = "Dictate — \(hotkeyConfig.displayName)"
    }

    func run(_ cmd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script, cmd]
        try? p.run()
        p.waitUntilExit()
    }
}

let tapCB: CGEventTapCallBack = { _, type, event, refcon in
    guard let r = refcon else { return Unmanaged.passRetained(event) }
    return Unmanaged<AppDelegate>.fromOpaque(r).takeUnretainedValue().handle(type: type, event: event)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
