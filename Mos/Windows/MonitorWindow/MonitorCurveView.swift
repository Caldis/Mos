import Cocoa

struct MonitorTimelineSample {
    let time: CFTimeInterval
    let stage: ScrollMonitorStage
    let delta: MonitorDelta
    let phase: Int64
    let hasMomentum: Bool

    init?(event: MonitorEvent) {
        guard case .scroll(let sample) = event.payload else { return nil }
        time = event.time
        stage = sample.stage
        delta = sample.delta
        phase = sample.fields?.phase ?? 0
        hasMomentum = (sample.fields?.momentum ?? 0) != 0
    }
}

final class MonitorCurveView: NSView {
    private var samples: [MonitorTimelineSample] = []
    private var range: ClosedRange<CFTimeInterval> = 0...5
    private var selection: CFTimeInterval?
    private var waitingForInput = false
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let verticalColor = NSColor.systemBlue
    static let horizontalColor = NSColor.systemTeal

    override var isFlipped: Bool { true }

    func display(
        _ samples: [MonitorTimelineSample],
        range: ClosedRange<CFTimeInterval>,
        selection: CFTimeInterval?,
        waitingForInput: Bool
    ) {
        let durationChanged = range.upperBound - range.lowerBound != self.range.upperBound - self.range.lowerBound
        let needsRedraw = !samples.isEmpty || !self.samples.isEmpty || durationChanged
            || selection != self.selection || waitingForInput != self.waitingForInput

        self.samples = samples
        self.range = range
        self.selection = selection
        self.waitingForInput = waitingForInput
        if needsRedraw { needsDisplay = true }
    }

    static func visibleRange(
        endingAt now: CFTimeInterval,
        duration: CFTimeInterval,
        selection: CFTimeInterval?,
        recording: Bool
    ) -> ClosedRange<CFTimeInterval> {
        // Inspecting a row can reposition a paused graph. A live graph always
        // follows the recording clock while the selected raw values stay put.
        if !recording, let selection = selection, selection < now - duration {
            let end = selection + duration / 5
            return (end - duration)...end
        }
        return (now - duration)...now
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width >= 320, bounds.height >= 100 else { return }

        let panel = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        NSColor.textBackgroundColor.setFill()
        panel.fill()
        stroke(panel, color: NSColor.labelColor.withAlphaComponent(0.15), width: 1)

        let laneTitles = [
            NSLocalizedString("monitor-captured", comment: "Captured input in the timeline"),
            NSLocalizedString("monitor-output", comment: "Output overlay in the timeline"),
        ]
        let plotStart = max(154, (laneTitles.map { textWidth($0) }.max() ?? 0) + 23)
        let width = bounds.width - plotStart - 14
        guard width > 0 else { return }

        let laneHeight = (bounds.height - 30) / 2
        let input = NSRect(x: plotStart, y: 8, width: width, height: laneHeight)
        let output = input.offsetBy(dx: 0, dy: laneHeight)
        drawLane(laneTitles[0], input: true, in: input)
        drawLane(laneTitles[1], input: false, in: output)
        drawSelection(in: input.union(output))
        drawTimeAxis(in: NSRect(x: plotStart, y: output.maxY + 3, width: width, height: 16))

        if waitingForInput {
            let message = NSLocalizedString("monitor-waiting-scroll", comment: "No scroll input received yet")
            drawText(message, at: NSPoint(x: input.midX - textWidth(message) / 2, y: input.maxY - 8),
                     color: .secondaryLabelColor)
        }
    }

    private func drawLane(_ title: String, input: Bool, in plot: NSRect) {
        let points = samples.filter {
            ($0.stage == .captured) == input && $0.delta.x.isFinite
                && $0.delta.y.isFinite && range.contains($0.time)
        }
        let peak = points.reduce(1.0) { max($0, abs($1.delta.x), abs($1.delta.y)) }
        drawText(title, at: NSPoint(x: 13, y: plot.midY - 15), color: .labelColor, weight: .medium)
        if !points.isEmpty {
            drawText("±\(scaleLabel(peak)) pt", at: NSPoint(x: 13, y: plot.midY + 1), color: .secondaryLabelColor)
        }

        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: plot.minX, y: plot.midY))
        baseline.line(to: NSPoint(x: plot.maxX, y: plot.midY))
        stroke(baseline, color: NSColor.labelColor.withAlphaComponent(0.24), width: 0.7)

        let grid = NSBezierPath()
        for step in 0...4 {
            let x = plot.minX + CGFloat(step) * plot.width / 4
            grid.move(to: NSPoint(x: x, y: plot.minY + 3))
            grid.line(to: NSPoint(x: x, y: plot.maxY - 3))
        }
        stroke(grid, color: NSColor.labelColor.withAlphaComponent(0.13), width: 0.6)

        if !input { drawPhaseMarkers(points, in: plot) }
        drawSamples(points, axis: .vertical, peak: peak, in: plot)
        drawSamples(points, axis: .horizontal, peak: peak, in: plot)
    }

    private func drawPhaseMarkers(_ points: [MonitorTimelineSample], in plot: NSRect) {
        let began = NSBezierPath()
        let ended = NSBezierPath()
        for sample in points where sample.stage == .postedToProcess || sample.stage == .postedToHID {
            guard sample.phase == 1 || sample.phase == 4 else { continue }
            let marker = sample.phase == 1 ? began : ended
            let x = position(of: sample.time, in: plot)
            marker.move(to: NSPoint(x: x, y: plot.minY + 4))
            marker.line(to: NSPoint(x: x, y: plot.maxY - 4))
        }
        stroke(began, color: .systemRed, width: 1)
        stroke(ended, color: .systemPurple, width: 1, dashed: true)
    }

    private func drawSamples(
        _ points: [MonitorTimelineSample], axis: MonitorAxis, peak: Double, in plot: NSRect
    ) {
        let stems = NSBezierPath()
        let momentumStems = NSBezierPath()
        let posts = NSBezierPath()
        let momentumPosts = NSBezierPath()
        let horizontal = axis == .horizontal
        let color = horizontal ? Self.horizontalColor : Self.verticalColor
        let scale = plot.height / 2 - 7

        for sample in points {
            let value = sample.delta[axis]
            let x = position(of: sample.time, in: plot)
            let y = plot.midY - CGFloat(value / peak) * scale
            switch sample.stage {
            case .captured, .frame:
                // Keep each input and computed frame as the original discrete stem.
                if value != 0 {
                    let path = sample.hasMomentum ? momentumStems : stems
                    path.move(to: NSPoint(x: x, y: plot.midY))
                    path.line(to: NSPoint(x: x, y: y))
                }
            case .postedToProcess, .postedToHID:
                let dots = sample.hasMomentum ? momentumPosts : posts
                // A hollow X marker stays legible over a coincident Y point
                // without shifting either sample away from its timestamp.
                let radius: CGFloat = horizontal ? 2.8 : 1.8
                dots.appendOval(in: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }

        stroke(stems, color: color, width: 1.5, dashed: horizontal)
        stroke(momentumStems, color: color.withAlphaComponent(0.7), width: 1.5, dashed: true)
        if horizontal {
            stroke(posts, color: color, width: 1.1)
        } else {
            color.setFill()
            posts.fill()
        }
        stroke(momentumPosts, color: color, width: 1.1, dashed: true)
    }

    private func position(of time: CFTimeInterval, in rect: NSRect) -> CGFloat {
        let fraction = (time - range.lowerBound) / (range.upperBound - range.lowerBound)
        return rect.minX + rect.width * CGFloat(fraction)
    }

    private func drawSelection(in rect: NSRect) {
        guard let selection = selection, range.contains(selection) else { return }
        let path = NSBezierPath()
        let x = position(of: selection, in: rect)
        path.move(to: NSPoint(x: x, y: rect.minY))
        path.line(to: NSPoint(x: x, y: rect.maxY))
        stroke(path, color: NSColor.labelColor.withAlphaComponent(0.6), width: 0.75)
    }

    private func drawTimeAxis(in axis: NSRect) {
        drawText("−\(scaleLabel(range.upperBound - range.lowerBound)) s", at: axis.origin, color: .secondaryLabelColor)
        let now = "0 s"
        drawText(now, at: NSPoint(x: axis.maxX - textWidth(now), y: axis.minY), color: .secondaryLabelColor)
    }

    private func scaleLabel(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? ""
    }

    private func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat, dashed: Bool = false) {
        if dashed { path.setLineDash([2, 2], count: 2, phase: 0) }
        color.setStroke()
        path.lineWidth = width
        path.stroke()
    }

    private func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
    }

    private func drawText(_ text: String, at point: NSPoint, color: NSColor, weight: NSFont.Weight = .regular) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: weight),
            .foregroundColor: color,
        ])
    }
}

/// The legend and range share one row above the plot.
final class MonitorTimelineView: NSView {
    let curve = MonitorCurveView()
    private(set) var duration: CFTimeInterval = 5
    var didChange: (() -> Void)?

    private let durationLabel = NSTextField(labelWithString: "")
    private let decrease = NSButton()
    private let increase = NSButton()

    init() {
        super.init(frame: .zero)
        let title = NSTextField(labelWithString: NSLocalizedString("monitor-scroll-timeline", comment: "Scroll Timeline title"))
        title.font = .systemFont(ofSize: 14, weight: .semibold)

        configureStep(decrease, symbol: "−", name: NSLocalizedString("monitor-shorten-window", comment: "Shorten time window"),
                      action: #selector(shorten))
        configureStep(increase, symbol: "+", name: NSLocalizedString("monitor-extend-window", comment: "Extend time window"),
                      action: #selector(extend))
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.alignment = .right
        durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        let header = NSStackView(views: [
            title,
            legend("Y", color: MonitorCurveView.verticalColor, dot: false),
            legend("X", color: MonitorCurveView.horizontalColor, dot: false),
            legend(NSLocalizedString("monitor-computed-frames", comment: "Smoothed frames legend"), color: .secondaryLabelColor, dot: false),
            legend(NSLocalizedString("monitor-posted-events", comment: "Posted events legend"), color: .secondaryLabelColor, dot: true),
            NSView(), durationLabel, decrease, increase
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        curve.translatesAutoresizingMaskIntoConstraints = false
        curve.setAccessibilityElement(true)
        curve.setAccessibilityRole(.group)
        curve.setAccessibilityLabel(title.stringValue)
        addSubview(curve)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            curve.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            curve.leadingAnchor.constraint(equalTo: leadingAnchor),
            curve.trailingAnchor.constraint(equalTo: trailingAnchor),
            curve.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        updateRangeControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init()") }

    private func configureStep(_ button: NSButton, symbol: String, name: String, action: Selector) {
        button.title = symbol
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action
        button.toolTip = name
        button.setAccessibilityLabel(name)
    }

    private func legend(_ name: String, color: NSColor, dot: Bool) -> NSStackView {
        let image = NSImage(size: NSSize(width: 15, height: 10), flipped: false) { rect in
            color.setFill()
            if dot {
                NSBezierPath(ovalIn: NSRect(x: rect.midX - 2.4, y: rect.midY - 2.4, width: 4.8, height: 4.8)).fill()
            } else {
                NSBezierPath(rect: NSRect(x: rect.minX + 1, y: rect.midY - 0.6, width: rect.width - 2, height: 1.2)).fill()
            }
            return true
        }
        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.toolTip = name
        let legend = NSStackView(views: [NSImageView(image: image), label])
        legend.alignment = .centerY
        legend.spacing = 4
        return legend
    }

    private func updateRangeControls() {
        durationLabel.stringValue = "\(MonitorPresentation.displacement(duration)) s"
        decrease.isEnabled = duration > 1
        increase.isEnabled = duration < 10
    }

    @objc private func shorten() { changeDuration(by: -0.5) }
    @objc private func extend() { changeDuration(by: 0.5) }

    private func changeDuration(by step: CFTimeInterval) {
        duration = min(10, max(1, duration + step))
        updateRangeControls()
        didChange?()
    }
}
