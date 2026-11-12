import Cocoa

// 让纯回归可以单独编译 ToastContentView，而不依赖完整 App 目标。
struct Toast {
    enum Style: CaseIterable {
        case info
        case success
        case warning
        case error
    }
}

final class ToastManager {
    static let shared = ToastManager()

    func snappedOrigin(for panel: NSPanel, proposedOrigin: NSPoint) -> NSPoint {
        return proposedOrigin
    }

    func saveAnchor(for panel: NSPanel) {}
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func expectEqual(_ lhs: CGFloat, _ rhs: CGFloat, _ message: String, epsilon: CGFloat = 0.001) {
    expect(abs(lhs - rhs) <= epsilon, message + " (lhs: \(lhs), rhs: \(rhs))")
}

private func testDefaultAnchorPoint() {
    let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
    let point = ToastLayout.defaultAnchorPoint(in: visibleFrame)

    expectEqual(point.x, 700, "默认锚点应水平居中")
    expectEqual(point.y, 690, "默认锚点应位于可见区域顶部下方 1/5")
}

private func testStackDirection() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)

    expect(ToastLayout.stackDirection(for: NSPoint(x: 500, y: 700), in: visibleFrame) == .up,
           "上半屏锚点应向上堆叠")
    expect(ToastLayout.stackDirection(for: NSPoint(x: 500, y: 120), in: visibleFrame) == .down,
           "下半屏锚点应向下堆叠")
}

private func testOriginAndAnchorAreInverse() {
    let anchor = NSPoint(x: 600, y: 500)
    let size = NSSize(width: 320, height: 48)
    let offset: CGFloat = 96

    let downOrigin = ToastLayout.origin(
        toastSize: size,
        anchorPoint: anchor,
        direction: .down,
        offsetFromAnchor: offset
    )
    let restoredDownAnchor = ToastLayout.anchorPoint(
        for: downOrigin,
        toastSize: size,
        direction: .down,
        offsetFromAnchor: offset
    )
    expectEqual(restoredDownAnchor.x, anchor.x, "向下堆叠时 anchor x 应可逆")
    expectEqual(restoredDownAnchor.y, anchor.y, "向下堆叠时 anchor y 应可逆")

    let upOrigin = ToastLayout.origin(
        toastSize: size,
        anchorPoint: anchor,
        direction: .up,
        offsetFromAnchor: offset
    )
    let restoredUpAnchor = ToastLayout.anchorPoint(
        for: upOrigin,
        toastSize: size,
        direction: .up,
        offsetFromAnchor: offset
    )
    expectEqual(restoredUpAnchor.x, anchor.x, "向上堆叠时 anchor x 应可逆")
    expectEqual(restoredUpAnchor.y, anchor.y, "向上堆叠时 anchor y 应可逆")
}

private func testToastVisibilityState() {
    let entries = [
        ToastVisibilityEntry(id: 0, message: "oldest", isDismissing: true),
        ToastVisibilityEntry(id: 1, message: "active", isDismissing: false),
        ToastVisibilityEntry(id: 2, message: "newest", isDismissing: false),
    ]

    expect(ToastVisibilityRules.containsVisibleMessage("oldest", in: entries),
           "淡出中的 toast 仍然可见，应继续参与去重")
    expect(ToastVisibilityRules.activeCount(in: entries) == 2,
           "activeCount 应忽略淡出中的 toast")
    expect(ToastVisibilityRules.oldestActiveIndex(in: entries) == 1,
           "淘汰最旧 active toast 时应跳过已在淡出的条目")
}

private func testStackOriginsAvoidExistingToasts() {
    let anchor = NSPoint(x: 600, y: 500)
    let toastSizes = [
        NSSize(width: 320, height: 44),
        NSSize(width: 320, height: 48),
        NSSize(width: 320, height: 52),
    ]

    let origins = ToastLayout.stackOrigins(
        toastSizes: toastSizes,
        anchorPoint: anchor,
        direction: .down,
        spacing: 8
    )

    expect(origins.count == toastSizes.count, "stackOrigins 应返回与输入数量一致的位置")
    expectEqual(origins[2].y, 448, "最新 toast 应贴近锚点")
    expectEqual(origins[1].y, 428.4, "第二条 toast 应按 0.3 比例形成更紧的层叠")
    expectEqual(origins[0].y, 410.0, "第三条 toast 应继续按 0.3 比例后退")
}

private func testStackOffsetsMatchLayeredSpacing() {
    let toastSizes = [
        NSSize(width: 320, height: 44),
        NSSize(width: 320, height: 48),
        NSSize(width: 320, height: 52),
    ]

    let offsets = ToastLayout.stackOffsets(toastSizes: toastSizes, spacing: 8)

    expect(offsets.count == toastSizes.count, "stackOffsets 应返回与输入数量一致的偏移")
    expectEqual(offsets[0], 46.0, "最底层 toast 的 offset 应累计所有更靠近锚点的层叠步进")
    expectEqual(offsets[1], 23.6, "中间层 toast 的 offset 应只累计紧邻前层的层叠步进")
    expectEqual(offsets[2], 0.0, "最顶层 toast 应始终紧贴锚点")
}

private func testStackOpacitiesFadeByLayer() {
    let opacities = ToastLayout.stackOpacities(count: 4, maxVisibleCount: 4)

    expect(opacities.count == 4, "stackOpacities 应返回与输入数量一致的透明度")
    expectEqual(opacities[0], 0.4, "最底层 toast 应最淡")
    expectEqual(opacities[1], 0.6, "次底层 toast 应逐级变实")
    expectEqual(opacities[2], 0.8, "次顶层 toast 应接近不透明")
    expectEqual(opacities[3], 1.0, "最顶层 toast 应保持完全不透明")
}

private func testInfoStyleProvidesAccentColor() {
    expect(ToastContentView.accentColor(for: .info) != nil,
           "Info 类型应提供强调色，以支持 ribbon 显示")
}

private func findMessageLabel(in view: NSView) -> NSTextField? {
    if let textField = view as? NSTextField {
        return textField
    }
    for subview in view.subviews {
        if let label = findMessageLabel(in: subview) {
            return label
        }
    }
    return nil
}

private func testToastContentViewNilWrapWidthUsesSingleLineTruncation() {
    let contentView = ToastContentView(
        message: "Long toast message that should wrap to multiple lines when expanded.",
        icon: nil,
        accentColor: nil,
        showsAccentIndicator: true,
        wrapWidth: nil
    )

    guard let messageLabel = findMessageLabel(in: contentView) else {
        fputs("FAIL: 未找到 toast 消息文本控件\n", stderr)
        exit(1)
    }

    expect(messageLabel.maximumNumberOfLines == 1, "未提供 wrapWidth 时应默认为单行")
    expect(messageLabel.lineBreakMode == .byTruncatingTail, "未提供 wrapWidth 时应默认为尾部截断")
}

private func testDefaultWrapWidthStorageDefaultsToFourHundred() {
    let suiteName = "\(Bundle.main.bundleIdentifier ?? "app").toast"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removeObject(forKey: "defaultWrapWidth")

    let storage = ToastStorage()

    expectEqual(storage.defaultWrapWidth, 400, "defaultWrapWidth 默认值应为 400")
}

private func testDefaultWrapWidthStorageClampsNegativeValues() {
    let suiteName = "\(Bundle.main.bundleIdentifier ?? "app").toast"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removeObject(forKey: "defaultWrapWidth")

    let storage = ToastStorage()
    storage.defaultWrapWidth = -120

    expectEqual(storage.defaultWrapWidth, 0, "defaultWrapWidth 不应接受负值")
}

private func testDefaultWrapWidthStoragePreservesPositiveValues() {
    let suiteName = "\(Bundle.main.bundleIdentifier ?? "app").toast"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removeObject(forKey: "defaultWrapWidth")

    let storage = ToastStorage()
    storage.defaultWrapWidth = 420

    expectEqual(storage.defaultWrapWidth, 420, "defaultWrapWidth 应保留正值")
}

private func testZeroWrapWidthUsesSingleLineTruncation() {
    let contentView = ToastContentView(
        message: "Long toast message that should stay on a single line when wrap width is zero.",
        icon: nil,
        accentColor: nil,
        showsAccentIndicator: true,
        wrapWidth: 0
    )

    guard let messageLabel = findMessageLabel(in: contentView) else {
        fputs("FAIL: 未找到 toast 消息文本控件\n", stderr)
        exit(1)
    }

    expect(messageLabel.maximumNumberOfLines == 1, "wrapWidth = 0 时应强制单行")
    expect(messageLabel.lineBreakMode == .byTruncatingTail, "wrapWidth = 0 时应保持尾部截断")
}

private func testZeroWrapWidthCanUseWiderSingleLineLimit() {
    let contentView = ToastContentView(
        message: "Hello, this is a toast message 213123123123123123231 and it should stay on one line without the old 350pt cap.",
        icon: ToastContentView.defaultIcon(for: .info),
        accentColor: ToastContentView.accentColor(for: .info),
        showsAccentIndicator: true,
        wrapWidth: 0,
        singleLineMaxWidth: 800
    )

    contentView.layoutSubtreeIfNeeded()

    expect(contentView.fittingSize.width > 500, "单行模式应允许使用更宽的单行上限，而不是固定截断在 350pt")
}

private func testPositiveWrapWidthUsesUnlimitedLines() {
    let contentView = ToastContentView(
        message: "Long toast message that should wrap to multiple lines when wrap width is positive.",
        icon: nil,
        accentColor: nil,
        showsAccentIndicator: true,
        wrapWidth: 350
    )

    guard let messageLabel = findMessageLabel(in: contentView) else {
        fputs("FAIL: 未找到 toast 消息文本控件\n", stderr)
        exit(1)
    }

    expect(messageLabel.maximumNumberOfLines == 0, "正 wrapWidth 时应取消行数限制")
    expect(messageLabel.lineBreakMode == .byWordWrapping, "正 wrapWidth 时应启用自动换行")
    expectEqual(messageLabel.preferredMaxLayoutWidth, 350, "正 wrapWidth 时应传递到 preferredMaxLayoutWidth")
}

private func testPositiveWrapWidthKeepsReadableWidth() {
    let contentView = ToastContentView(
        message: "This is a long toast message that should wrap across multiple lines when full text is enabled.",
        icon: ToastContentView.defaultIcon(for: .warning),
        accentColor: ToastContentView.accentColor(for: .warning),
        showsAccentIndicator: true,
        wrapWidth: 350
    )

    contentView.layoutSubtreeIfNeeded()

    expect(contentView.fittingSize.width >= 250, "正 wrapWidth 时 toast 宽度不应塌缩到只剩图标")
}

private func testNegativeWrapWidthFallsBackToSingleLine() {
    let contentView = ToastContentView(
        message: "Long toast message that should still stay single-line when wrap width is negative.",
        icon: nil,
        accentColor: nil,
        showsAccentIndicator: true,
        wrapWidth: -1
    )

    guard let messageLabel = findMessageLabel(in: contentView) else {
        fputs("FAIL: 未找到 toast 消息文本控件\n", stderr)
        exit(1)
    }

    expect(messageLabel.maximumNumberOfLines == 1, "负 wrapWidth 应回退到单行")
    expect(messageLabel.lineBreakMode == .byTruncatingTail, "负 wrapWidth 应保持尾部截断")
}

private func testSnappedAnchorPointSnapsXAxisToScreenMidline() {
    let visibleFrame = NSRect(x: 80, y: 40, width: 1200, height: 800)
    let proposedAnchor = NSPoint(x: visibleFrame.midX - 19, y: 420)

    let snappedAnchor = ToastLayout.snappedAnchorPoint(proposedAnchor, in: visibleFrame)

    expectEqual(snappedAnchor.x, visibleFrame.midX, "x 轴在中线 20px 范围内时应吸附到中线")
    expectEqual(snappedAnchor.y, proposedAnchor.y, "仅 x 轴命中吸附时不应改动 y")
}

private func testSnappedAnchorPointLeavesXAxisAloneOutsideTolerance() {
    let visibleFrame = NSRect(x: 80, y: 40, width: 1200, height: 800)
    let proposedAnchor = NSPoint(x: visibleFrame.midX + 21, y: 420)

    let snappedAnchor = ToastLayout.snappedAnchorPoint(proposedAnchor, in: visibleFrame)

    expectEqual(snappedAnchor.x, proposedAnchor.x, "x 轴超过 20px 容差时不应吸附")
    expectEqual(snappedAnchor.y, proposedAnchor.y, "未命中任何吸附点时不应改动 y")
}

private func testSnappedAnchorPointSnapsYAxisToScreenFifths() {
    let visibleFrame = NSRect(x: 80, y: 40, width: 1200, height: 800)
    let lowerProposedAnchor = NSPoint(x: 500, y: visibleFrame.minY + visibleFrame.height / 5.0 + 19)
    let upperProposedAnchor = NSPoint(x: 500, y: visibleFrame.minY + visibleFrame.height * 4.0 / 5.0 - 18)

    let lowerSnappedAnchor = ToastLayout.snappedAnchorPoint(lowerProposedAnchor, in: visibleFrame)
    let upperSnappedAnchor = ToastLayout.snappedAnchorPoint(upperProposedAnchor, in: visibleFrame)

    expectEqual(lowerSnappedAnchor.y, visibleFrame.minY + visibleFrame.height / 5.0, "y 轴应支持吸附到 1/5 位置")
    expectEqual(upperSnappedAnchor.y, visibleFrame.minY + visibleFrame.height * 4.0 / 5.0, "y 轴应支持吸附到 4/5 位置")
    expectEqual(lowerSnappedAnchor.x, lowerProposedAnchor.x, "仅 y 轴命中吸附时不应改动 x")
    expectEqual(upperSnappedAnchor.x, upperProposedAnchor.x, "仅 y 轴命中吸附时不应改动 x")
}

@main
struct ToastRegressionTests {
    static func main() {
        testDefaultAnchorPoint()
        testStackDirection()
        testOriginAndAnchorAreInverse()
        testToastVisibilityState()
        testStackOriginsAvoidExistingToasts()
        testStackOffsetsMatchLayeredSpacing()
        testStackOpacitiesFadeByLayer()
        testInfoStyleProvidesAccentColor()
        testToastContentViewNilWrapWidthUsesSingleLineTruncation()
        testDefaultWrapWidthStorageDefaultsToFourHundred()
        testDefaultWrapWidthStorageClampsNegativeValues()
        testDefaultWrapWidthStoragePreservesPositiveValues()
        testZeroWrapWidthUsesSingleLineTruncation()
        testZeroWrapWidthCanUseWiderSingleLineLimit()
        testPositiveWrapWidthUsesUnlimitedLines()
        testPositiveWrapWidthKeepsReadableWidth()
        testNegativeWrapWidthFallsBackToSingleLine()
        testSnappedAnchorPointSnapsXAxisToScreenMidline()
        testSnappedAnchorPointLeavesXAxisAloneOutsideTolerance()
        testSnappedAnchorPointSnapsYAxisToScreenFifths()
        print("toast regression tests passed")
    }
}
