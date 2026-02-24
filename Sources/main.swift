import Cocoa
import ServiceManagement

// MARK: - Data Model

struct UsageData {
    let fiveHourPct: Double
    let sevenDayPct: Double
    let resetsAt: Date?
    let sevenDayResetsAt: Date?
    let extraUsageCents: Double
}

// MARK: - Utilities

func elapsedPct(resetsAt: Date?, windowHours: Double) -> Double? {
    guard let resetTime = resetsAt else { return nil }
    let windowSec = windowHours * 3600
    let startTime = resetTime.addingTimeInterval(-windowSec)
    let now = Date()
    guard now >= startTime, now <= resetTime else { return nil }
    return ((now.timeIntervalSince(startTime)) / windowSec) * 100
}

func driftPct(usage: Double, resetsAt: Date?, windowHours: Double) -> Double? {
    guard let elapsed = elapsedPct(resetsAt: resetsAt, windowHours: windowHours) else { return nil }
    return (usage - elapsed).rounded()
}

func driftNSColor(_ drift: Double) -> NSColor {
    if drift > 30 { return .systemRed }
    if drift > 10 { return .systemOrange }
    if drift < -10 { return .systemGreen }
    return NSColor.secondaryLabelColor
}

func labelColor(pct: Double, drift: Double?, full: Bool) -> NSColor {
    if full { return .systemRed }
    if let d = drift {
        if d > 30 { return .systemRed }
        if d > 10 { return .systemOrange }
    }
    return .labelColor
}

func formatRelativeTime(_ date: Date) -> String {
    let diffMs = date.timeIntervalSinceNow * 1000
    if diffMs <= 0 { return "now" }
    let diffMin = Int(diffMs / 60000)
    if diffMin < 60 { return "\(diffMin)min" }
    let totalH = diffMin / 60
    if totalH >= 24 {
        let d = totalH / 24
        let rh = totalH % 24
        return rh > 0 ? "\(d)d\(rh)h" : "\(d)d"
    }
    let m = diffMin % 60
    return m > 0 ? "\(totalH)h\(String(format: "%02d", m))" : "\(totalH)h"
}

func formatDrift(_ drift: Double) -> String {
    drift >= 0 ? "+\(Int(drift))" : "\(Int(drift))"
}

// MARK: - OAuth Token

func readOAuthToken() -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do { try task.run() } catch { return nil }
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if let jsonData = raw.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
       let oauth = json["claudeAiOauth"] as? [String: Any],
       let token = oauth["accessToken"] as? String {
        return token
    }
    return raw.isEmpty ? nil : raw
}

// MARK: - API

func fetchUsageData(token: String) async -> UsageData? {
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

    guard let (data, response) = try? await URLSession.shared.data(for: request),
          let http = response as? HTTPURLResponse, http.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          json["five_hour"] != nil else {
        return nil
    }

    let fiveHour = json["five_hour"] as? [String: Any]
    let sevenDay = json["seven_day"] as? [String: Any]
    let extra = json["extra_usage"] as? [String: Any]

    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fmt2 = ISO8601DateFormatter()
    fmt2.formatOptions = [.withInternetDateTime]

    func parseDate(_ str: String?) -> Date? {
        guard let s = str else { return nil }
        return fmt.date(from: s) ?? fmt2.date(from: s)
    }

    return UsageData(
        fiveHourPct: ((fiveHour?["utilization"] as? Double) ?? 0).rounded(),
        sevenDayPct: ((sevenDay?["utilization"] as? Double) ?? 0).rounded(),
        resetsAt: parseDate(fiveHour?["resets_at"] as? String),
        sevenDayResetsAt: parseDate(sevenDay?["resets_at"] as? String),
        extraUsageCents: (extra?["used_credits"] as? Double) ?? 0
    )
}

// MARK: - Drawing Helpers

func drawTrackInCtx(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, r: CGFloat, sw: CGFloat, full: Bool) {
    let color: NSColor = full ? .systemRed : .gray.withAlphaComponent(0.2)
    ctx.setLineWidth(sw)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color.cgColor)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
}

func drawRingInCtx(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, r: CGFloat, sw: CGFloat,
                    pct: Double, elapsed: Double?, drift: Double?) {
    let startAngle = -CGFloat.pi / 2
    let usagePct = min(pct, 100)
    ctx.setLineWidth(sw)
    ctx.setLineCap(.round)

    if let elapsed = elapsed, let drift = drift {
        let underPace = usagePct < elapsed
        let basePct = underPace ? usagePct : min(usagePct, elapsed)
        let overPct = underPace ? 0 : max(0, usagePct - elapsed)

        if basePct > 0 {
            let baseColor: NSColor = underPace ? .systemGreen : .secondaryLabelColor.withAlphaComponent(0.5)
            let sweep = CGFloat(basePct / 100) * 2 * .pi
            ctx.setStrokeColor(baseColor.cgColor)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                       startAngle: startAngle, endAngle: startAngle + sweep, clockwise: false)
            ctx.strokePath()
        }
        if overPct > 0 {
            let baseSweep = CGFloat(basePct / 100) * 2 * .pi
            let overSweep = CGFloat(overPct / 100) * 2 * .pi
            ctx.setStrokeColor(driftNSColor(drift).cgColor)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                       startAngle: startAngle + baseSweep,
                       endAngle: startAngle + baseSweep + overSweep, clockwise: false)
            ctx.strokePath()
        }
        // Tick mark
        let tickAngle = startAngle + CGFloat(elapsed / 100) * 2 * .pi
        let tickLen = sw * 0.7
        let t1 = CGPoint(x: cx + cos(tickAngle) * (r - tickLen), y: cy + sin(tickAngle) * (r - tickLen))
        let t2 = CGPoint(x: cx + cos(tickAngle) * (r + tickLen), y: cy + sin(tickAngle) * (r + tickLen))
        ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(max(sw * 0.4, 1.2))
        ctx.move(to: t1)
        ctx.addLine(to: t2)
        ctx.strokePath()
    } else if usagePct > 0 {
        let sweep = CGFloat(usagePct / 100) * 2 * .pi
        ctx.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.5).cgColor)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                   startAngle: startAngle, endAngle: startAngle + sweep, clockwise: false)
        ctx.strokePath()
    }
}

func drawCenterLabel(cx: CGFloat, cy: CGFloat, text: String, fontSize: CGFloat, color: NSColor) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let textSize = (text as NSString).size(withAttributes: attrs)
    let textRect = NSRect(x: cx - textSize.width / 2, y: cy - textSize.height / 2,
                          width: textSize.width, height: textSize.height)
    (text as NSString).draw(in: textRect, withAttributes: attrs)
}

// MARK: - Menu Bar Icon

func renderMenuBarIcon(usage: UsageData?, extraDelta: Double = 0) -> NSImage {
    let h: CGFloat = 24
    let r: CGFloat = 10.0
    let sw: CGFloat = 3.5
    let gap: CGFloat = 4
    let circleW = (r + sw / 2) * 2

    let full5h = (usage?.fiveHourPct ?? 0) >= 100
    let full7d = (usage?.sevenDayPct ?? 0) >= 100
    let anyFull = full5h || full7d

    var extraLabelW: CGFloat = 0
    var extraText = ""
    if anyFull {
        extraText = "+$\(String(format: "%.2f", extraDelta / 100))"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        extraLabelW = (extraText as NSString).size(withAttributes: attrs).width + 4
    }

    let w = circleW * 2 + gap + extraLabelW
    let cx1 = r + sw / 2
    let cx2 = circleW + gap + r + sw / 2
    let cy = h / 2

    let image = NSImage(size: NSSize(width: w, height: h), flipped: true) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

        drawTrackInCtx(ctx, cx: cx1, cy: cy, r: r, sw: sw, full: full5h)
        drawTrackInCtx(ctx, cx: cx2, cy: cy, r: r, sw: sw, full: full7d)

        guard let u = usage else { return true }

        let e5h = elapsedPct(resetsAt: u.resetsAt, windowHours: 5)
        let e7d = elapsedPct(resetsAt: u.sevenDayResetsAt, windowHours: 168)
        let d5h = driftPct(usage: u.fiveHourPct, resetsAt: u.resetsAt, windowHours: 5)
        let d7d = driftPct(usage: u.sevenDayPct, resetsAt: u.sevenDayResetsAt, windowHours: 168)

        drawRingInCtx(ctx, cx: cx1, cy: cy, r: r, sw: sw, pct: u.fiveHourPct, elapsed: e5h, drift: d5h)
        drawRingInCtx(ctx, cx: cx2, cy: cy, r: r, sw: sw, pct: u.sevenDayPct, elapsed: e7d, drift: d7d)

        if !full5h {
            let lbl5h = "\(Int(u.fiveHourPct.rounded()))"
            drawCenterLabel(cx: cx1, cy: cy, text: lbl5h, fontSize: 8.5, color: labelColor(pct: u.fiveHourPct, drift: d5h, full: false))
        }
        if !full7d {
            let lbl7d = "\(Int(u.sevenDayPct.rounded()))"
            drawCenterLabel(cx: cx2, cy: cy, text: lbl7d, fontSize: 8.5, color: labelColor(pct: u.sevenDayPct, drift: d7d, full: false))
        }

        if anyFull {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.systemRed]
            let textSize = (extraText as NSString).size(withAttributes: attrs)
            let x = circleW * 2 + gap + 2
            let textRect = NSRect(x: x, y: cy - textSize.height / 2, width: textSize.width, height: textSize.height)
            (extraText as NSString).draw(in: textRect, withAttributes: attrs)
        }

        return true
    }
    image.isTemplate = false
    return image
}

// MARK: - Popover Gauge

func renderPopoverGauge(pct: Double, elapsed: Double?, drift: Double?, full: Bool) -> NSImage {
    let size: CGFloat = 64
    let r: CGFloat = 25
    let sw: CGFloat = 6
    let cx = size / 2
    let cy = size / 2

    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        drawTrackInCtx(ctx, cx: cx, cy: cy, r: r, sw: sw, full: full)
        drawRingInCtx(ctx, cx: cx, cy: cy, r: r, sw: sw, pct: pct, elapsed: elapsed, drift: drift)
        if !full {
            let label = "\(Int(pct.rounded()))"
            drawCenterLabel(cx: cx, cy: cy, text: label, fontSize: 18, color: labelColor(pct: pct, drift: drift, full: false))
        }
        return true
    }
    image.isTemplate = false
    return image
}

// MARK: - Popover View Controller

class PopoverViewController: NSViewController {
    private let gauge5hView = NSImageView()
    private let gauge7dView = NSImageView()
    private let detail5h = NSTextField(labelWithString: "--")
    private let detail7d = NSTextField(labelWithString: "--")
    private let extraLabel = NSTextField(labelWithString: "")
    private var loginCheckbox: NSButton?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?

    override func loadView() {
        let gaugeSize: CGFloat = 64

        for gv in [gauge5hView, gauge7dView] {
            gv.imageScaling = .scaleNone
            gv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                gv.widthAnchor.constraint(equalToConstant: gaugeSize),
                gv.heightAnchor.constraint(equalToConstant: gaugeSize),
            ])
        }

        let title5h = NSTextField(labelWithString: "5 hours")
        let title7d = NSTextField(labelWithString: "7 days")
        for lbl in [title5h, title7d] {
            lbl.font = .systemFont(ofSize: 11, weight: .medium)
            lbl.textColor = .secondaryLabelColor
            lbl.alignment = .center
        }
        for lbl in [detail5h, detail7d] {
            lbl.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            lbl.alignment = .center
        }

        let col5h = NSStackView(views: [title5h, gauge5hView, detail5h])
        col5h.orientation = .vertical; col5h.alignment = .centerX; col5h.spacing = 4
        let col7d = NSStackView(views: [title7d, gauge7dView, detail7d])
        col7d.orientation = .vertical; col7d.alignment = .centerX; col7d.spacing = 4

        let topRow = NSStackView(views: [col5h, col7d])
        topRow.orientation = .horizontal; topRow.distribution = .fillEqually; topRow.spacing = 20

        let sep = NSBox(); sep.boxType = .separator

        extraLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        extraLabel.textColor = .secondaryLabelColor
        extraLabel.alignment = .center

        let loginBtn = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLogin))
        loginBtn.controlSize = .small
        if #available(macOS 13.0, *) {
            loginBtn.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        self.loginCheckbox = loginBtn

        let refreshBtn = NSButton(title: "Refresh", target: self, action: #selector(refreshTapped))
        refreshBtn.bezelStyle = .rounded; refreshBtn.controlSize = .small
        let quitBtn = NSButton(title: "Quit", target: self, action: #selector(quitTapped))
        quitBtn.bezelStyle = .rounded; quitBtn.controlSize = .small

        let btnRow = NSStackView(views: [refreshBtn, quitBtn])
        btnRow.orientation = .horizontal; btnRow.spacing = 8

        let mainStack = NSStackView(views: [topRow, sep, extraLabel, loginBtn, btnRow])
        mainStack.orientation = .vertical; mainStack.spacing = 10; mainStack.alignment = .centerX
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
        ])

        self.view = root
    }

    func update(usage: UsageData?, extraRate: Double? = nil) {
        let e5h = usage.flatMap { elapsedPct(resetsAt: $0.resetsAt, windowHours: 5) }
        let e7d = usage.flatMap { elapsedPct(resetsAt: $0.sevenDayResetsAt, windowHours: 168) }
        let d5h = usage.flatMap { driftPct(usage: $0.fiveHourPct, resetsAt: $0.resetsAt, windowHours: 5) }
        let d7d = usage.flatMap { driftPct(usage: $0.sevenDayPct, resetsAt: $0.sevenDayResetsAt, windowHours: 168) }

        let extra = usage?.extraUsageCents ?? 0
        gauge5hView.image = renderPopoverGauge(
            pct: usage?.fiveHourPct ?? 0, elapsed: e5h, drift: d5h, full: (usage?.fiveHourPct ?? 0) >= 100)
        gauge7dView.image = renderPopoverGauge(
            pct: usage?.sevenDayPct ?? 0, elapsed: e7d, drift: d7d, full: (usage?.sevenDayPct ?? 0) >= 100)

        if let d = d5h, let u = usage {
            let reset = u.resetsAt.map { formatRelativeTime($0) } ?? "--"
            detail5h.stringValue = "\(formatDrift(d)) · \(reset)"
            detail5h.textColor = driftNSColor(d)
        } else {
            detail5h.stringValue = "--"
            detail5h.textColor = .secondaryLabelColor
        }
        if let d = d7d, let u = usage {
            let reset = u.sevenDayResetsAt.map { formatRelativeTime($0) } ?? "--"
            detail7d.stringValue = "\(formatDrift(d)) · \(reset)"
            detail7d.textColor = driftNSColor(d)
        } else {
            detail7d.stringValue = "--"
            detail7d.textColor = .secondaryLabelColor
        }

        var extraStr = "extra  \(String(format: "$%.2f", extra / 100))"
        if let rate = extraRate, rate > 0 {
            extraStr += "  (\(String(format: "$%.2f", rate / 100))/h)"
        }
        extraLabel.stringValue = extraStr
    }

    @objc private func refreshTapped() { onRefresh?() }
    @objc private func quitTapped() { onQuit?() }
    @available(macOS 13.0, *)
    @objc private func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
        loginCheckbox?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var usage: UsageData?
    private var eventMonitor: Any?
    private var extraTrackStart: (date: Date, cents: Double)?

    private var currentExtraRate: Double? {
        guard let u = usage, u.extraUsageCents > 0, let start = extraTrackStart else { return nil }
        let hours = Date().timeIntervalSince(start.date) / 3600
        guard hours > 0 else { return nil }
        return (u.extraUsageCents - start.cents) / hours
    }

    private lazy var popoverVC: PopoverViewController = {
        let vc = PopoverViewController()
        vc.onRefresh = { [weak self] in self?.refresh() }
        vc.onQuit = { NSApp.terminate(nil) }
        return vc
    }()
    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.contentViewController = popoverVC
        p.behavior = .transient
        return p
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = renderMenuBarIcon(usage: nil)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            popoverVC.update(usage: usage, extraRate: currentExtraRate)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func refresh() {
        Task {
            guard let token = readOAuthToken() else { return }
            guard let data = await fetchUsageData(token: token) else { return }
            await MainActor.run {
                self.usage = data

                if data.extraUsageCents > 0 {
                    let now = Date()
                    let shouldReset: Bool
                    if let start = self.extraTrackStart {
                        shouldReset = !Calendar.current.isDate(start.date, inSameDayAs: now)
                            || data.extraUsageCents < start.cents
                    } else {
                        shouldReset = true
                    }
                    if shouldReset {
                        self.extraTrackStart = (date: now, cents: data.extraUsageCents)
                    }
                } else {
                    self.extraTrackStart = nil
                }

                let extraDelta = self.extraTrackStart.map { max(0, data.extraUsageCents - $0.cents) } ?? 0
                self.statusItem.button?.image = renderMenuBarIcon(usage: data, extraDelta: extraDelta)
                if self.popover.isShown { self.popoverVC.update(usage: data, extraRate: self.currentExtraRate) }
            }
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
