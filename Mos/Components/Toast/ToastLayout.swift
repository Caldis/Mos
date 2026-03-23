//
//  ToastLayout.swift
//  Mos
//  Toast 布局纯逻辑 - 锚点、方向、位置换算
//

import Cocoa

enum ToastStackDirection {
    case up
    case down
}

enum ToastLayout {

    private static let stackStepRatio: CGFloat = 3.0 / 10.0
    private static let minimumStackAlpha: CGFloat = 0.4
    private static let defaultSnapTolerance: CGFloat = 20.0

    static func defaultAnchorPoint(in visibleFrame: NSRect) -> NSPoint {
        return NSPoint(
            x: visibleFrame.midX,
            y: visibleFrame.origin.y + visibleFrame.height - visibleFrame.height / 5.0
        )
    }

    static func snappedAnchorPoint(_ proposedAnchorPoint: NSPoint, in visibleFrame: NSRect, tolerance: CGFloat = defaultSnapTolerance) -> NSPoint {
        let yTargets = [
            visibleFrame.minY + visibleFrame.height / 5.0,
            visibleFrame.minY + visibleFrame.height * 4.0 / 5.0,
        ]

        return NSPoint(
            x: snappedValue(proposedAnchorPoint.x, targets: [visibleFrame.midX], tolerance: tolerance),
            y: snappedValue(proposedAnchorPoint.y, targets: yTargets, tolerance: tolerance)
        )
    }

    static func stackDirection(for anchorPoint: NSPoint, in visibleFrame: NSRect) -> ToastStackDirection {
        let midY = visibleFrame.origin.y + visibleFrame.height / 2.0
        return anchorPoint.y > midY ? .up : .down
    }

    static func origin(toastSize: NSSize, anchorPoint: NSPoint, direction: ToastStackDirection, offsetFromAnchor: CGFloat) -> NSPoint {
        let x = anchorPoint.x - toastSize.width / 2.0
        let y: CGFloat

        switch direction {
        case .down:
            y = anchorPoint.y - toastSize.height - offsetFromAnchor
        case .up:
            y = anchorPoint.y + offsetFromAnchor
        }

        return NSPoint(x: x, y: y)
    }

    static func anchorPoint(for origin: NSPoint, toastSize: NSSize, direction: ToastStackDirection, offsetFromAnchor: CGFloat) -> NSPoint {
        let x = origin.x + toastSize.width / 2.0
        let y: CGFloat

        switch direction {
        case .down:
            y = origin.y + toastSize.height + offsetFromAnchor
        case .up:
            y = origin.y - offsetFromAnchor
        }

        return NSPoint(x: x, y: y)
    }

    static func stackOffsets(toastSizes: [NSSize], spacing: CGFloat) -> [CGFloat] {
        guard !toastSizes.isEmpty else { return [] }

        var offsets = Array(repeating: CGFloat(0), count: toastSizes.count)
        var offsetFromAnchor: CGFloat = 0

        for index in toastSizes.indices.reversed() {
            offsets[index] = offsetFromAnchor
            offsetFromAnchor += toastSizes[index].height * stackStepRatio + spacing
        }

        return offsets
    }

    static func stackOrigins(toastSizes: [NSSize], anchorPoint: NSPoint, direction: ToastStackDirection, spacing: CGFloat) -> [NSPoint] {
        guard !toastSizes.isEmpty else { return [] }

        return stackOffsets(toastSizes: toastSizes, spacing: spacing).enumerated().map { index, offsetFromAnchor in
            origin(
                toastSize: toastSizes[index],
                anchorPoint: anchorPoint,
                direction: direction,
                offsetFromAnchor: offsetFromAnchor
            )
        }
    }

    static func stackOpacities(count: Int, maxVisibleCount: Int) -> [CGFloat] {
        guard count > 0 else { return [] }

        let clampedMaxVisibleCount = max(maxVisibleCount, 1)
        let denominator = max(clampedMaxVisibleCount - 1, 1)

        return (0..<count).map { index in
            let depth = min(count - 1 - index, clampedMaxVisibleCount - 1)
            let normalizedDepth = CGFloat(depth) / CGFloat(denominator)
            return 1.0 - normalizedDepth * (1.0 - minimumStackAlpha)
        }
    }

    private static func snappedValue(_ value: CGFloat, targets: [CGFloat], tolerance: CGFloat) -> CGFloat {
        var nearestTarget: CGFloat?
        var nearestDistance = tolerance

        for target in targets {
            let distance = abs(target - value)
            guard distance <= tolerance, distance <= nearestDistance else { continue }
            nearestTarget = target
            nearestDistance = distance
        }

        return nearestTarget ?? value
    }
}
