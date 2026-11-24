import Cocoa
import QuartzCore

final class MonitorViewController: NSViewController {
    let monitorToolbar = MonitorToolbar()
    private let capture = MonitorCapture()
    private let timeline = MonitorTimelineView()
    private let inspector = MonitorInspector()
    private let notice = NSTextField(wrappingLabelWithString: "")
    private lazy var events = MonitorEventTable(capture: capture)
    private lazy var inspectorItem = NSSplitViewItem(viewController: inspector)
    private let detailSplit = NSSplitViewController()

    private var channel: MonitorChannel = .scroll
    private var selection: MonitorEvent?
    private var content: NSStackView?
    private var topConstraint: NSLayoutConstraint?

    override func loadView() {
        let root = NSVisualEffectView()
        root.blendingMode = .behindWindow
        root.state = .active
        if #available(macOS 10.14, *) {
            root.material = .hudWindow
        } else {
            root.material = .dark
        }

        view = root
        configureSplit()
        notice.isHidden = true
        notice.textColor = .systemOrange
        notice.font = .systemFont(ofSize: 11, weight: .medium)
        let content = NSStackView(views: [notice, timeline, detailSplit.view])
        content.orientation = .vertical
        content.alignment = .leading
        content.distribution = .fill
        content.spacing = MonitorStyle.padding
        content.detachesHiddenViews = true
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        self.content = content
        let top = content.topAnchor.constraint(equalTo: root.topAnchor, constant: MonitorStyle.padding)
        topConstraint = top
        let chartHeight = timeline.heightAnchor.constraint(equalToConstant: 255)
        chartHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            top,
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: MonitorStyle.padding),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -MonitorStyle.padding),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -MonitorStyle.padding),
            notice.widthAnchor.constraint(equalTo: content.widthAnchor),
            timeline.widthAnchor.constraint(equalTo: content.widthAnchor),
            timeline.heightAnchor.constraint(greaterThanOrEqualToConstant: 194),
            chartHeight,
            detailSplit.view.widthAnchor.constraint(equalTo: content.widthAnchor),
            detailSplit.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 145),
        ])
        connectControls()
        render([.scroll, .buttons, .state])
    }

    func alignBelowToolbar(in window: NSWindow) {
        guard let content = content else { return }
        topConstraint?.isActive = false
        let replacement: NSLayoutConstraint
        if let layout = window.contentLayoutGuide as? NSLayoutGuide {
            replacement = content.topAnchor.constraint(equalTo: layout.topAnchor, constant: 4)
        } else {
            let inset = max(0, view.convert(view.bounds, to: nil).maxY - window.contentLayoutRect.maxY)
            replacement = content.topAnchor.constraint(equalTo: view.topAnchor, constant: max(MonitorStyle.padding, inset + 4))
        }
        replacement.isActive = true
        topConstraint = replacement
    }

    func startRecording() {
        _ = view
        capture.start()
    }

    func stopRecording() {
        capture.pause()
    }

    private func configureSplit() {
        let split = MonitorDetailSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        detailSplit.splitView = split
        let tableItem = NSSplitViewItem(viewController: events)
        tableItem.minimumThickness = 370
        inspectorItem.minimumThickness = 284 + MonitorStyle.padding
        inspectorItem.canCollapse = true
        detailSplit.addSplitViewItem(tableItem)
        detailSplit.addSplitViewItem(inspectorItem)
        inspectorItem.isCollapsed = true
        addChild(detailSplit)
    }

    private func connectControls() {
        monitorToolbar.didSelectChannel = { [weak self] in self?.switchTo($0) }
        monitorToolbar.didToggleRecording = { [weak self] in self?.toggleRecording() }
        monitorToolbar.didClear = { [weak self] in self?.clear() }
        monitorToolbar.didExport = { [weak self] in self?.export() }
        capture.didUpdate = { [weak self] in self?.render($0) }
        timeline.didChange = { [weak self] in self?.updatePlot() }
        events.didSelect = { [weak self] in self?.select($0) }
        inspector.didClose = { [weak self] in self?.select(nil) }
    }

    private func switchTo(_ channel: MonitorChannel) {
        guard self.channel != channel else { return }
        self.channel = channel
        timeline.isHidden = channel != .scroll
        select(nil)
        render([.scroll, .buttons, .state])
    }

    private func toggleRecording() {
        if capture.state == .recording {
            capture.pause()
        } else {
            capture.start()
        }
    }

    private func clear() {
        select(nil)
        capture.clear()
    }

    private func select(_ event: MonitorEvent?) {
        selection = event
        let expanded = !inspectorItem.isCollapsed
        if let event = event {
            inspector.display(event)
            if !expanded {
                inspectorItem.isCollapsed = false
                let splitView = detailSplit.splitView
                if splitView.bounds.width >= 660 {
                    splitView.setPosition(max(370, splitView.bounds.width * 0.57), ofDividerAt: 0)
                }
            }
        } else {
            inspectorItem.isCollapsed = true
            events.update(channel: channel, selectedID: nil)
        }
        updatePlot()
    }

    private func render(_ update: MonitorCapture.Update) {
        if channel == .scroll && (update.contains(.scroll) || update.contains(.state) || timeline.curve.hasSamples) {
            updatePlot()
        }
        if update.includes(channel) {
            events.update(channel: channel, selectedID: selection?.id)
        }
        if !update.isEmpty {
            monitorToolbar.update(capture.state, canClear: !capture.isEmpty, canExport: capture.count(channel) > 0)
        }
        if update.contains(.state) { updateNotice() }
    }

    private func updateNotice() {
        switch capture.state {
        case .accessibilityRequired:
            notice.stringValue = NSLocalizedString("monitor-accessibility-required", comment: "Accessibility required for Monitor")
        case .tapUnavailable:
            notice.stringValue = NSLocalizedString("monitor-capture-unavailable", comment: "The Monitor tap cannot be enabled")
        case .recording, .paused:
            notice.stringValue = capture.missed > 0
                ? String.localizedStringWithFormat(
                    NSLocalizedString("monitor-samples-missed", comment: "Samples missed by the Monitor buffer"), Int64(capture.missed)
                  )
                : ""
        }
        notice.isHidden = notice.stringValue.isEmpty
    }

    private func updatePlot() {
        guard channel == .scroll else {
            timeline.animateLiveCurve(false)
            return
        }
        let recording = capture.state == .recording
        let range = MonitorCurveView.visibleRange(
            endingAt: recording ? CACurrentMediaTime() : capture.displayTime,
            duration: timeline.duration, selection: selection?.time, recording: recording
        )
        let samples = capture.timeline(in: range)
        timeline.curve.display(
            samples, range: range, selection: selection?.time,
            waitingForInput: recording && capture.count(.scroll) == 0
        )
        timeline.animateLiveCurve(recording && !samples.isEmpty)
    }

    private func export() {
        guard let window = view.window else { return }
        let text = capture.export(channel)
        guard !text.isEmpty else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = channel.exportName
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
}

private final class MonitorDetailSplitView: NSSplitView {
    // Keep the system divider geometry for collapsing, with a gutter in the inspector pane.
    override func drawDivider(in rect: NSRect) {}
}
