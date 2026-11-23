//
//  PhasedTrackpadOutput.swift
//  Mos
//  触控板式 phased 滚动输出: 手势状态机, 事件构造与输出端
//

import Cocoa

/// 触控板滚动事件使用的私有 CGEvent 字段编号
enum TrackpadEventField {
    static let sender = CGEventField(rawValue: 87)!
    static let gestureSubtype = CGEventField(rawValue: 110)!
    static let gestureDX = CGEventField(rawValue: 116)!
    static let gestureDY = CGEventField(rawValue: 119)!
    static let gesturePhase = CGEventField(rawValue: 132)!
    static let acceleratedX = CGEventField(rawValue: 175)!
    static let acceleratedY = CGEventField(rawValue: 176)!
    static let rawX = CGEventField(rawValue: 177)!
    static let rawY = CGEventField(rawValue: 178)!
}

/// phased 手势状态机。帧位移按整数像素输出, 不足 1 像素的部分结转到下一帧; 不产生惯性事件
struct PhasedTrackpadGesture {

    enum Step: Equatable {
        /// 惯性结束 + 预备 + 取消, 打断接收方仍在进行的滑行
        case interrupt
        case mayBegin
        case began(y: Int64, x: Int64)
        case changed(y: Int64, x: Int64)
        case ended
    }

    private(set) var isOpen = false
    private var remainder = (y: 0.0, x: 0.0)

    mutating func advance(y: Double, x: Double) -> [Step] {
        remainder.y += y
        remainder.x += x
        let iy = Int64(remainder.y.rounded(.towardZero))
        let ix = Int64(remainder.x.rounded(.towardZero))
        guard iy != 0 || ix != 0 else { return [] }
        remainder.y -= Double(iy)
        remainder.x -= Double(ix)
        if isOpen {
            return [.changed(y: iy, x: ix)]
        }
        isOpen = true
        return [.interrupt, .mayBegin, .began(y: iy, x: ix)]
    }

    /// 放弃进行中的手势而不产生事件; 下一次手势开头的 interrupt 负责复位接收方
    mutating func discard() {
        remainder = (0.0, 0.0)
        isOpen = false
    }

    mutating func end() -> [Step] {
        remainder = (0.0, 0.0)
        guard isOpen else { return [] }
        isOpen = false
        return [.ended]
    }
}

/// 以虚拟触控板为 sender, 从 HID 层投递 phased 事件的输出端
final class PhasedTrackpadSink: ScrollOutputSink {

    private let identity: VirtualTrackpadIdentity
    /// 判断光标是否仍在目标窗口的可见区域内, 可在任意线程调用
    private let contains: (CGPoint) -> Bool
    /// 只在投递队列上访问
    private var gesture = PhasedTrackpadGesture()

    init(identity: VirtualTrackpadIdentity, contains: @escaping (CGPoint) -> Bool) {
        self.identity = identity
        self.contains = contains
    }

    var isReady: Bool { identity.sender != nil }

    /// location 参数不使用: 事件跟随当前光标位置投递
    func frame(y: Double, x: Double, at location: CGPoint) {
        guard let sender = identity.sender else { return }
        // HID 层事件投递给光标下的窗口; 光标已离开目标窗口时放弃手势, 剩余插值与 Ended 都不送往其他应用
        guard isCursorInside() else {
            gesture.discard()
            return
        }
        post(gesture.advance(y: y, x: x), sender: sender)
    }

    func end(at location: CGPoint) {
        guard let sender = identity.sender, isCursorInside() else {
            gesture.discard()
            return
        }
        post(gesture.end(), sender: sender)
    }

    private func isCursorInside() -> Bool {
        guard let cursor = CGEvent(source: nil)?.location else { return false }
        return contains(cursor)
    }

    /// sender 非零时接收方读取 175-178; 公开位移被翻转或清零后同步这四个字段
    func preparePassthrough(_ event: CGEvent, reversedY: Bool, reversedX: Bool, clearedY: Bool, clearedX: Bool) {
        Self.syncRawFields(event, reverseY: reversedY, reverseX: reversedX, clearY: clearedY, clearX: clearedX)
    }

    private func post(_ steps: [PhasedTrackpadGesture.Step], sender: Int64) {
        for step in steps {
            for event in Self.makeEvents(for: step, sender: sender) {
                event.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - 事件构造

    /// 事件不写入 location, 保留创建时的光标位置。HID 层投递的事件会把光标移到其 location,
    /// 写入会话开始时的位置会把光标锁在原地
    static func makeEvents(for step: PhasedTrackpadGesture.Step, sender: Int64) -> [CGEvent] {
        switch step {
        case .interrupt:
            return [
                makeScroll(y: 0, x: 0, phase: 0, momentum: 3, sender: sender),
                makeScroll(y: 0, x: 0, phase: 128, momentum: 0, sender: sender),
                makeGesture(y: 0, x: 0, phase: 128, sender: sender),
                makeScroll(y: 0, x: 0, phase: 8, momentum: 0, sender: sender),
                makeGesture(y: 0, x: 0, phase: 8, sender: sender),
            ].compactMap { $0 }
        case .mayBegin:
            return pair(y: 0, x: 0, phase: 128, sender: sender)
        case .began(let y, let x):
            return pair(y: y, x: x, phase: 1, sender: sender)
        case .changed(let y, let x):
            return pair(y: y, x: x, phase: 2, sender: sender)
        case .ended:
            return pair(y: 0, x: 0, phase: 4, sender: sender)
        }
    }

    private static func pair(y: Int64, x: Int64, phase: Int64, sender: Int64) -> [CGEvent] {
        return [
            makeScroll(y: y, x: x, phase: phase, momentum: 0, sender: sender),
            makeGesture(y: y, x: x, phase: phase, sender: sender),
        ].compactMap { $0 }
    }

    static func makeScroll(y: Int64, x: Int64, phase: Int64, momentum: Int64, sender: Int64) -> CGEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else {
            return nil
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        // 写入行位移会按 1 行 = 8 像素重算定点位移与像素位移, 因此行位移必须最先写入
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: y.signum())
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: x.signum())
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: y)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: x)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(y) / 10)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(x) / 10)
        event.setDoubleValueField(TrackpadEventField.acceleratedY, value: Double(y))
        event.setDoubleValueField(TrackpadEventField.acceleratedX, value: Double(x))
        event.setDoubleValueField(TrackpadEventField.rawY, value: Double(y))
        event.setDoubleValueField(TrackpadEventField.rawX, value: Double(x))
        event.setIntegerValueField(TrackpadEventField.sender, value: sender)
        ScrollUtils.shared.markSyntheticSmoothEvent(event)
        return event
    }

    /// 真实触控板的每个滚动事件都伴随一个 type 29 手势事件 (滚动子类型 6)
    static func makeGesture(y: Int64, x: Int64, phase: Int64, sender: Int64) -> CGEvent? {
        guard let event = CGEvent(source: nil), let gestureType = CGEventType(rawValue: 29) else { return nil }
        event.type = gestureType
        event.setIntegerValueField(TrackpadEventField.gestureSubtype, value: 6)
        event.setIntegerValueField(TrackpadEventField.gesturePhase, value: phase)
        event.setDoubleValueField(TrackpadEventField.gestureDX, value: Double(x))
        event.setDoubleValueField(TrackpadEventField.gestureDY, value: Double(y))
        event.setIntegerValueField(TrackpadEventField.sender, value: sender)
        ScrollUtils.shared.markSyntheticSmoothEvent(event)
        return event
    }

    static func syncRawFields(_ event: CGEvent, reverseY: Bool, reverseX: Bool, clearY: Bool, clearX: Bool) {
        if reverseY || clearY {
            event.setDoubleValueField(TrackpadEventField.acceleratedY, value: clearY ? 0 : -event.getDoubleValueField(TrackpadEventField.acceleratedY))
            event.setDoubleValueField(TrackpadEventField.rawY, value: clearY ? 0 : -event.getDoubleValueField(TrackpadEventField.rawY))
        }
        if reverseX || clearX {
            event.setDoubleValueField(TrackpadEventField.acceleratedX, value: clearX ? 0 : -event.getDoubleValueField(TrackpadEventField.acceleratedX))
            event.setDoubleValueField(TrackpadEventField.rawX, value: clearX ? 0 : -event.getDoubleValueField(TrackpadEventField.rawX))
        }
    }
}
