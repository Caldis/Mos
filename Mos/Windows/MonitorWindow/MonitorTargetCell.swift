import Cocoa
import CoreText

private final class MonitorTargetLabel {
    static let font = NSFont.systemFont(ofSize: 11)
    static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    static let iconSize: CGFloat = 12
    static let missing = MonitorTargetLabel(MonitorPresentation.missing)
    static let ellipsis = line("…", font: font)

    let text: String
    let leading: CTLine
    let leadingWidth: CGFloat
    let name: CTLine?
    let nameWidth: CGFloat
    let icon: CGImage?

    init(_ leadingText: String, numeric: Bool = false, name: String? = nil, icon: CGImage? = nil) {
        text = name.map { "\(leadingText) \($0)" } ?? leadingText
        leading = Self.line(leadingText, font: numeric ? Self.numberFont : Self.font)
        leadingWidth = ceil(CTLineGetTypographicBounds(leading, nil, nil, nil))
        self.name = name.map { Self.line($0, font: Self.font) }
        nameWidth = self.name.map { ceil(CTLineGetTypographicBounds($0, nil, nil, nil)) } ?? 0
        self.icon = icon
    }

    private static func line(_ text: String, font: NSFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]))
    }
}

final class MonitorTargetCell: NSTableCellView {
    private var target: MonitorDeliveryTarget?
    private var hasTarget = false
    private var label = MonitorTargetLabel.missing
    private var truncatedName: CTLine?
    private var truncatedWidth: CGFloat?

    override var intrinsicContentSize: NSSize {
        let font = MonitorTargetLabel.font
        let contentHeight = max(ceil(font.ascender - font.descender), MonitorTargetLabel.iconSize)
        return NSSize(width: NSView.noIntrinsicMetric, height: contentHeight + 4)
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            if backgroundStyle != oldValue { needsDisplay = true }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { needsDisplay = true }
    }

    func display(_ target: MonitorDeliveryTarget?, using processes: MonitorProcessLabels) {
        guard !hasTarget || self.target != target else { return }
        self.target = target
        hasTarget = true
        if case .process(let pid)? = target {
            hasTarget = processes.display(pid, in: self)
        } else {
            display(processes.label(for: target))
        }
    }

    fileprivate func display(_ label: MonitorTargetLabel) {
        guard self.label !== label else { return }
        self.label = label
        truncatedWidth = nil
        truncatedName = nil
        toolTip = label.text
        setAccessibilityValue(label.text)
        needsDisplay = true
    }

    fileprivate func display(_ label: MonitorTargetLabel, for pid: Int64) {
        guard target == .process(pid) else { return }
        display(label)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: bounds.insetBy(dx: 4, dy: 0))
        let color = backgroundStyle == .emphasized ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor
        context.setFillColor(color.cgColor)

        let font = MonitorTargetLabel.font
        let baseline = floor(bounds.midY - (font.ascender + font.descender) / 2)
        var x = bounds.minX + 4
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(label.leading, context)
        x += label.leadingWidth + 5

        if let icon = label.icon {
            let size = MonitorTargetLabel.iconSize
            context.draw(icon, in: CGRect(x: x, y: floor(bounds.midY - size / 2), width: size, height: size))
            x += size + 4
        }
        if let name = fittingName(in: bounds.maxX - 4 - x) {
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(name, context)
        }
    }

    private func fittingName(in width: CGFloat) -> CTLine? {
        guard width > 0, let name = label.name else { return nil }
        guard width < label.nameWidth else { return name }
        if truncatedWidth != width {
            truncatedWidth = width
            truncatedName = CTLineCreateTruncatedLine(name, width, .end, MonitorTargetLabel.ellipsis)
        }
        return truncatedName
    }
}

final class MonitorProcessLabels {
    private struct Pending {
        let label: MonitorTargetLabel
        let cells = NSHashTable<MonitorTargetCell>.weakObjects()
    }

    private let queue = DispatchQueue(label: "me.caldis.mos.monitor.processes", qos: .utility)
    private let labels = NSCache<NSNumber, MonitorTargetLabel>()
    private var tapLabels: [MonitorDeliveryTarget: MonitorTargetLabel] = [:]
    private var pending: [pid_t: Pending] = [:]

    init() { labels.countLimit = 256 }

    fileprivate func label(for target: MonitorDeliveryTarget?) -> MonitorTargetLabel {
        guard let target = target else { return .missing }
        if let cached = tapLabels[target] { return cached }
        let label = MonitorTargetLabel(MonitorPresentation.targetName(target))
        tapLabels[target] = label
        return label
    }

    fileprivate func display(_ rawPID: Int64, in cell: MonitorTargetCell) -> Bool {
        let key = NSNumber(value: rawPID)
        if let pid = pid_t(exactly: rawPID), let waiting = pending[pid] {
            waiting.cells.add(cell)
            cell.display(waiting.label)
            return true
        }
        if let label = labels.object(forKey: key) {
            cell.display(label)
            return true
        }

        let placeholder = MonitorTargetLabel(String(rawPID), numeric: true)
        cell.display(placeholder)
        guard let pid = pid_t(exactly: rawPID), pid > 0 else {
            labels.setObject(placeholder, forKey: key)
            return true
        }
        guard pending.count < 64 else { return false }
        let waiting = Pending(label: placeholder)
        waiting.cells.add(cell)
        pending[pid] = waiting

        // PID lookups and icon downsampling run once outside the table's render pass.
        queue.async { [weak self] in
            guard self != nil else { return }
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? app?.executableURL?.lastPathComponent
            let icon = Self.thumbnail(app?.icon)
            DispatchQueue.main.async { [weak self] in
                self?.resolved(pid, name: name, icon: icon)
            }
        }
        return true
    }

    private func resolved(_ pid: pid_t, name: String?, icon: CGImage?) {
        guard let waiting = pending.removeValue(forKey: pid) else { return }
        let label = name.map { MonitorTargetLabel(String(pid), numeric: true, name: $0, icon: icon) } ?? waiting.label
        labels.setObject(label, forKey: NSNumber(value: pid))
        for cell in waiting.cells.allObjects {
            cell.display(label, for: Int64(pid))
        }
    }

    private static func thumbnail(_ image: NSImage?) -> CGImage? {
        let size = Int(MonitorTargetLabel.iconSize * 2)
        var rect = CGRect(x: 0, y: 0, width: size, height: size)
        guard let source = image?.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }
}
