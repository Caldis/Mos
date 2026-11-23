import Cocoa

final class MonitorCurveView: NSView {
    private var samples: [ScrollMonitorSample] = []
    private var end: CFTimeInterval = 0
    private var duration: CFTimeInterval = 5
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    override var isFlipped: Bool { true }

    func update(samples: [ScrollMonitorSample], end: CFTimeInterval, duration: CFTimeInterval) {
        guard !samples.isEmpty || !self.samples.isEmpty || duration != self.duration else { return }
        self.samples = samples
        self.end = end
        self.duration = duration
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width >= 320, bounds.height >= 154 else { return }

        let panel = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        NSColor.textBackgroundColor.setFill()
        panel.fill()
        stroke(panel, color: NSColor.labelColor.withAlphaComponent(0.15), width: 1)

        let lanes = ScrollMonitorLane.allCases
        let plotStart: CGFloat = 154
        let plotWidth = bounds.width - plotStart - 14
        let lanesArea = NSRect(x: 0, y: 8, width: bounds.width, height: bounds.height - 54)
        let laneHeight = lanesArea.height / CGFloat(lanes.count)

        for (index, lane) in lanes.enumerated() {
            let plot = NSRect(
                x: plotStart,
                y: lanesArea.minY + CGFloat(index) * laneHeight,
                width: plotWidth,
                height: laneHeight
            )
            draw(lane, in: plot)
        }

        let timeAxis = NSRect(x: plotStart, y: lanesArea.maxY + 3, width: plotWidth, height: 16)
        drawTimeAxis(in: timeAxis)
        drawLegend(at: NSPoint(x: plotStart, y: timeAxis.maxY + 4))
    }

    private func draw(_ lane: ScrollMonitorLane, in plot: NSRect) {
        let points = samples.filter { $0.stage.lane == lane && $0.x.isFinite && $0.y.isFinite }
        let peak = points.reduce(1.0) { max($0, abs($1.x), abs($1.y)) }
        drawText(lane.title, at: NSPoint(x: 13, y: plot.midY - 15), color: .labelColor, weight: .medium)
        if !points.isEmpty {
            drawText("±\(numberFormatter.string(from: NSNumber(value: peak)) ?? "") pt",
                     at: NSPoint(x: 13, y: plot.midY + 1), color: .secondaryLabelColor)
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

        let vertical = NSBezierPath()
        let horizontal = NSBezierPath()
        let momentum = NSBezierPath()
        let horizontalMomentum = NSBezierPath()
        let began = NSBezierPath()
        let ended = NSBezierPath()
        let scale = plot.height / 2 - 7
        let start = end - duration

        for point in points {
            let x = plot.minX + CGFloat((point.time - start) / duration) * plot.width
            let fields = point.fields
            let hasMomentum = (fields?.momentum ?? 0) != 0
            if lane == .output, let phase = fields?.phase, phase == 1 || phase == 4 {
                let marker = phase == 1 ? began : ended
                marker.move(to: NSPoint(x: x, y: plot.minY + 4))
                marker.line(to: NSPoint(x: x, y: plot.maxY - 4))
            }
            if point.y != 0 {
                let path = hasMomentum ? momentum : vertical
                path.move(to: NSPoint(x: x, y: plot.midY))
                path.line(to: NSPoint(x: x, y: plot.midY - CGFloat(point.y / peak) * scale))
            }
            if point.x != 0 {
                let path = hasMomentum ? horizontalMomentum : horizontal
                let axisX = min(x + 2, plot.maxX)
                path.move(to: NSPoint(x: axisX, y: plot.midY))
                path.line(to: NSPoint(x: axisX, y: plot.midY - CGFloat(point.x / peak) * scale))
            }
        }
        stroke(began, color: .systemRed, width: 1)
        stroke(ended, color: .systemPurple, width: 1, dashed: true)
        stroke(vertical, color: .systemBlue, width: 1.5)
        stroke(horizontal, color: .systemTeal, width: 1.5, dashed: true)
        stroke(momentum, color: .systemOrange, width: 1.5)
        stroke(horizontalMomentum, color: .systemOrange, width: 1.5, dashed: true)
    }

    private func drawTimeAxis(in axis: NSRect) {
        let seconds = numberFormatter.string(from: NSNumber(value: duration)) ?? ""
        drawText("−\(seconds) s", at: axis.origin, color: .secondaryLabelColor)
        let now = "0 s"
        let width = textWidth(now)
        drawText(now, at: NSPoint(x: axis.maxX - width, y: axis.minY), color: .secondaryLabelColor)
    }

    private func drawLegend(at origin: NSPoint) {
        let items: [(String, NSColor, Bool)] = [
            (NSLocalizedString("monitor-vertical-axis", comment: "Scroll timeline legend: vertical displacement"), .systemBlue, false),
            (NSLocalizedString("monitor-horizontal-axis", comment: "Scroll timeline legend: horizontal displacement"), .systemTeal, true),
            (NSLocalizedString("monitor-momentum", comment: "Scroll timeline legend: momentum"), .systemOrange, false),
            (NSLocalizedString("monitor-gesture-start", comment: "Scroll timeline legend: gesture start"), .systemRed, false),
            (NSLocalizedString("monitor-gesture-end", comment: "Scroll timeline legend: gesture end"), .systemPurple, true),
        ]
        var x = origin.x
        for (title, color, dashed) in items {
            let swatch = NSBezierPath()
            swatch.move(to: NSPoint(x: x, y: origin.y + 7))
            swatch.line(to: NSPoint(x: x + 12, y: origin.y + 7))
            stroke(swatch, color: color, width: 1.5, dashed: dashed)
            drawText(title, at: NSPoint(x: x + 17, y: origin.y), color: .secondaryLabelColor)
            x += 30 + textWidth(title)
        }
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

private extension ScrollMonitorLane {
    var title: String {
        switch self {
        case .input: return NSLocalizedString("monitor-captured", comment: "Scroll timeline lane for raw input")
        case .frame: return NSLocalizedString("monitor-computed-frames", comment: "Scroll timeline lane for smoothed frames")
        case .output: return NSLocalizedString("monitor-posted-events", comment: "Scroll timeline lane for events posted by Mos")
        }
    }
}
