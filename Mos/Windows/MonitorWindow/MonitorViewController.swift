import Cocoa

final class MonitorViewController: NSViewController {
    private enum LogChannel: Int {
        case scroll
        case buttons

        var fileName: String {
            switch self {
            case .scroll: return "monitor-scroll-events"
            case .buttons: return "monitor-button-events"
            }
        }
    }

    private static let tapMask = [
        CGEventType.scrollWheel, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .mouseMoved, .keyDown, .keyUp, .flagsChanged,
    ].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

    private let trace = ScrollMonitorTrace.shared
    private let startTime = CACurrentMediaTime()
    private var displayTime = CACurrentMediaTime()
    private var scrollHistory = MonitorHistory<ScrollMonitorSample>(capacity: 16_384)
    private var buttonHistory = MonitorHistory<MonitorButtonEvent>(capacity: 8_192)
    private var incoming: [ScrollMonitorSample] = []
    private var tap: Interceptor?
    private var refreshTimer: Timer?
    private var nextLogRefresh: CFTimeInterval = 0
    private var logChannel = LogChannel.scroll
    private var logNeedsRefresh = true
    private var recordingStarted = false
    private var windowDuration: CFTimeInterval = 5
    private var droppedSamples = 0
    private var captureUnavailable = false

    private let curve = MonitorCurveView()
    private let log = NSTextView(frame: .zero)
    private let status = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "5 s")
    private let durationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()
    private let logParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.headIndent = 15
        style.paragraphSpacing = 2
        return style
    }()
    private lazy var recordingButton = NSButton(title: "", target: self, action: #selector(toggleRecording))
    private lazy var copyButton = NSButton(
        title: NSLocalizedString("copy", comment: "Copy"), target: self, action: #selector(copyLog)
    )
    private lazy var exportButton = NSButton(
        title: NSLocalizedString("monitor-export-log", comment: "Export the selected event log"),
        target: self,
        action: #selector(exportLog)
    )
    private lazy var shortcutButton = NSButton(
        title: NSLocalizedString("monitor-test-shortcut", comment: "End-user shortcut test menu"),
        target: self,
        action: #selector(showShortcuts(_:))
    )

    deinit {
        if refreshTimer != nil {
            ScrollMonitorTrace.setSharedRecording(false)
            trace.drain(into: &incoming)
        }
        refreshTimer?.invalidate()
        tap?.stop()
    }

    override func loadView() {
        let root = NSVisualEffectView()
        root.blendingMode = .behindWindow
        root.state = .followsWindowActiveState
        if #available(macOS 10.14, *) {
            root.material = .underWindowBackground
        } else {
            root.material = .appearanceBased
        }
        let windowLabel = NSTextField(labelWithString: NSLocalizedString("monitor-time-window", comment: "Scroll timeline time window"))
        let slider = NSSlider(
            value: windowDuration, minValue: 1, maxValue: 10, target: self, action: #selector(changeDuration(_:))
        )
        slider.isContinuous = true
        slider.setAccessibilityLabel(windowLabel.stringValue)
        slider.widthAnchor.constraint(equalToConstant: 136).isActive = true
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true

        let clearButton = NSButton(
            title: NSLocalizedString("monitor-clear", comment: "Clear the timeline and event logs"),
            target: self,
            action: #selector(clear)
        )
        let timelineControls = controls([windowLabel, slider, durationLabel, NSView(), recordingButton, clearButton])
        curve.setAccessibilityElement(true)
        curve.setAccessibilityRole(.group)
        curve.setAccessibilityLabel(NSLocalizedString("monitor-scroll-timeline", comment: "Accessible name for the scroll timeline"))

        let filter = NSSegmentedControl(
            labels: [
                NSLocalizedString("monitor-scroll-log", comment: "Scroll event log tab"),
                NSLocalizedString("monitor-button-log", comment: "Mouse and keyboard event log tab"),
            ],
            trackingMode: .selectOne, target: self, action: #selector(changeChannel(_:))
        )
        filter.selectedSegment = logChannel.rawValue
        shortcutButton.isHidden = true
        let eventControls = controls([filter, NSView(), shortcutButton, copyButton, exportButton])
        status.textColor = .secondaryLabelColor
        status.isHidden = true

        let logScroll = makeLogScrollView()
        let content = NSStackView(views: [timelineControls, curve, status, eventControls, logScroll])
        content.orientation = .vertical
        content.alignment = .leading
        content.distribution = .fill
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        let contentTop: NSLayoutConstraint
        let topPadding: CGFloat = 8
        if #available(macOS 11.0, *) {
            contentTop = content.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: topPadding)
        } else {
            let titlebarHeight = NSWindow.frameRect(forContentRect: .zero, styleMask: .titled).height
            contentTop = content.topAnchor.constraint(equalTo: root.topAnchor, constant: titlebarHeight + topPadding)
        }
        NSLayoutConstraint.activate([
            contentTop,
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            timelineControls.widthAnchor.constraint(equalTo: content.widthAnchor),
            curve.widthAnchor.constraint(equalTo: content.widthAnchor),
            curve.heightAnchor.constraint(equalToConstant: 232),
            eventControls.widthAnchor.constraint(equalTo: content.widthAnchor),
            logScroll.widthAnchor.constraint(equalTo: content.widthAnchor),
            logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        view = root
        updateRecordingButton()
        refreshLog(force: true)
    }

    private func controls(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func makeLogScrollView() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        log.isEditable = false
        log.isSelectable = true
        log.isRichText = false
        log.isVerticallyResizable = true
        log.autoresizingMask = [.width]
        log.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        log.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        log.textContainer?.widthTracksTextView = true
        log.textContainerInset = NSSize(width: 10, height: 8)
        log.defaultParagraphStyle = logParagraphStyle
        scroll.documentView = log
        return scroll
    }

    func startRecording() {
        guard refreshTimer == nil else { return }

        do {
            tap = try Interceptor(
                event: Self.tapMask,
                handleBy: { [weak self] _, type, event, _ in
                    self?.observe(type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .listenOnly
            )
            ScrollMonitorTrace.setSharedRecording(true)
            recordingStarted = true
            captureUnavailable = false
            updateStatus()
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                self?.refresh()
            }
            timer.tolerance = 0.005
            refreshTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            updateRecordingButton()
        } catch {
            captureUnavailable = true
            updateStatus()
        }
    }

    func stopRecording() {
        guard refreshTimer != nil else { return }
        ScrollMonitorTrace.setSharedRecording(false)
        refreshTimer?.invalidate()
        refreshTimer = nil
        tap?.stop()
        tap = nil
        readPendingSamples()
        displayTime = CACurrentMediaTime()
        refreshTimeline()
        refreshLog(force: true)
        updateRecordingButton()
    }

    private func observe(_ type: CGEventType, event: CGEvent) {
        if type == .scrollWheel {
            trace.record(event, stage: .observed)
        } else if type != .tapDisabledByTimeout, type != .tapDisabledByUserInput,
                  let sample = MonitorButtonEvent(event) {
            buttonHistory.append(sample)
            if logChannel == .buttons { logNeedsRefresh = true }
        }
    }

    private func refresh() {
        guard InputPermissionMonitor.shared.isAuthorized else {
            stopRecording()
            captureUnavailable = true
            updateStatus()
            return
        }
        readPendingSamples()
        displayTime = CACurrentMediaTime()
        refreshTimeline()
        if displayTime >= nextLogRefresh {
            nextLogRefresh = displayTime + 0.15
            refreshLog()
            captureUnavailable = tap?.isRunning() != true
            updateStatus()
        }
    }

    private func readPendingSamples() {
        droppedSamples += trace.drain(into: &incoming)
        for sample in incoming { scrollHistory.append(sample) }
        if !incoming.isEmpty && logChannel == .scroll { logNeedsRefresh = true }
    }

    private func refreshTimeline() {
        let start = displayTime - windowDuration
        let visible = scrollHistory.reversed().prefix { $0.time >= start }.filter { $0.stage.lane != nil }
        curve.update(samples: Array(visible.reversed()), end: displayTime, duration: windowDuration)
    }

    private func refreshLog(force: Bool = false) {
        guard force || logNeedsRefresh else { return }
        let canCopy: Bool
        switch logChannel {
        case .scroll: canCopy = !scrollHistory.isEmpty
        case .buttons: canCopy = !buttonHistory.isEmpty
        }
        copyButton.isEnabled = canCopy
        exportButton.isEnabled = canCopy
        if !force && (log.selectedRange().length > 0 || (log.enclosingScrollView?.contentView.bounds.minY ?? 0) > 1) {
            return
        }
        logNeedsRefresh = false
        let lines: [String]
        switch logChannel {
        case .scroll: lines = scrollHistory.suffix(60).reversed().map { $0.logLine(since: startTime) }
        case .buttons: lines = buttonHistory.suffix(60).reversed().map { $0.logLine(since: startTime) }
        }
        let empty = lines.isEmpty
        let text = empty ? NSLocalizedString("monitor-no-events", comment: "Event log empty state") : lines.joined(separator: "\n")
        let font: NSFont
        if empty {
            font = .systemFont(ofSize: 12)
        } else if #available(macOS 10.15, *) {
            font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        } else {
            font = NSFont.userFixedPitchFont(ofSize: 11) ?? .systemFont(ofSize: 11)
        }
        log.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: empty ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: logParagraphStyle,
        ]))
        log.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    private func logTextForExport() -> String {
        switch logChannel {
        case .scroll: return scrollHistory.map { $0.logLine(since: startTime) }.joined(separator: "\n")
        case .buttons: return buttonHistory.map { $0.logLine(since: startTime) }.joined(separator: "\n")
        }
    }

    private func updateRecordingButton() {
        if refreshTimer != nil {
            recordingButton.title = NSLocalizedString("monitor-pause", comment: "Pause recording event data")
        } else if recordingStarted {
            recordingButton.title = NSLocalizedString("monitor-resume", comment: "Resume recording event data")
        } else {
            recordingButton.title = NSLocalizedString("monitor-record", comment: "Start recording event data")
        }
    }

    private func updateStatus() {
        if captureUnavailable {
            status.stringValue = NSLocalizedString("monitor-capture-unavailable", comment: "The passive event listener could not be enabled")
        } else if droppedSamples > 0 {
            let label = NSLocalizedString("monitor-dropped-samples", comment: "Number of scroll samples lost when the capture queue filled")
            status.stringValue = "\(label) \(droppedSamples)"
        } else {
            status.stringValue = ""
        }
        status.isHidden = status.stringValue.isEmpty
    }

    @objc private func toggleRecording() {
        if refreshTimer == nil {
            startRecording()
        } else {
            stopRecording()
            captureUnavailable = false
            updateStatus()
        }
    }

    @objc private func changeDuration(_ sender: NSSlider) {
        windowDuration = (sender.doubleValue * 2).rounded() / 2
        let seconds = durationFormatter.string(from: NSNumber(value: windowDuration)) ?? String(windowDuration)
        durationLabel.stringValue = "\(seconds) s"
        refreshTimeline()
    }

    @objc private func changeChannel(_ sender: NSSegmentedControl) {
        guard let channel = LogChannel(rawValue: sender.selectedSegment) else { return }
        logChannel = channel
        shortcutButton.isHidden = channel != .buttons
        refreshLog(force: true)
    }

    @objc private func clear() {
        trace.drain(into: &incoming)
        incoming.removeAll(keepingCapacity: true)
        scrollHistory.removeAll()
        buttonHistory.removeAll()
        droppedSamples = 0
        displayTime = CACurrentMediaTime()
        refreshTimeline()
        refreshLog(force: true)
        updateStatus()
    }

    @objc private func copyLog() {
        readPendingSamples()
        let text = logTextForExport()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func exportLog() {
        guard let window = view.window else { return }
        readPendingSamples()
        let text = logTextForExport()
        guard !text.isEmpty else { return }

        let date = DateFormatter()
        date.dateFormat = "yyyy-MM-dd-HHmmss"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(logChannel.fileName)-\(date.string(from: Date())).log"
        panel.allowedFileTypes = ["log", "txt"]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self?.presentError(error)
            }
        }
    }

    @objc private func showShortcuts(_ sender: NSButton) {
        let menu = NSMenu()
        ShortcutManager.buildShortcutMenu(into: menu, target: self, action: #selector(runShortcut(_:)))
        menu.items = menu.items.filter { $0.submenu != nil }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
    }

    @objc private func runShortcut(_ sender: NSMenuItem) {
        guard let shortcut = sender.representedObject as? SystemShortcut.Shortcut else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ShortcutExecutor.shared.execute(shortcut)
        }
    }
}
