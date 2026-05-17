//
//  KeyRecorder.swift
//  Mos
//  用于录制热键
//
//  Created by Claude on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

/// 录制模式
enum KeyRecordingMode {
    /// 组合键模式：需要修饰键+普通键的组合 (用于 ButtonsView)
    case combination
    /// 单键模式：支持单个按键，包括单独的修饰键 (用于 ScrollingView)
    case singleKey
    /// 自适应模式：支持所有输入类型，通过时间间隔判断意图 (用于自定义绑定)
    case adaptive
}

protocol KeyRecorderDelegate: AnyObject {
    /// 录制开始回调
    func onRecordingStarted(_ recorder: KeyRecorder)

    /// 录制完成回调
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool)

    /// 录制结束回调
    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool)

    /// 验证录制的事件是否为重复
    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool
}

/// 默认实现 (替代 @objc optional 语义)
extension KeyRecorderDelegate {
    func onRecordingStarted(_ recorder: KeyRecorder) {}

    func onRecordingStopped(_ recorder: KeyRecorder, didRecord: Bool) {}

    func validateRecordedEvent(_ recorder: KeyRecorder, event: InputEvent) -> Bool {
        return true
    }
}

class KeyRecorder: NSObject {

    // MARK: - Constants
    static let TIMEOUT: TimeInterval = 10.0
    private static let recordedFeedbackDelay: TimeInterval = 0.7
    private static let duplicateFeedbackDelay: TimeInterval = 1.0
    static let FLAG_CHANGE_NOTI_NAME = NSNotification.Name("RECORD_FLAG_CHANGE_NOTI_NAME")
    static let FINISH_NOTI_NAME = NSNotification.Name("RECORD_FINISH_NOTI_NAME")
    static let CANCEL_NOTI_NAME = NSNotification.Name("RECORD_CANCEL_NOTI_NAME")

    // Delegate
    weak var delegate: KeyRecorderDelegate?
    // Recording
    private var interceptor: Interceptor?
    private var isRecording = false
    private var isRecorded = false // 是否已经记录过 (每次启动只记录一个按键
    private var recordTimeoutTimer: Timer? // 超时保护定时器
    private var invalidKeyPressCount = 0 // 无效按键计数
    private let invalidKeyThreshold = 5 // 显示 ESC 提示的阈值
    private var recordingMode: KeyRecordingMode = .combination // 当前录制模式
    private var hidEventObserver: NSObjectProtocol?  // HID++ 事件监听 (录制期间)
    // Adaptive mode state
    private enum AdaptiveState {
        case idle
        case modifierHeld(modifiers: CGEventFlags)
        case modifierReleasedWaiting(modifiers: CGEventFlags)
        case recorded
    }
    private var adaptiveState: AdaptiveState = .idle
    private var adaptiveConfirmTimer: Timer?  // 300ms post-release timer
    private var holdConfirmTimer: Timer?       // 9.5s fallback timer
    // 同时释放检测 (类似格斗游戏组合键输入缓冲)
    private var previousAdaptiveFlags: CGEventFlags = []
    private var modifierReleaseTimestamps: [(flags: CGEventFlags, time: TimeInterval)] = []
    private var displayDebounceTimer: Timer?  // 释放时延迟更新 preview, 避免闪烁中间态

    // Adaptive mode constants
    private static let ADAPTIVE_CONFIRM_DELAY: TimeInterval = 0.3
    private static let HOLD_CONFIRM_DELAY: TimeInterval = 9.5
    private static let SIMULTANEOUS_RELEASE_WINDOW: TimeInterval = 0.05  // 50ms 内视为同时释放
    private static let modifierFlagsMask: UInt64 =
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskSecondaryFn.rawValue

    static func recordingFeedbackDelay(isDuplicate: Bool) -> TimeInterval {
        return isDuplicate ? duplicateFeedbackDelay : recordedFeedbackDelay
    }

    // UI 组件
    private var keyPopover: KeyPopover?
    
    // MARK: - Life Cycle
    deinit {
        stopRecording()
    }
    
    // MARK: - Event Masks
    // 事件掩码 (支持鼠标和键盘事件，包括修饰键变化)
    private var eventMask: CGEventMask {
        let leftDown = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let rightDown = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        let otherDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let flagsChanged = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        return leftDown | rightDown | otherDown | keyDown | flagsChanged
    }
    
    // MARK: - Recording Manager
    // 开始记录事件
    /// - Parameters:
    ///   - sourceView: 触发录制的视图，用于显示 Popover
    ///   - mode: 录制模式，默认为组合键模式
    func startRecording(from sourceView: NSView, mode: KeyRecordingMode = .combination) {
        // Guard: 防止重复执行
        guard !isRecording else { return }
        isRecording = true
        recordingMode = mode
        delegate?.onRecordingStarted(self)
        // Log
        NSLog("[EventRecorder] Starting in \(mode) mode")
        // 确保清理任何存在的录制界面
        keyPopover?.hide()
        keyPopover = nil
        // 立即显示 Popover (不等待 HID++ divert)
        keyPopover = KeyPopover()
        keyPopover?.show(at: sourceView)
        // 异步 divert 所有 Logitech 按键 (BLE 通信有延迟)
        DispatchQueue.main.async {
            LogiCenter.shared.beginKeyRecording()
        }
        // 监听事件
        do {
            // 监听回调事件通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRecordedEvent(_:)),
                name: KeyRecorder.FINISH_NOTI_NAME,
                object: nil
            )
            // 监听修饰键变化通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleModifierFlagsChanged(_:)),
                name: KeyRecorder.FLAG_CHANGE_NOTI_NAME,
                object: nil
            )
            // 监听录制取消通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRecordingCancelled(_:)),
                name: KeyRecorder.CANCEL_NOTI_NAME,
                object: nil
            )
            // 启动拦截器
            interceptor = try Interceptor(
                event: eventMask,
                handleBy: { (proxy, type, event, refcon) in
                    // 跳过 Mos 合成事件, 避免 executeCustom 的合成事件干扰录制
                    if event.getIntegerValueField(.eventSourceUserData) == MosEventMarker.syntheticCustom {
                        return nil
                    }
                    let recordedEvent = event
                    switch type {
                    case .flagsChanged:
                        // 修饰键变化，发送通知 (单键模式下也用于完成录制)
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: KeyRecorder.FLAG_CHANGE_NOTI_NAME,
                                object: recordedEvent
                            )
                        }
                    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                        // 鼠标按键
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: KeyRecorder.FINISH_NOTI_NAME,
                                object: recordedEvent
                            )
                        }
                    case .keyDown:
                        // ESC键特殊处理：取消录制
                        if recordedEvent.keyCode == KeyCode.escape {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: KeyRecorder.CANCEL_NOTI_NAME,
                                    object: nil
                                )
                            }
                        } else {
                            // 普通按键录制
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: KeyRecorder.FINISH_NOTI_NAME,
                                    object: recordedEvent
                                )
                            }
                        }
                    default:
                        break
                    }
                    return nil
                },
                listenOn: CGEventTapLocation.cgSessionEventTap,
                placeAt: CGEventTapPlacement.headInsertEventTap,
                for: CGEventTapOptions.defaultTap
            )
            // 监听 HID++ 事件 (如果 LogiCenter 已启动)
            hidEventObserver = NotificationCenter.default.addObserver(
                forName: LogiCenter.buttonEventRelay,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self, self.isRecording, !self.isRecorded else { return }
                guard let mosEvent = notification.userInfo?["event"] as? InputEvent else { return }
                guard mosEvent.phase == .down else { return }
                NotificationCenter.default.post(
                    name: KeyRecorder.FINISH_NOTI_NAME,
                    object: mosEvent
                )
            }
            // 启动超时保护定时器
            startTimeoutTimer()
            // Log
            NSLog("[EventRecorder] Started")
        } catch {
            NSLog("[EventRecorder] Failed to start: \(error)")
            // 如果创建失败，重置状态
            isRecording = false
        }
    }
    // 修饰键变化处理
    @objc private func handleModifierFlagsChanged(_ notification: NSNotification) {
        guard isRecording && !isRecorded else { return }
        let event = notification.object as! CGEvent

        // Adaptive 模式: 使用状态机处理修饰键
        if recordingMode == .adaptive {
            handleAdaptiveFlagsChanged(event)
            return
        }

        // 单键模式：修饰键按下时直接完成录制
        if recordingMode == .singleKey && event.isKeyDown && event.isModifiers {
            NSLog("[EventRecorder] Single key mode: modifier key recorded")
            NotificationCenter.default.post(
                name: KeyRecorder.FINISH_NOTI_NAME,
                object: event
            )
            return
        }

        // 组合键模式：如果有修饰键被按下，刷新超时定时器给用户更多时间
        let hasActiveModifiers = event.hasModifiers
        if hasActiveModifiers {
            startTimeoutTimer()
            NSLog("[EventRecorder] Modifier key pressed, timeout timer refreshed")
        }
        // 实时更新录制界面显示当前已按下的修饰键
        keyPopover?.keyPreview
            .updateForRecording(from: event)
    }
    // MARK: - Adaptive Mode

    private func handleAdaptiveFlagsChanged(_ event: CGEvent) {
        let hasActiveModifiers = event.hasModifiers

        // 检测本次释放了哪些修饰键 (previous & ~current)
        let currentBits = event.flags.rawValue & Self.modifierFlagsMask
        let previousBits = previousAdaptiveFlags.rawValue & Self.modifierFlagsMask
        let releasedBits = previousBits & ~currentBits
        if releasedBits != 0 {
            modifierReleaseTimestamps.append((
                flags: CGEventFlags(rawValue: releasedBits),
                time: CACurrentMediaTime()
            ))
        }
        previousAdaptiveFlags = event.flags

        if hasActiveModifiers {
            // 修饰键仍有按住
            cancelAdaptiveConfirmTimer()
            startHoldConfirmTimer()
            startTimeoutTimer()
            // 新手势开始时清空释放历史
            switch adaptiveState {
            case .idle, .modifierReleasedWaiting, .recorded:
                modifierReleaseTimestamps.removeAll()
            case .modifierHeld:
                break
            }
            adaptiveState = .modifierHeld(modifiers: event.flags)
            NSLog("[EventRecorder] Adaptive: modifier held, flags=\(event.flags.rawValue)")

            let isAdding = (currentBits & ~previousBits) != 0
            if isAdding {
                // 新增修饰键: 取消 debounce, 清空释放历史 (用户改变了意图), 立即更新显示
                cancelDisplayDebounceTimer()
                modifierReleaseTimestamps.removeAll()
                keyPopover?.keyPreview.updateForRecording(from: event)
            } else {
                // 释放修饰键但仍有按住: 延迟更新, 避免同时释放时闪烁中间态
                scheduleDisplayDebounce(event: event)
            }
        } else {
            // 所有修饰键松开
            cancelDisplayDebounceTimer() // 不再需要延迟更新, 最终结果由 confirm 流程显示
            switch adaptiveState {
            case .modifierHeld:
                cancelHoldConfirmTimer()
                // 从释放时间戳中计算同时释放的修饰键组合
                let simultaneousModifiers = computeSimultaneousReleaseModifiers()
                modifierReleaseTimestamps.removeAll()
                adaptiveState = .modifierReleasedWaiting(modifiers: simultaneousModifiers)
                startAdaptiveConfirmTimer(modifiers: simultaneousModifiers)
                NSLog("[EventRecorder] Adaptive: all released, simultaneous flags=\(simultaneousModifiers.rawValue)")
            default:
                break
            }
        }
    }

    /// 从释放时间戳中提取最后一组同时释放的修饰键
    /// 类似格斗游戏组合键检测: 50ms 窗口内的释放视为同时操作
    private func computeSimultaneousReleaseModifiers() -> CGEventFlags {
        guard let lastRelease = modifierReleaseTimestamps.last else { return [] }
        var combinedBits: UInt64 = 0
        for release in modifierReleaseTimestamps.reversed() {
            if lastRelease.time - release.time <= Self.SIMULTANEOUS_RELEASE_WINDOW {
                combinedBits |= release.flags.rawValue
            } else {
                break
            }
        }
        return CGEventFlags(rawValue: combinedBits)
    }

    /// Adaptive 模式下的事件完成处理 (非修饰键/组合键录入时调用)
    private func handleAdaptiveRecordedEvent(_ event: InputEvent) {
        cancelAdaptiveConfirmTimer()
        cancelHoldConfirmTimer()
        adaptiveState = .recorded
    }

    /// 确认录制当前修饰键组合 (300ms 定时器或 9.5s hold 定时器触发)
    private func confirmAdaptiveModifiers(_ modifiers: CGEventFlags) {
        guard isRecording && !isRecorded else { return }
        cancelAdaptiveConfirmTimer()
        cancelHoldConfirmTimer()
        adaptiveState = .recorded

        // 构造 InputEvent 并通过 FINISH 通知完成录制
        let mosEvent = InputEvent(
            type: .keyboard,
            code: extractPrimaryModifierCode(from: modifiers),
            modifiers: modifiers,
            phase: .down,
            source: .hidPP,
            device: nil
        )
        NotificationCenter.default.post(
            name: KeyRecorder.FINISH_NOTI_NAME,
            object: mosEvent
        )
    }

    /// 从 flags 中提取主要修饰键的 keyCode
    private func extractPrimaryModifierCode(from flags: CGEventFlags) -> UInt16 {
        if flags.rawValue & CGEventFlags.maskCommand.rawValue != 0 { return KeyCode.commandL }
        if flags.rawValue & CGEventFlags.maskShift.rawValue != 0 { return KeyCode.shiftL }
        if flags.rawValue & CGEventFlags.maskAlternate.rawValue != 0 { return KeyCode.optionL }
        if flags.rawValue & CGEventFlags.maskControl.rawValue != 0 { return KeyCode.controlL }
        if flags.rawValue & CGEventFlags.maskSecondaryFn.rawValue != 0 { return KeyCode.fnL }
        return KeyCode.commandL
    }

    // MARK: - Adaptive Timers

    private func startAdaptiveConfirmTimer(modifiers: CGEventFlags) {
        cancelAdaptiveConfirmTimer()
        adaptiveConfirmTimer = Timer.scheduledTimer(withTimeInterval: KeyRecorder.ADAPTIVE_CONFIRM_DELAY, repeats: false) { [weak self] _ in
            NSLog("[EventRecorder] Adaptive: 300ms confirm timer fired, confirming modifier(s)")
            self?.confirmAdaptiveModifiers(modifiers)
        }
    }

    private func cancelAdaptiveConfirmTimer() {
        adaptiveConfirmTimer?.invalidate()
        adaptiveConfirmTimer = nil
    }

    private func startHoldConfirmTimer() {
        cancelHoldConfirmTimer()
        holdConfirmTimer = Timer.scheduledTimer(withTimeInterval: KeyRecorder.HOLD_CONFIRM_DELAY, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            NSLog("[EventRecorder] Adaptive: 9.5s hold timer fired")
            if case .modifierHeld(let modifiers) = self.adaptiveState {
                self.confirmAdaptiveModifiers(modifiers)
            }
        }
    }

    private func cancelHoldConfirmTimer() {
        holdConfirmTimer?.invalidate()
        holdConfirmTimer = nil
    }

    // MARK: - Display Debounce (防止同时释放修饰键时 preview 闪烁中间态)

    private func scheduleDisplayDebounce(event: CGEvent) {
        cancelDisplayDebounceTimer()
        // 保留 event 的 flags 用于延迟更新 (CGEvent 是引用类型, 不需要拷贝 flags)
        let flags = event.flags
        displayDebounceTimer = Timer.scheduledTimer(withTimeInterval: Self.SIMULTANEOUS_RELEASE_WINDOW, repeats: false) { [weak self] _ in
            guard let self = self, self.isRecording, !self.isRecorded else { return }
            // 窗口期内没有更多释放事件, 说明这是一次有意的释放, 更新显示
            self.keyPopover?.keyPreview.updateForRecording(modifiers: flags)
        }
    }

    private func cancelDisplayDebounceTimer() {
        displayDebounceTimer?.invalidate()
        displayDebounceTimer = nil
    }

    // 录制取消处理
    @objc private func handleRecordingCancelled(_ notification: NSNotification) {
        guard isRecording && !isRecorded else { return }
        NSLog("[EventRecorder] Recording cancelled by ESC key")
        stopRecording()
    }
    @objc private func handleRecordedEvent(_ notification: NSNotification) {
        guard isRecording else { return }

        // 统一转换为 InputEvent
        // 注意: 先检查 InputEvent (value type), 再检查 CGEvent (CoreFoundation type)
        // CGEvent 的 as? 对 Any 总是成功, 所以必须后检查
        let mosEvent: InputEvent
        if let hidEvent = notification.object as? InputEvent {
            mosEvent = hidEvent
        } else if let cgEvent = notification.object, CFGetTypeID(cgEvent as CFTypeRef) == CGEvent.typeID {
            mosEvent = InputEvent(fromCGEvent: cgEvent as! CGEvent)
        } else {
            NSLog("[EventRecorder] Unknown event type in notification")
            return
        }

        // Adaptive 模式: 清理定时器和状态
        if recordingMode == .adaptive {
            handleAdaptiveRecordedEvent(mosEvent)
        }

        // 检查事件有效性 (根据录制模式)
        let isValid: Bool
        switch recordingMode {
        case .singleKey:
            isValid = mosEvent.isRecordableAsSingleKey
        case .combination:
            isValid = mosEvent.isRecordable
        case .adaptive:
            isValid = mosEvent.isRecordableAsAdaptive
        }
        guard isValid else {
            NSLog("[EventRecorder] Invalid event ignored")
            keyPopover?.keyPreview.shakeWarning()
            invalidKeyPressCount += 1
            if invalidKeyPressCount >= invalidKeyThreshold {
                keyPopover?.showEscHint()
            }
            return
        }

        guard !isRecorded else { return }
        isRecorded = true

        let isNew = self.delegate?.validateRecordedEvent(self, event: mosEvent) ?? true
        let isDuplicate = !isNew
        let status: KeyPreview.Status = isNew ? .recorded : .duplicate

        keyPopover?.keyPreview
            .update(from: mosEvent.displayComponents, status: status)
        if isDuplicate {
            keyPopover?.showDuplicateHint()
        }
        self.delegate?.onEventRecorded(self, didRecordEvent: mosEvent, isDuplicate: isDuplicate)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recordingFeedbackDelay(isDuplicate: isDuplicate)) { [weak self] in
            self?.stopRecording()
        }
    }

    // 停止记录
    func stopRecording() {
        // Guard: 需要 Recording 才进行后续处理
        guard isRecording else { return }
        let didRecord = isRecorded
        // Log
        NSLog("[EventRecorder] Stopping")
        // 隐藏录制界面
        keyPopover?.hide()
        keyPopover = nil
        // 取消超时定时器
        cancelTimeoutTimer()
        // 清理 adaptive 状态
        cancelAdaptiveConfirmTimer()
        cancelHoldConfirmTimer()
        cancelDisplayDebounceTimer()
        adaptiveState = .idle
        previousAdaptiveFlags = []
        modifierReleaseTimestamps.removeAll()
        // 取消通知和监听
        interceptor?.stop()
        interceptor = nil
        NotificationCenter.default.removeObserver(self, name: KeyRecorder.FINISH_NOTI_NAME, object: nil)
        NotificationCenter.default.removeObserver(self, name: KeyRecorder.FLAG_CHANGE_NOTI_NAME, object: nil)
        NotificationCenter.default.removeObserver(self, name: KeyRecorder.CANCEL_NOTI_NAME, object: nil)
        if let observer = hidEventObserver {
            NotificationCenter.default.removeObserver(observer)
            hidEventObserver = nil
        }
        delegate?.onRecordingStopped(self, didRecord: didRecord)
        // 录制结束: 恢复到只 divert 有绑定的按键
        LogiCenter.shared.endKeyRecording()
        // 重置状态 (添加延迟确保 Popover 结束动画完成, 避免多个 popover 重复出现导致卡住)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isRecording = false
            self?.isRecorded = false
            self?.invalidKeyPressCount = 0
            NSLog("[EventRecorder] Stopped")
        }
    }
    
    // MARK: - Timeout Protection
    private func startTimeoutTimer() {
        cancelTimeoutTimer()
        recordTimeoutTimer = Timer.scheduledTimer(withTimeInterval: KeyRecorder.TIMEOUT, repeats: false) { [weak self] _ in
            NSLog("[EventRecorder] Recording timed out")
            self?.stopRecording()
        }
    }
    private func cancelTimeoutTimer() {
        recordTimeoutTimer?.invalidate()
        recordTimeoutTimer = nil
    }
}
