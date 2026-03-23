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
        testSnappedAnchorPointSnapsXAxisToScreenMidline()
        testSnappedAnchorPointLeavesXAxisAloneOutsideTolerance()
        testSnappedAnchorPointSnapsYAxisToScreenFifths()
        print("toast regression tests passed")
    }
}
