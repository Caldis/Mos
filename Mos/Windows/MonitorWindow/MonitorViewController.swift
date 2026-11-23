import Cocoa

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
    private var pinnedEnd: CFTimeInterval?
    private var content: NSStackView?
    private var topConstraint: NSLayoutConstraint?

    override func loadView() {
        let root = NSVisualEffectView()
        root.blendingMode = .behindWindow
        root.state = .followsWindowActiveState
        if #available(macOS 10.14, *) {
            root.material = .underWindowBackground
        } else {
            root.material = .appearanceBased
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
        content.spacing = 10
        content.detachesHiddenViews = true
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        self.content = content
        let top = content.topAnchor.constraint(equalTo: root.topAnchor, constant: 12)
        topConstraint = top
        let chartHeight = timeline.heightAnchor.constraint(equalToConstant: 255)
        chartHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            top,
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 17),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -17),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
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
            replacement = content.topAnchor.constraint(equalTo: layout.topAnchor, constant: 12)
        } else {
            let inset = max(0, view.convert(view.bounds, to: nil).maxY - window.contentLayoutRect.maxY)
            replacement = content.topAnchor.constraint(equalTo: view.topAnchor, constant: 12 + inset)
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
        detailSplit.splitView.isVertical = true
        detailSplit.splitView.dividerStyle = .thin
        let tableItem = NSSplitViewItem(viewController: events)
        tableItem.minimumThickness = 370
        inspectorItem.minimumThickness = 284
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
            pinnedEnd = min(capture.displayTime, event.time + timeline.duration * 0.18)
            inspector.display(event)
            if !expanded {
                inspectorItem.isCollapsed = false
                let splitView = detailSplit.splitView
                if splitView.bounds.width >= 660 {
                    splitView.setPosition(max(370, splitView.bounds.width * 0.57), ofDividerAt: 0)
                }
            }
        } else {
            pinnedEnd = nil
            inspectorItem.isCollapsed = true
            events.update(channel: channel, selectedID: nil)
        }
        updatePlot()
    }

    private func render(_ update: MonitorCapture.Update) {
        if update.includes(channel) {
            events.update(channel: channel, selectedID: selection?.id)
        }
        if !update.isEmpty {
            monitorToolbar.update(capture.state, canClear: !capture.isEmpty, canExport: capture.count(channel) > 0)
        }
        if update.contains(.state) { updateNotice() }
        if pinnedEnd == nil || update.contains(.state) { updatePlot() }
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
        guard channel == .scroll else { return }
        let duration = timeline.duration
        let end = max(capture.origin + duration, pinnedEnd ?? capture.displayTime, selection?.time ?? capture.origin)
        let range = (end - duration)...end
        timeline.curve.display(
            capture.timeline(in: range), range: range, origin: capture.origin,
            axis: timeline.axis, selection: selection?.time,
            waitingForInput: capture.state == .recording && capture.count(.scroll) == 0
        )
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
