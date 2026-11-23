import Cocoa

struct MonitorTimelineSample {
    let time: CFTimeInterval
    let stage: ScrollMonitorStage
    let delta: MonitorDelta

    init?(event: MonitorEvent) {
        guard case .scroll(let sample) = event.payload else { return nil }
        time = event.time
        stage = sample.stage
        delta = sample.delta
    }
}

final class MonitorCurveView: NSView {
    private var samples: [MonitorTimelineSample] = []
    private var range: ClosedRange<CFTimeInterval> = 0...5
    private var origin: CFTimeInterval = 0
    private var axis: MonitorAxis = .vertical
    private var selection: CFTimeInterval?
    private var waitingForInput = false

    static let frameColor = NSColor.systemBlue
    static let postColor = NSColor.systemOrange

    override var isFlipped: Bool { true }

    func display(
        _ samples: [MonitorTimelineSample],
        range: ClosedRange<CFTimeInterval>,
        origin: CFTimeInterval,
        axis: MonitorAxis,
        selection: CFTimeInterval?,
        waitingForInput: Bool
    ) {
        self.samples = samples
        self.range = range
        self.origin = origin
        self.axis = axis
        self.selection = selection
        self.waitingForInput = waitingForInput
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width >= 220, bounds.height >= 100 else { return }

        let inputTitle = NSLocalizedString("monitor-captured", comment: "Captured input in the timeline")
        let outputTitle = NSLocalizedString("monitor-output", comment: "Output overlay in the timeline")
        let laneFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let inset = max(106, [inputTitle, outputTitle].map {
            ($0 as NSString).size(withAttributes: [.font: laneFont]).width
        }.max() ?? 0) + 16
        let width = bounds.width - inset - 18
        guard width > 1 else { return }

        let height = (bounds.height - 34) / 2
        let input = NSRect(x: inset, y: 8, width: width, height: height)
        let output = input.offsetBy(dx: 0, dy: height)
        let inputPeak = peak(forInput: true, floor: 24)
        let outputPeak = peak(forInput: false, floor: 8)

        drawGrid(input: input, output: output)
        drawLaneLabel(inputTitle, peak: inputPeak, at: input.midY, font: laneFont)
        drawLaneLabel(outputTitle, peak: outputPeak, at: output.midY, font: laneFont)
        drawSelection(in: input.union(output))
        drawSamples(input: input, inputPeak: inputPeak, output: output, outputPeak: outputPeak)
        if waitingForInput {
            let text = NSLocalizedString("monitor-waiting-scroll", comment: "No scroll input received yet")
            let font = NSFont.systemFont(ofSize: 12)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            draw(text, at: NSPoint(x: input.midX - width / 2, y: input.maxY - 8), font: font)
        }
    }

    private func peak(forInput input: Bool, floor: Double) -> Double {
        samples.reduce(floor) { peak, sample in
            let value = sample.delta[axis]
            guard value.isFinite, (sample.stage == .captured) == input else { return peak }
            return max(peak, abs(value).rounded(.up))
        }
    }

    private func x(_ time: CFTimeInterval, in rect: NSRect) -> CGFloat {
        let fraction = (time - range.lowerBound) / (range.upperBound - range.lowerBound)
        return rect.minX + rect.width * CGFloat(fraction)
    }

    private func drawGrid(input: NSRect, output: NSRect) {
        let grid = NSBezierPath()
        let zero = NSBezierPath()
        for step in 0...5 {
            let position = input.minX + input.width * CGFloat(step) / 5
            grid.move(to: NSPoint(x: position, y: input.minY))
            grid.line(to: NSPoint(x: position, y: output.maxY))

            let time = range.lowerBound + (range.upperBound - range.lowerBound) * Double(step) / 5
            let label = "\(MonitorPresentation.displacement(time - origin)) s"
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            let offset = (label as NSString).size(withAttributes: [.font: font]).width / 2
            let left = min(max(0, position - offset), bounds.maxX - offset * 2)
            draw(label, at: NSPoint(x: left, y: output.maxY + 6), font: font)
        }
        for lane in [input, output] {
            zero.move(to: NSPoint(x: lane.minX, y: lane.midY))
            zero.line(to: NSPoint(x: lane.maxX, y: lane.midY))
        }
        stroke(grid, color: NSColor.labelColor.withAlphaComponent(0.14), width: 0.5)
        stroke(zero, color: NSColor.labelColor.withAlphaComponent(0.37), width: 0.75)
    }

    private func drawLaneLabel(_ title: String, peak: Double, at y: CGFloat, font: NSFont) {
        draw(title, at: NSPoint(x: 3, y: y - 12), font: font, color: .labelColor)
        draw("±\(MonitorPresentation.displacement(peak)) pt",
             at: NSPoint(x: 3, y: y + 3),
             font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular))
    }

    private func drawSelection(in rect: NSRect) {
        guard let selection = selection, range.contains(selection) else { return }
        let path = NSBezierPath()
        let position = x(selection, in: rect)
        path.move(to: NSPoint(x: position, y: rect.minY))
        path.line(to: NSPoint(x: position, y: rect.maxY))
        stroke(path, color: Self.frameColor.withAlphaComponent(0.75), width: 0.75)
    }

    private func drawSamples(input: NSRect, inputPeak: Double, output: NSRect, outputPeak: Double) {
        let captured = NSBezierPath()
        let frames = NSBezierPath()
        let framePoints = NSBezierPath()
        let posts = NSBezierPath()
        var previousFrameTime: CFTimeInterval?
        for sample in samples {
            let value = sample.delta[axis]
            guard value.isFinite, range.contains(sample.time) else { continue }
            let isInput = sample.stage == .captured
            let lane = isInput ? input : output
            let peak = isInput ? inputPeak : outputPeak
            let horizontal = x(sample.time, in: lane)
            let point = NSPoint(x: horizontal, y: lane.midY - CGFloat(value / peak) * (lane.height / 2 - 5))

            switch sample.stage {
            case .captured:
                captured.move(to: NSPoint(x: horizontal, y: lane.midY))
                captured.line(to: point)
            case .frame:
                // Break the line across idle gaps instead of drawing invented frames.
                if let previous = previousFrameTime, sample.time - previous <= 0.12 {
                    frames.line(to: point)
                } else {
                    frames.move(to: point)
                    framePoints.appendOval(in: NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
                }
                previousFrameTime = sample.time
            case .postedToProcess, .postedToHID:
                posts.appendOval(in: NSRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
            }
        }
        stroke(captured, color: .secondaryLabelColor, width: 1.1)
        stroke(frames, color: Self.frameColor, width: 1.25)
        Self.frameColor.setFill()
        framePoints.fill()
        Self.postColor.setFill()
        posts.fill()
    }

    private func draw(
        _ label: String, at point: NSPoint, font: NSFont, color: NSColor = .secondaryLabelColor
    ) {
        (label as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }
}

/// The axis, legend and range are one row so switching axes or pausing does
/// not move the plot relative to the event table.
final class MonitorTimelineView: NSView {
    let curve = MonitorCurveView()
    private(set) var axis: MonitorAxis = .vertical
    private(set) var duration: CFTimeInterval = 5
    var didChange: (() -> Void)?

    private let durationLabel = NSTextField(labelWithString: "")
    private let decrease = NSButton()
    private let increase = NSButton()

    init() {
        super.init(frame: .zero)
        let title = NSTextField(labelWithString: NSLocalizedString("monitor-scroll-timeline", comment: "Scroll Timeline title"))
        title.font = .systemFont(ofSize: 14, weight: .semibold)

        let axisControl = NSSegmentedControl(
            labels: ["Y", "X"], trackingMode: .selectOne, target: self, action: #selector(changeAxis(_:))
        )
        axisControl.selectedSegment = MonitorAxis.vertical.rawValue
        axisControl.setAccessibilityLabel(NSLocalizedString("monitor-axis", comment: "Axis shown in the timeline"))

        configureStep(decrease, symbol: "−", name: NSLocalizedString("monitor-shorten-window", comment: "Shorten time window"),
                      action: #selector(shorten))
        configureStep(increase, symbol: "+", name: NSLocalizedString("monitor-extend-window", comment: "Extend time window"),
                      action: #selector(extend))
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.alignment = .right
        durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        let header = NSStackView(views: [
            title, axisControl,
            legend(NSLocalizedString("monitor-computed-frames", comment: "Smoothed frames legend"), color: MonitorCurveView.frameColor, dot: false),
            legend(NSLocalizedString("monitor-posted-events", comment: "Posted events legend"), color: MonitorCurveView.postColor, dot: true),
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

    @objc private func changeAxis(_ sender: NSSegmentedControl) {
        guard let axis = MonitorAxis(rawValue: sender.selectedSegment) else { return }
        self.axis = axis
        didChange?()
    }

    @objc private func shorten() { changeDuration(by: -0.5) }
    @objc private func extend() { changeDuration(by: 0.5) }

    private func changeDuration(by step: CFTimeInterval) {
        duration = min(10, max(1, duration + step))
        updateRangeControls()
        didChange?()
    }
}
