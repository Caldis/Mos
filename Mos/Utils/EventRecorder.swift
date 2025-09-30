//
//  EventRecorder.swift
//  Mos
//  用于录制热键
//
//  Created by Claude on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

protocol EventRecorderDelegate: AnyObject {
    func onEventRecorded(_ recorder: EventRecorder, didRecordEvent event: CGEvent)
}

class EventRecorder: NSObject {
    
    // MARK: - Constants
    static let TIMEOUT: TimeInterval = 10.0
    static let FLAG_CHANGE_NOTI_NAME = NSNotification.Name("RECORD_FLAG_CHANGE_NOTI_NAME")
    static let FINISH_NOTI_NAME = NSNotification.Name("RECORD_FINISH_NOTI_NAME")
    static let CANCEL_NOTI_NAME = NSNotification.Name("RECORD_CANCEL_NOTI_NAME")
    
    // Delegate
    weak var delegate: EventRecorderDelegate?
    // Recording
    private var interceptor: Interceptor?
    private var isRecording = false
    private var isRecorded = false // 是否已经记录过 (每次启动只记录一个按键
    private var recordTimeoutTimer: Timer? // 超时保护定时器
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
    func startRecording(from sourceView: NSView) {
        // Guard: 防止重复执行
        guard !isRecording else { return }
        isRecording = true
        // Log
        NSLog("[EventRecorder] Starting")
        // 确保清理任何存在的录制界面
        keyPopover?.hide()
        keyPopover = nil
        // 监听事件
        do {
            // 监听回调事件通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRecordedEvent(_:)),
                name: EventRecorder.FINISH_NOTI_NAME,
                object: nil
            )
            // 监听修饰键变化通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleModifierFlagsChanged(_:)),
                name: EventRecorder.FLAG_CHANGE_NOTI_NAME,
                object: nil
            )
            // 监听录制取消通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRecordingCancelled(_:)),
                name: EventRecorder.CANCEL_NOTI_NAME,
                object: nil
            )
            // 启动拦截器
            interceptor = try Interceptor(
                event: eventMask,
                handleBy: { (proxy, type, event, refcon) in
                    let recordedEvent = event
                    switch type {
                    case .flagsChanged:
                        // 修饰键变化，发送通知更新UI
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: EventRecorder.FLAG_CHANGE_NOTI_NAME,
                                object: recordedEvent
                            )
                        }
                    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                        // 鼠标按键
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: EventRecorder.FINISH_NOTI_NAME,
                                object: recordedEvent
                            )
                        }
                    case .keyDown:
                        // ESC键特殊处理：取消录制
                        if recordedEvent.keyCode == KeyCode.escape {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: EventRecorder.CANCEL_NOTI_NAME,
                                    object: nil
                                )
                            }
                        } else {
                            // 普通按键录制
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: EventRecorder.FINISH_NOTI_NAME,
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
            // 展示录制界面
            keyPopover = KeyPopover()
            keyPopover?.show(at: sourceView)
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
        // 如果有修饰键被按下，刷新超时定时器给用户更多时间
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
    // 通知事件处理
    @objc private func handleRecordedEvent(_ notification: NSNotification) {
        // Guard: 需要 Recording 才进行后续处理
        guard isRecording else { return }
        // Guard: 获取 RecordedEvent
        let event = notification.object as! CGEvent
        // Guard: 检查事件有效性
        guard event.isRecordable else { 
            NSLog("[EventRecorder] Invalid event ignored: \(event)")
            return 
        }
        // 更新记录标识
        guard !isRecorded else { return }
        isRecorded = true
        // 显示录制完成的按键
        keyPopover?.keyPreview
            .update(from: event.displayComponents, status: .recorded)
        // 将结果发给 delegate
        self.delegate?.onEventRecorded(self, didRecordEvent: event)
        // 停止录制 (延迟 300ms 确保能看完提示
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
        NotificationCenter.default.removeObserver(self, name: EventRecorder.FINISH_NOTI_NAME, object: nil)
        NotificationCenter.default.removeObserver(self, name: EventRecorder.FLAG_CHANGE_NOTI_NAME, object: nil)
        NotificationCenter.default.removeObserver(self, name: EventRecorder.CANCEL_NOTI_NAME, object: nil)
        // 重置状态 (添加延迟确保 Popover 结束动画完成, 避免多个 popover 重复出现导致卡住)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isRecording = false
            self?.isRecorded = false
            NSLog("[EventRecorder] Stopped")
        }
    }
    
    // MARK: - Timeout Protection
    private func startTimeoutTimer() {
        cancelTimeoutTimer()
        recordTimeoutTimer = Timer.scheduledTimer(withTimeInterval: EventRecorder.TIMEOUT, repeats: false) { [weak self] _ in
            NSLog("[EventRecorder] Recording timed out")
            self?.stopRecording()
        }
    }
    private func cancelTimeoutTimer() {
        recordTimeoutTimer?.invalidate()
        recordTimeoutTimer = nil
    }
}

