import Cocoa
import QuartzCore

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
    private var liveEnd: CFTimeInterval = 5
    private var preparedSize: NSSize = .zero
    private var inputPeak: Double?
    private var outputPeak: Double?
    private let traceClip = CALayer()
    private let trace = CALayer()
    private var traceLayers: [CAShapeLayer] = []
    private var usedLayers = 0
    private let inputTitle = MonitorPresentation.stageName(.captured)
    private let outputTitle = MonitorPresentation.stageName(.posted)
    private lazy var plotStart = max(154, max(textWidth(inputTitle), textWidth(outputTitle)) + 23)
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let verticalColor = NSColor(red: 96.0 / 255.0, green: 198.0 / 255.0, blue: 85.0 / 255.0, alpha: 1)
    static let horizontalColor = NSColor(red: 246.0 / 255.0, green: 191.0 / 255.0, blue: 79.0 / 255.0, alpha: 1)

    override var isFlipped: Bool { true }
    var hasSamples: Bool { !samples.isEmpty }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        traceClip.masksToBounds = true
        trace.shouldRasterize = true
        traceClip.addSublayer(trace)
        layer?.addSublayer(traceClip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layout() {
        super.layout()
        if bounds.size != preparedSize { updateTrace() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        trace.rasterizationScale = window?.backingScaleFactor ?? 1
    }

    func display(
        _ samples: [MonitorTimelineSample],
        range: ClosedRange<CFTimeInterval>,
        selection: CFTimeInterval?,
        waitingForInput: Bool
    ) {
        let durationChanged = range.upperBound - range.lowerBound != self.range.upperBound - self.range.lowerBound
        let traceChanged = !samples.isEmpty || hasSamples || durationChanged || selection != self.selection
        if durationChanged || waitingForInput != self.waitingForInput { needsDisplay = true }

        self.samples = samples
        self.range = range
        liveEnd = range.upperBound
        self.selection = selection
        self.waitingForInput = waitingForInput
        if traceChanged { updateTrace() }
    }

    func advance(to now: CFTimeInterval) {
        guard hasSamples, now > liveEnd else { return }
        liveEnd = now
        // Moving the retained paths leaves the grid and labels in their backing store.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateTraceOffset()
        CATransaction.commit()
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
        guard let input = inputPlot else { return }
        let output = input.offsetBy(dx: 0, dy: input.height)
        drawGrid(inputTitle, peak: inputPeak, in: input)
        drawGrid(outputTitle, peak: outputPeak, in: output)
        drawTimeAxis(in: NSRect(x: input.minX, y: output.maxY + 3, width: input.width, height: 16))

        if waitingForInput {
            let message = NSLocalizedString("monitor-waiting-scroll", comment: "No scroll input received yet")
            drawText(message, at: NSPoint(x: input.midX - textWidth(message) / 2, y: input.maxY - 8),
                     color: .secondaryLabelColor)
        }
    }

    private var inputPlot: NSRect? {
        guard bounds.width >= 320, bounds.height >= 100 else { return nil }
        let width = bounds.width - plotStart - 14
        guard width > 0 else { return nil }
        return NSRect(x: plotStart, y: 8, width: width, height: (bounds.height - 30) / 2)
    }

    private func updateTrace() {
        preparedSize = bounds.size
        guard let input = inputPlot else {
            traceClip.isHidden = true
            return
        }
        var captured: [MonitorTimelineSample] = []
        var output: [MonitorTimelineSample] = []
        for sample in samples where sample.delta.x.isFinite && sample.delta.y.isFinite && range.contains(sample.time) {
            if sample.stage == .captured { captured.append(sample) } else { output.append(sample) }
        }
        let capturedPeak = peak(of: captured)
        let postedPeak = peak(of: output)
        if capturedPeak != inputPeak || postedPeak != outputPeak { needsDisplay = true }
        inputPeak = capturedPeak
        outputPeak = postedPeak

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        traceClip.isHidden = false
        traceClip.frame = NSRect(x: input.minX, y: input.minY, width: input.width, height: input.height * 2)
        trace.setAffineTransform(.identity)
        trace.frame = traceClip.bounds
        usedLayers = 0

        let upper = NSRect(origin: .zero, size: input.size)
        let lower = upper.offsetBy(dx: 0, dy: upper.height)
        if let capturedPeak = capturedPeak {
            setSamples(captured, axis: .vertical, peak: capturedPeak, in: upper)
            setSamples(captured, axis: .horizontal, peak: capturedPeak, in: upper)
        }
        if let postedPeak = postedPeak {
            setPhaseMarkers(output, in: lower)
            // The longer X tick remains visible on either side of a coincident Y tick.
            setSamples(output, axis: .horizontal, peak: postedPeak, in: lower)
            setSamples(output, axis: .vertical, peak: postedPeak, in: lower)
        }
        setSelection(in: upper.union(lower))
        for unused in traceLayers.dropFirst(usedLayers) { unused.path = nil }
        updateTraceOffset()
        CATransaction.commit()
    }

    private func updateTraceOffset() {
        let width = traceClip.bounds.width
        let offset = width * CGFloat((range.upperBound - liveEnd) / (range.upperBound - range.lowerBound))
        trace.setAffineTransform(CGAffineTransform(translationX: offset, y: 0))
    }

    private func peak(of points: [MonitorTimelineSample]) -> Double? {
        points.isEmpty ? nil : points.reduce(1.0) { max($0, abs($1.delta.x), abs($1.delta.y)) }
    }

    private func drawGrid(_ title: String, peak: Double?, in plot: NSRect) {
        drawText(title, at: NSPoint(x: 13, y: plot.midY - 15), color: .labelColor, weight: .medium)
        if let peak = peak {
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
    }

    private func setPhaseMarkers(_ points: [MonitorTimelineSample], in plot: NSRect) {
        let began = CGMutablePath()
        let ended = CGMutablePath()
        for sample in points where sample.stage == .posted {
            guard sample.phase == 1 || sample.phase == 4 else { continue }
            let marker = sample.phase == 1 ? began : ended
            let x = position(of: sample.time, in: plot)
            marker.move(to: NSPoint(x: x, y: plot.minY + 4))
            marker.addLine(to: NSPoint(x: x, y: plot.maxY - 4))
        }
        setPath(began, color: .systemRed, width: 1)
        setPath(ended, color: .systemPurple, width: 1, dashed: true)
    }

    private func setSamples(
        _ points: [MonitorTimelineSample], axis: MonitorAxis, peak: Double, in plot: NSRect
    ) {
        let stems = CGMutablePath()
        let momentumStems = CGMutablePath()
        let ticks = CGMutablePath()
        let momentumTicks = CGMutablePath()
        let horizontal = axis == .horizontal
        let color = horizontal ? Self.horizontalColor : Self.verticalColor
        let scale = plot.height / 2 - 7
        let tickHalfWidth: CGFloat = horizontal ? 2.8 : 1.8

        for sample in points {
            let value = sample.delta[axis]
            // Zero-displacement marks stack along the baseline during single-axis scrolling.
            guard value != 0 else { continue }
            let x = position(of: sample.time, in: plot)
            let y = plot.midY - CGFloat(value / peak) * scale
            switch sample.stage {
            case .captured, .frame:
                // Keep each input and computed frame as the original discrete stem.
                let path = sample.hasMomentum ? momentumStems : stems
                path.move(to: NSPoint(x: x, y: plot.midY))
                path.addLine(to: NSPoint(x: x, y: y))
            case .posted:
                let tick = sample.hasMomentum ? momentumTicks : ticks
                tick.move(to: NSPoint(x: x - tickHalfWidth, y: y))
                tick.addLine(to: NSPoint(x: x + tickHalfWidth, y: y))
            }
        }

        // The stems share a baseline, so dash gaps would line up across samples.
        setPath(stems, color: color, width: 1.5)
        setPath(momentumStems, color: color.withAlphaComponent(0.7), width: 1.5)
        setPath(ticks, color: color, width: 1.1)
        setPath(momentumTicks, color: color.withAlphaComponent(0.7), width: 1.1)
    }

    private func position(of time: CFTimeInterval, in rect: NSRect) -> CGFloat {
        let fraction = (time - range.lowerBound) / (range.upperBound - range.lowerBound)
        return rect.minX + rect.width * CGFloat(fraction)
    }

    private func setSelection(in rect: NSRect) {
        guard let selection = selection, range.contains(selection) else { return }
        let path = CGMutablePath()
        let x = position(of: selection, in: rect)
        path.move(to: NSPoint(x: x, y: rect.minY))
        path.addLine(to: NSPoint(x: x, y: rect.maxY))
        setPath(path, color: NSColor.labelColor.withAlphaComponent(0.6), width: 0.75)
    }

    private func setPath(_ path: CGPath, color: NSColor, width: CGFloat, dashed: Bool = false) {
        guard !path.isEmpty else { return }
        if usedLayers == traceLayers.count {
            let shape = CAShapeLayer()
            shape.fillColor = nil
            trace.addSublayer(shape)
            traceLayers.append(shape)
        }
        let shape = traceLayers[usedLayers]
        usedLayers += 1
        shape.frame = trace.bounds
        shape.path = path
        shape.strokeColor = color.cgColor
        shape.lineWidth = width
        shape.lineDashPattern = dashed ? [2, 2] : nil
    }

    private func drawTimeAxis(in axis: NSRect) {
        drawText("−\(scaleLabel(range.upperBound - range.lowerBound)) s", at: axis.origin, color: .secondaryLabelColor)
        let now = "0 s"
        drawText(now, at: NSPoint(x: axis.maxX - textWidth(now), y: axis.minY), color: .secondaryLabelColor)
    }

    private func scaleLabel(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? ""
    }

    private func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
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
    private let decrease = MonitorRoundButton(style: .neutral)
    private let increase = MonitorRoundButton(style: .neutral)
    private var animation: Timer?

    init() {
        super.init(frame: .zero)
        MonitorStyle.styleSection(self)
        let title = MonitorStyle.sectionHeader(NSLocalizedString("monitor-scroll-timeline", comment: "Scroll Timeline title"))

        configureStep(decrease, symbol: "−", name: NSLocalizedString("monitor-shorten-window", comment: "Shorten time window"),
                      action: #selector(shorten))
        configureStep(increase, symbol: "+", name: NSLocalizedString("monitor-extend-window", comment: "Extend time window"),
                      action: #selector(extend))
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.alignment = .right
        durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        let header = NSStackView(views: [
            title,
            legend("Y", color: MonitorCurveView.verticalColor),
            legend("X", color: MonitorCurveView.horizontalColor),
            legend(NSLocalizedString("monitor-computed-frames", comment: "Smoothed frames legend"), color: .secondaryLabelColor),
            legend(NSLocalizedString("monitor-posted-events", comment: "Posted events legend"), color: .secondaryLabelColor, markWidth: 5),
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
            header.topAnchor.constraint(equalTo: topAnchor, constant: MonitorStyle.contentVerticalInset),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MonitorStyle.padding),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MonitorStyle.padding),
            curve.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            curve.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            curve.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            curve.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -MonitorStyle.contentVerticalInset),
        ])
        updateRangeControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init()") }

    deinit { animation?.invalidate() }

    func animateLiveCurve(_ active: Bool) {
        guard active, let window = window, window.isVisible, !window.isMiniaturized else {
            animation?.invalidate()
            animation = nil
            return
        }
        guard animation == nil else { return }

        // The playhead advances between recorder drains using the same clock
        // as the samples. Each tick uses the plot's current snapshot.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let view = self else { return }
            view.curve.advance(to: CACurrentMediaTime())
        }
        timer.tolerance = 0.001
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }

    private func configureStep(_ button: NSButton, symbol: String, name: String, action: Selector) {
        button.title = symbol
        button.target = self
        button.action = action
        button.toolTip = name
        button.setAccessibilityLabel(name)
    }

    private func legend(_ name: String, color: NSColor, markWidth: CGFloat = 13) -> NSStackView {
        let image = NSImage(size: NSSize(width: 15, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(rect: NSRect(x: rect.midX - markWidth / 2, y: rect.midY - 0.6, width: markWidth, height: 1.2)).fill()
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
