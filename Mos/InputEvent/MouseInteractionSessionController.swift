//
//  MouseInteractionSessionController.swift
//  Mos
//  管理 synthetic 鼠标拖拽会话与虚拟修饰键的鼠标交互传播
//

import Cocoa

enum SyntheticMouseTarget: Equatable {
    case left
    case right
    case other(buttonNumber: Int64)
}

enum PhysicalMouseTarget: Equatable {
    case none
    case left
    case right
    case other(buttonNumber: Int64)
}

final class MouseInteractionSessionController {
    static let shared = MouseInteractionSessionController()

    private static let motionEventMask: CGEventMask =
        (CGEventMask(1 << CGEventType.mouseMoved.rawValue)) |
        (CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.otherMouseDragged.rawValue))

    private static let motionEventCallback: CGEventTapCallBack = { _, type, event, _ in
        MouseInteractionSessionController.shared.handleMotionTapEvent(type: type, event: event)
    }

    private let startMotionTapOverride: (() -> Void)?
    private let stopMotionTapOverride: (() -> Void)?
    private(set) var isMotionTapRunning = false
    private var activeSessions: [UUID: SyntheticMouseTarget] = [:]
    private var dominantTarget: SyntheticMouseTarget?
    private var motionInterceptor: Interceptor?
    private var testStartMotionTap: (() -> Void)?
    private var testStopMotionTap: (() -> Void)?
    var activeSessionCount: Int { activeSessions.count }
    private var hasActiveVirtualModifiers: Bool { InputProcessor.shared.activeModifierFlags != 0 }

    // MARK: - Gesture Motion Support
    /// 手势运动事件处理回调 (由 GestureProcessor 注册, 在 motion tap 事件中调用)
    var gestureMotionHandler: ((CGEvent) -> Void)?
    /// 是否有活跃的手势追踪会话
    private(set) var hasActiveGesture = false

    /// 设置手势追踪状态 (由 GestureProcessor 调用)
    func setGestureTracking(_ active: Bool) {
        hasActiveGesture = active
        refreshMotionTapState()
    }

    init(
        startMotionTap: (() -> Void)? = nil,
        stopMotionTap: (() -> Void)? = nil
    ) {
        self.startMotionTapOverride = startMotionTap
        self.stopMotionTapOverride = stopMotionTap
    }

    static func dominantSyntheticTarget(from targets: [SyntheticMouseTarget]) -> SyntheticMouseTarget? {
        guard !targets.isEmpty else { return nil }
        return targets.min(by: { lhs, rhs in
            syntheticPriority(of: lhs) < syntheticPriority(of: rhs)
        })
    }

    static func effectiveTarget(
        physical: PhysicalMouseTarget,
        synthetic: SyntheticMouseTarget?
    ) -> SyntheticMouseTarget? {
        guard let synthetic else {
            switch physical {
            case .none:
                return nil
            case .left:
                return .left
            case .right:
                return .right
            case .other(let buttonNumber):
                return .other(buttonNumber: buttonNumber)
            }
        }

        let physicalAsSynthetic: SyntheticMouseTarget? = {
            switch physical {
            case .none:
                return nil
            case .left:
                return .left
            case .right:
                return .right
            case .other(let buttonNumber):
                return .other(buttonNumber: buttonNumber)
            }
        }()

        guard let physicalAsSynthetic else { return synthetic }
        return syntheticPriority(of: physicalAsSynthetic) <= syntheticPriority(of: synthetic) ? physicalAsSynthetic : synthetic
    }

    @discardableResult
    func beginSession(target: SyntheticMouseTarget) -> UUID {
        let sessionID = UUID()
        activeSessions[sessionID] = target
        recomputeDominantTarget()
        refreshMotionTapState()
        return sessionID
    }

    func endSession(id: UUID) {
        guard activeSessions.removeValue(forKey: id) != nil else { return }
        recomputeDominantTarget()
        refreshMotionTapState()
    }

    func clearAllSessions() {
        guard !activeSessions.isEmpty || isMotionTapRunning else { return }
        activeSessions.removeAll()
        dominantTarget = nil
        refreshMotionTapState()
    }

    func refreshMotionTapState() {
        if shouldKeepMotionTapRunning {
            if !isMotionTapRunning {
                startMotionTap()
            }
            return
        }

        guard isMotionTapRunning else { return }
        stopMotionTap()
    }

    func rewriteMouseInteractionEvent(_ event: CGEvent) {
        let shouldApplyVirtualModifiers = hasActiveVirtualModifiers
        let synthetic = dominantTarget

        guard synthetic != nil || shouldApplyVirtualModifiers else { return }

        if let synthetic {
            let physical = Self.physicalTarget(from: event)
            if let effective = Self.effectiveTarget(physical: physical, synthetic: synthetic) {
                rewrite(event, as: effective)
            }
        }

        event.flags = InputProcessor.shared.combinedModifierFlags(physicalModifiers: event.flags)
    }

    func setTestingMotionTapHooks(start: (() -> Void)? = {}, stop: (() -> Void)? = {}) {
        testStartMotionTap = start
        testStopMotionTap = stop
    }

    func clearTestingMotionTapHooks() {
        testStartMotionTap = nil
        testStopMotionTap = nil
    }

    private static func syntheticPriority(of target: SyntheticMouseTarget) -> (Int, Int64) {
        switch target {
        case .left:
            return (0, 0)
        case .right:
            return (1, 0)
        case .other(let buttonNumber):
            return (2, buttonNumber)
        }
    }

    private static func physicalTarget(from event: CGEvent) -> PhysicalMouseTarget {
        switch event.type {
        case .leftMouseDragged:
            return .left
        case .rightMouseDragged:
            return .right
        case .otherMouseDragged:
            return .other(buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber))
        case .mouseMoved:
            return .none
        default:
            return .none
        }
    }

    private func recomputeDominantTarget() {
        dominantTarget = Self.dominantSyntheticTarget(from: Array(activeSessions.values))
    }

    private var shouldKeepMotionTapRunning: Bool {
        !activeSessions.isEmpty || hasActiveVirtualModifiers || hasActiveGesture
    }

    private func rewrite(_ event: CGEvent, as target: SyntheticMouseTarget) {
        switch target {
        case .left:
            event.type = .leftMouseDragged
            event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        case .right:
            event.type = .rightMouseDragged
            event.setIntegerValueField(.mouseEventButtonNumber, value: 1)
        case .other(let buttonNumber):
            event.type = .otherMouseDragged
            event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        }
    }

    private func startMotionTap() {
        if let startMotionTapOverride {
            startMotionTapOverride()
            isMotionTapRunning = true
            return
        }

        if let testStartMotionTap {
            testStartMotionTap()
            isMotionTapRunning = true
            return
        }

        if let motionInterceptor {
            do {
                try motionInterceptor.start()
                isMotionTapRunning = true
            } catch {
                NSLog("MouseInteractionSessionController: Failed to start motion interceptor: \(error)")
                isMotionTapRunning = false
            }
            return
        }

        do {
            let interceptor = try Interceptor(
                event: Self.motionEventMask,
                handleBy: Self.motionEventCallback,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .defaultTap
            )
            interceptor.onRestart = {
                InputProcessor.shared.clearActiveBindings()
            }
            interceptor.shouldRestart = { [weak self] in
                guard let self else { return false }
                return self.shouldKeepMotionTapRunning
            }
            motionInterceptor = interceptor
            isMotionTapRunning = true
        } catch {
            NSLog("MouseInteractionSessionController: Failed to create motion interceptor: \(error)")
            isMotionTapRunning = false
        }
    }

    private func stopMotionTap() {
        if let stopMotionTapOverride {
            stopMotionTapOverride()
            isMotionTapRunning = false
            return
        }

        if let testStopMotionTap {
            testStopMotionTap()
            isMotionTapRunning = false
            return
        }

        motionInterceptor?.pause()
        isMotionTapRunning = false
    }

    private func handleMotionTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            InputProcessor.shared.clearActiveBindings()
            return Unmanaged.passUnretained(event)
        }

        // 手势运动处理 (仅读取 delta 值, 不修改事件)
        gestureMotionHandler?(event)

        rewriteMouseInteractionEvent(event)
        return Unmanaged.passUnretained(event)
    }
}
