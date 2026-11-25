import Cocoa

/// Converts the poster's scroll frames to a two-finger trajectory on the shared device.
@available(macOS 15.0, *)
final class VirtualTrackpadScrollOutput: ScrollOutputSink {
    private typealias Position = VirtualTrackpadTouchReport.Position

    private struct Gesture {
        let moves: AsyncStream<Position>.Continuation
        let task: Task<Void, Never>
        let direction: Double
        var position = CGPoint(x: 0, y: 2603)
        var heldMovement = CGPoint.zero
        var settlingFrames = 3
    }

    private let identity: VirtualTrackpadIdentity
    private let cursorLocation: () -> CGPoint?
    private let naturalScrolling: () -> Bool
    // The producer runs on ScrollDispatchContext's serial queue.
    private var gesture: Gesture?
    private var lastTask: Task<Void, Never>?

    init(
        identity: VirtualTrackpadIdentity,
        cursorLocation: @escaping () -> CGPoint? = { CGEvent(source: nil)?.location },
        naturalScrolling: @escaping () -> Bool = {
            (UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool) ?? true
        }
    ) {
        self.identity = identity
        self.cursorLocation = cursorLocation
        self.naturalScrolling = naturalScrolling
    }

    func frame(y: Double, x: Double, at location: CGPoint) {
        guard Self.isNear(location, cursorLocation()) else {
            finish(cancelled: true)
            return
        }
        guard x.isFinite, y.isFinite else { return }

        let initialFrame = gesture == nil
        if initialFrame {
            guard x != 0 || y != 0 else { return }
            start(at: location)
        }
        guard var active = gesture else { return }
        let scale = 4 * active.direction
        let dx = x * scale
        let dy = y * scale

        if initialFrame || active.settlingFrames > 0 {
            active.heldMovement.x += dx
            active.heldMovement.y += dy
            if !initialFrame {
                active.settlingFrames -= 1
                active.moves.yield(position(at: active.position))
            }
            gesture = active
            return
        }

        let movement = CGPoint(x: dx + active.heldMovement.x, y: dy + active.heldMovement.y)
        var next = CGPoint(x: active.position.x + movement.x, y: active.position.y + movement.y)
        if !Self.contains(next) {
            // Lift and re-center at the edge of the touch surface, as in MirroringScrollLab.
            finish(cancelled: false)
            start(at: location)
            guard let replacement = gesture else { return }
            active = replacement
            active.settlingFrames = 0
            next = CGPoint(x: movement.x, y: 2603 + movement.y)
        }

        active.position = Self.clamp(next)
        active.heldMovement = .zero
        active.moves.yield(position(at: active.position))
        gesture = active
    }

    func end(at location: CGPoint) {
        finish(cancelled: !Self.isNear(location, cursorLocation()))
    }

    private func start(at location: CGPoint) {
        let stream = AsyncStream<Position>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let previous = lastTask
        let task = Task { [identity, cursorLocation] in
            // A new contact may start once the previous task has sent its lift reports.
            await previous?.value
            guard !Task.isCancelled, Self.isNear(location, cursorLocation()) else { return }
            do {
                try await identity.sendTouchGesture(from: Position(y: 2603), moves: stream.stream)
            } catch is CancellationError {
            } catch {
                NSLog("VirtualTrackpadScrollOutput: touch report delivery failed: \(error)")
            }
        }
        lastTask = task
        gesture = Gesture(moves: stream.continuation, task: task, direction: naturalScrolling() ? 1 : -1)
    }

    private func finish(cancelled: Bool) {
        guard let active = gesture else { return }
        gesture = nil
        if cancelled { active.task.cancel() }
        active.moves.finish()
    }

    private func position(at point: CGPoint) -> Position {
        Position(xOffset: Int(point.x.rounded()), y: Int(point.y.rounded()))
    }

    private static func isNear(_ expected: CGPoint, _ actual: CGPoint?) -> Bool {
        guard let actual = actual else { return false }
        return abs(expected.x - actual.x) <= 4 && abs(expected.y - actual.y) <= 4
    }

    private static func contains(_ point: CGPoint) -> Bool {
        (-3100...3134).contains(point.x) && (300...4906).contains(point.y)
    }

    private static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, -3100), 3134), y: min(max(point.y, 300), 4906))
    }
}
