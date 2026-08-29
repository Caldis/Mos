//
//  MouseGestureRecognizer.swift
//  Mos
//
//  Minimal four-direction recognizer used by the mouse gesture navigation preset.
//

import Cocoa

enum MouseGestureDirection: Equatable {
    case up
    case down
    case left
    case right

    var shortcutIdentifier: String {
        switch self {
        case .up:
            return SystemShortcut.missionControl.identifier
        case .down:
            return SystemShortcut.appExpose.identifier
        case .left:
            return SystemShortcut.moveSpaceRight.identifier
        case .right:
            return SystemShortcut.moveSpaceLeft.identifier
        }
    }
}

struct MouseGestureRecognizer {
    static let defaultActivationDistance: CGFloat = 40
    static let defaultClickTolerance: CGFloat = 10
    static let defaultDominanceRatio: CGFloat = 1.2
    static let defaultHorizontalRearmInterval: TimeInterval = 0.16

    private let activationDistance: CGFloat
    private let clickTolerance: CGFloat
    private let dominanceRatio: CGFloat
    private let horizontalRearmInterval: TimeInterval

    private enum LockedAxis {
        case horizontal
        case vertical
    }

    private(set) var displacement = CGPoint.zero
    private(set) var maximumDistanceFromOrigin: CGFloat = 0
    private(set) var recognizedDirection: MouseGestureDirection?
    private var lockedAxis: LockedAxis?
    private var horizontalRemainder: CGFloat = 0
    private var horizontalNeedsRearm = false
    private var lastHorizontalDirection: MouseGestureDirection?
    private var lastMovementTimestamp: TimeInterval?

    init(
        activationDistance: CGFloat = defaultActivationDistance,
        clickTolerance: CGFloat = defaultClickTolerance,
        dominanceRatio: CGFloat = defaultDominanceRatio,
        horizontalRearmInterval: TimeInterval = defaultHorizontalRearmInterval
    ) {
        self.activationDistance = activationDistance
        self.clickTolerance = clickTolerance
        self.dominanceRatio = dominanceRatio
        self.horizontalRearmInterval = horizontalRearmInterval
    }

    mutating func append(
        deltaX: CGFloat,
        deltaY: CGFloat,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> MouseGestureDirection? {
        let movementGap = lastMovementTimestamp.map { max(0, timestamp - $0) }
        lastMovementTimestamp = timestamp
        displacement.x += deltaX
        displacement.y += deltaY
        maximumDistanceFromOrigin = max(
            maximumDistanceFromOrigin,
            hypot(displacement.x, displacement.y)
        )

        switch lockedAxis {
        case .horizontal:
            return appendHorizontalMovement(deltaX, movementGap: movementGap)
        case .vertical:
            return nil
        case nil:
            break
        }

        let horizontal = abs(displacement.x)
        let vertical = abs(displacement.y)
        guard max(horizontal, vertical) >= activationDistance else { return nil }

        if horizontal >= vertical * dominanceRatio {
            lockedAxis = .horizontal
            horizontalRemainder = displacement.x
            return recognizeHorizontalDirectionIfNeeded()
        } else if vertical >= horizontal * dominanceRatio {
            // CGEvent mouse delta Y is positive when moving down.
            lockedAxis = .vertical
            let direction: MouseGestureDirection = displacement.y < 0 ? .up : .down
            recognizedDirection = direction
            return direction
        } else {
            return nil
        }
    }

    private mutating func appendHorizontalMovement(
        _ deltaX: CGFloat,
        movementGap: TimeInterval?
    ) -> MouseGestureDirection? {
        if horizontalNeedsRearm,
           let movementGap,
           movementGap >= horizontalRearmInterval {
            horizontalNeedsRearm = false
            horizontalRemainder = 0
        }

        if horizontalNeedsRearm {
            horizontalRemainder += deltaX
            switch lastHorizontalDirection {
            case .right:
                // Continuing the same swipe must not spill into the next desktop.
                // Only opposite travel is accumulated so reversal remains immediate.
                horizontalRemainder = min(0, horizontalRemainder)
            case .left:
                horizontalRemainder = max(0, horizontalRemainder)
            default:
                horizontalRemainder = 0
            }
            return recognizeHorizontalDirectionIfNeeded()
        }

        horizontalRemainder += deltaX
        return recognizeHorizontalDirectionIfNeeded()
    }

    private mutating func recognizeHorizontalDirectionIfNeeded() -> MouseGestureDirection? {
        guard abs(horizontalRemainder) >= activationDistance else { return nil }

        let direction: MouseGestureDirection = horizontalRemainder < 0 ? .left : .right
        horizontalRemainder = 0
        horizontalNeedsRearm = true
        lastHorizontalDirection = direction
        recognizedDirection = direction
        return direction
    }

    var shouldReplayClick: Bool {
        guard recognizedDirection == nil else { return false }
        return maximumDistanceFromOrigin <= clickTolerance
    }
}
