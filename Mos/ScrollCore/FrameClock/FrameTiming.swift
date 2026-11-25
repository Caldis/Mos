import Foundation

struct FrameTiming {
    private static let referenceRate = 60.0
    static let referenceInterval = 1 / referenceRate
    static let legacy = FrameTiming(interval: referenceInterval, enabled: false)

    let scale: Double

    init(interval: CFTimeInterval, enabled: Bool) {
        if enabled && interval.isFinite && interval > 0 {
            scale = min(max(interval, 1.0 / 480.0), 0.1) * Self.referenceRate
        } else {
            scale = 1
        }
    }

    // Apply the same fraction of decay over the same elapsed time.
    func fraction(_ baseline: Double) -> Double {
        guard scale != 1, baseline > 0, baseline < 1 else { return baseline }
        return -expm1(log1p(-baseline) * scale)
    }
}

struct ScrollPointAccumulator {
    private var targetPID: pid_t?
    private var remainder = (y: 0.0, x: 0.0)

    mutating func quantize(_ delta: (y: Double, x: Double), for pid: pid_t) -> (y: Double, x: Double) {
        if targetPID != pid {
            targetPID = pid
            remainder = (0, 0)
        }
        // Quartz PointDelta stores whole points. Carry each axis's fractional part to the next frame.
        let y = Self.wholePoints(delta.y, remainder: &remainder.y)
        let x = Self.wholePoints(delta.x, remainder: &remainder.x)
        return (y, x)
    }

    private static func wholePoints(_ delta: Double, remainder: inout Double) -> Double {
        let sum = delta + remainder
        guard sum.isFinite else {
            remainder = 0
            return 0
        }
        let points = sum.rounded(.towardZero)
        remainder = sum - points
        return points
    }
}
