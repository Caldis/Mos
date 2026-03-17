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
}

protocol KeyRecorderDelegate: AnyObject {
    /// 录制完成回调
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: MosInputEvent, isDuplicate: Bool)

    /// 验证录制的事件是否为重复
    func validateRecordedEvent(_ recorder: KeyRecorder, event: MosInputEvent) -> Bool
}

/// 默认实现 (替代 @objc optional 语义)
extension KeyRecorderDelegate {
    func validateRecordedEvent(_ recorder: KeyRecorder, event: MosInputEvent) -> Bool {
        return true
    }
}

class KeyRecorder: NSObject {

    // MARK: - Constants
    static let TIMEOUT: TimeInterval = 10.0
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
            LogitechHIDManager.shared.temporarilyDivertAll()
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
            // 监听 HID++ 事件 (如果 LogitechHIDManager 已启动)
            hidEventObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("LogitechHIDButtonEvent"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self, self.isRecording, !self.isRecorded else { return }
                guard let mosEvent = notification.userInfo?["event"] as? MosInputEvent else { return }
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

        // 单键模式：修饰键按下时直接完成录制
        if recordingMode == .singleKey && event.isKeyDown && event.isModifiers {
            NSLog("[EventRecorder] Single key mode: modifier key recorded")
            // 直接触发录制完成
            NotificationCenter.default.post(
                name: KeyRecorder.FINISH_NOTI_NAME,
                object: event
            )
            return
        }

        // 组合键模式：如果有修饰键被按下，刷新超时定时器给用户更多时间
        let hasActiveModifiers = event.hasModifiers
        if hasActiveModifiers {
            startTimeoutTimer() // 重新启动定时器
            NSLog("[EventRecorder] Modifier key pressed, timeout timer refreshed")
        }
        // 实时更新录制界面显示当前已按下的修饰键
        keyPopover?.keyPreview
            .updateForRecording(from: event)
    }
    // 录制取消处理
    @objc private func handleRecordingCancelled(_ notification: NSNotification) {
        guard isRecording && !isRecorded else { return }
        NSLog("[EventRecorder] Recording cancelled by ESC key")
        stopRecording()
    }
    @objc private func handleRecordedEvent(_ notification: NSNotification) {
        guard isRecording else { return }

        // 统一转换为 MosInputEvent
        // 注意: 先检查 MosInputEvent (value type), 再检查 CGEvent (CoreFoundation type)
        // CGEvent 的 as? 对 Any 总是成功, 所以必须后检查
        let mosEvent: MosInputEvent
        if let hidEvent = notification.object as? MosInputEvent {
            mosEvent = hidEvent
        } else if let cgEvent = notification.object, CFGetTypeID(cgEvent as CFTypeRef) == CGEvent.typeID {
            mosEvent = MosInputEvent(fromCGEvent: cgEvent as! CGEvent)
        } else {
            NSLog("[EventRecorder] Unknown event type in notification")
            return
        }

        // 检查事件有效性 (根据录制模式)
        let isValid = recordingMode == .singleKey
            ? mosEvent.isRecordableAsSingleKey
            : mosEvent.isRecordable
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
        self.delegate?.onEventRecorded(self, didRecordEvent: mosEvent, isDuplicate: isDuplicate)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.stopRecording()
        }
    }

    // 停止记录
    func stopRecording() {
        // Guard: 需要 Recording 才进行后续处理
        guard isRecording else { return }
        // Log
        NSLog("[EventRecorder] Stopping")
        // 隐藏录制界面
        keyPopover?.hide()
        keyPopover = nil
        // 取消超时定时器
        cancelTimeoutTimer()
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
        // 录制结束: 恢复到只 divert 有绑定的按键
        LogitechHIDManager.shared.restoreDivertToBindings()
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

