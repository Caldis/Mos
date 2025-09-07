//
//  EventRecorder.swift
//  Mos
//
//  Created by Claude on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

let RECORD_NOTI_NAME = NSNotification.Name("EventRecorded") // 内部事件名
let MODIFIER_FLAGS_CHANGED_NOTI_NAME = NSNotification.Name("ModifierFlagsChanged") // 修饰键变化通知
let RECORDING_CANCELLED_NOTI_NAME = NSNotification.Name("RecordingCancelled") // 录制取消通知
let RECORD_TIMEOUT = 5.0 // 超时时间

// MARK: - 组合键数据结构
struct RecordedEvent {
    var modifierFlags: NSEvent.ModifierFlags
    var mouseButton: Int?
    var keyCode: UInt16?
    
    var hasModifiers: Bool {
        return !modifierFlags.intersection([.command, .option, .control, .shift, .function]).isEmpty
    }
    
    var isValid: Bool {
        // 修饰键不能单独存在，必须和鼠标或键盘按键组合
        if mouseButton == nil && keyCode == nil {
            return false
        }
        // 纯修饰键不允许被记录
        if keyCode != nil && isModifierKey(keyCode!) && mouseButton == nil {
            return false
        }
        return true
    }
    
    private func isModifierKey(_ keyCode: UInt16) -> Bool {
        let modifierKeyCodes: Set<UInt16> = [54, 55, 58, 59, 60, 61, 62, 179] // cmd, shift, option, ctrl, fn
        return modifierKeyCodes.contains(keyCode)
    }
    
    func displayName() -> String {
        var components: [String] = []
        
        // 使用扩展方法格式化修饰键
        let modifierString = modifierFlags.formattedString(excludeFnForFunctionKeys: keyCode)
        if !modifierString.isEmpty {
            components.append(modifierString)
        }
        
        // 添加主键
        if let mouseButton = mouseButton {
            switch mouseButton {
            case 0: components.append("Left Click")
            case 1: components.append("Right Click") 
            case 2: components.append("Middle Click")
            default: components.append("Mouse \(mouseButton + 1)")
            }
        }
        
        if let keyCode = keyCode {
            components.append(keyCodeToString(keyCode))
        }
        
        return components.joined(separator: " + ")
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // 标准按键映射 - 使用紧凑的字典方式
        let keyMap: [UInt16: String] = [
            // 字母键
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            // 数字键
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 26: "7", 28: "8", 29: "0", 25: "9",
            // 符号键
            24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
            // 特殊键
            49: "⎵", 51: "⌫", 53: "⎋", 76: "↩", 36: "↩", 48: "↹", 179: "Fn",
            // F键 (兼容 MacBook 功能键)
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 111: "F10", 103: "F11", 109: "F12", 105: "F13", 107: "F14", 113: "F15"
        ]
        
        return keyMap[keyCode] ?? "Key(\(keyCode))"
    }
    
    
}

protocol EventRecorderDelegate: AnyObject {
    func eventRecorder(_ recorder: EventRecorder, didRecordEvent event: RecordedEvent)
}

class EventRecorder: NSObject {
    
    // Delegate
    weak var delegate: EventRecorderDelegate?
    // Recording
    private var interceptor: Interceptor?
    private var isRecording = false
    private var isRecorded = false // 是否已经记录过 (每次启动只记录一个按键
    private var recordTimeoutTimer: Timer? // 超时保护定时器
    // Popover
    private var popover: NSPopover?
    private weak var popoverSourceView: NSView?
    // 修饰键状态跟踪
    private var currentModifiers = NSEvent.ModifierFlags()
    
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
        // 确保清理任何存在的 popover
        hidePopover()
        // 监听事件
        do {
            // 监听回调事件通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRecordedEvent(_:)),
                name: RECORD_NOTI_NAME,
                object: nil
            )
            // 监听修饰键变化通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleModifierFlagsChanged(_:)),
                name: MODIFIER_FLAGS_CHANGED_NOTI_NAME,
                object: nil
            )
            // 监听录制取消通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRecordingCancelled(_:)),
                name: RECORDING_CANCELLED_NOTI_NAME,
                object: nil
            )
            // 启动拦截器
            interceptor = try Interceptor(
                event: eventMask,
                handleBy: { (proxy, type, event, refcon) in
                    let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                    
                    switch type {
                    case .flagsChanged:
                        // 修饰键变化，发送通知更新UI
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: MODIFIER_FLAGS_CHANGED_NOTI_NAME,
                                object: flags
                            )
                        }
                    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                        // 鼠标按键
                        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                        let recordedEvent = RecordedEvent(
                            modifierFlags: flags,
                            mouseButton: buttonNumber,
                            keyCode: nil
                        )
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: RECORD_NOTI_NAME,
                                object: recordedEvent
                            )
                        }
                    case .keyDown:
                        // 其他键盘按键
                        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                        
                        // ESC键特殊处理：取消录制
                        if keyCode == 53 { // ESC keyCode
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: RECORDING_CANCELLED_NOTI_NAME,
                                    object: nil
                                )
                            }
                        } else {
                            // 普通按键录制
                            let recordedEvent = RecordedEvent(
                                modifierFlags: flags,
                                mouseButton: nil,
                                keyCode: keyCode
                            )
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: RECORD_NOTI_NAME,
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
            // 展示 Popover
            showPopover(at: sourceView)
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
        guard let flags = notification.object as? NSEvent.ModifierFlags else { return }
        
        // 更新当前修饰键状态
        currentModifiers = flags
        
        // 如果有修饰键被按下，刷新超时定时器给用户更多时间
        let hasActiveModifiers = !flags.intersection([.command, .option, .control, .shift, .function]).isEmpty
        if hasActiveModifiers {
            startTimeoutTimer() // 重新启动定时器
            NSLog("[EventRecorder] Modifier key pressed, timeout timer refreshed")
        }
        
        // 实时更新popover显示当前已按下的修饰键
        updatePopoverForModifiers(flags)
    }
    
    // 录制取消处理
    @objc private func handleRecordingCancelled(_ notification: NSNotification) {
        guard isRecording && !isRecorded else { return }
        NSLog("[EventRecorder] Recording cancelled by ESC key")
        // 显示取消提示
        updatePopoverTextForCancellation()
        // 延迟停止录制，让用户看到取消提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.stopRecording()
        }
    }
    
    // 通知事件处理
    @objc private func handleRecordedEvent(_ notification: NSNotification) {
        // Guard: 需要 Recording 才进行后续处理
        guard isRecording else { return }
        // Guard: 获取 RecordedEvent
        guard let event = notification.object as? RecordedEvent else { return }
        // Guard: 检查事件有效性
        guard event.isValid else { 
            NSLog("[EventRecorder] Invalid event ignored: \(event)")
            return 
        }
        // 更新记录标识
        guard !isRecorded else { return }
        isRecorded = true
        // 更新 popover 显示操作的按键
        updatePopoverText(for: event)
        // 将结果发给 delegate
        self.delegate?.eventRecorder(self, didRecordEvent: event)
        // 停止录制 (延迟 300ms 确保能看完提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.stopRecording()
        }
    }
    // 停止记录
    func stopRecording() {
        // Guard: 需要 Recording 才进行后续处理
        guard isRecording else { return }
        // Log
        NSLog("[EventRecorder] Stopping")
        // 隐藏 Popover
        hidePopover()
        // 取消超时定时器
        cancelTimeoutTimer()
        // 取消通知和监听
        interceptor?.stop()
        interceptor = nil
        NotificationCenter.default.removeObserver(self, name: RECORD_NOTI_NAME, object: nil)
        NotificationCenter.default.removeObserver(self, name: MODIFIER_FLAGS_CHANGED_NOTI_NAME, object: nil)
        NotificationCenter.default.removeObserver(self, name: RECORDING_CANCELLED_NOTI_NAME, object: nil)
        // 重置状态 (添加延迟确保 Popover 结束动画完成, 避免多个 popover 重复出现导致卡住)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isRecording = false
            self?.isRecorded = false
            self?.currentModifiers = NSEvent.ModifierFlags()
            NSLog("[EventRecorder] Stopped")
        }
    }
    
    // MARK: - Popover Management
    private func showPopover(at sourceView: NSView?) {
        // Guard: 没有 sourceView 直接不展示
        guard let sourceView = sourceView else { return }
        // 清理现有 popover
        hidePopover()
        // 创建 popover 内容
        let contentController = NSViewController()
        let contentView = NSView()
        contentView.wantsLayer = true
        
        let label = NSTextField(labelWithString: NSLocalizedString("Press any key...", comment: ""))
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
            contentView.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        contentController.view = contentView
        
        // 创建并配置 popover
        let newPopover = NSPopover()
        newPopover.contentViewController = contentController
        newPopover.behavior = .transient
        
        // 设置引用并显示
        popover = newPopover
        newPopover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }
    
    private func hidePopover() {
        if let currentPopover = popover {
            currentPopover.close() // 使用 close() 确保立即关闭
            popover = nil
        }
    }
    
    // 为修饰键实时更新popover显示
    private func updatePopoverForModifiers(_ flags: NSEvent.ModifierFlags) {
        guard let contentViewController = popover?.contentViewController else { return }
        let contentView = contentViewController.view
        
        for subview in contentView.subviews {
            if let label = subview as? NSTextField {
                let modifierText = formatModifiers(flags)
                if modifierText.isEmpty {
                    label.stringValue = NSLocalizedString("Press any key...", comment: "")
                } else {
                    label.stringValue = "\(modifierText) + ?"
                }
                break
            }
        }
    }
    
    private func updatePopoverText(for event: RecordedEvent) {
        guard let contentViewController = popover?.contentViewController else {
            return
        }
        
        let contentView = contentViewController.view
        
        // 查找 NSTextField 并更新文本
        for subview in contentView.subviews {
            if let label = subview as? NSTextField {
                label.stringValue = "[\(event.displayName())] Recorded"
                break
            }
        }
    }
    
    // 格式化修饰键显示
    private func formatModifiers(_ flags: NSEvent.ModifierFlags) -> String {
        // 在popover预览中我们不知道用户即将按下的是否为F键，所以不排除Fn
        return flags.formattedString()
    }
    
    // 显示取消录制提示
    private func updatePopoverTextForCancellation() {
        guard let contentViewController = popover?.contentViewController else { return }
        let contentView = contentViewController.view
        
        for subview in contentView.subviews {
            if let label = subview as? NSTextField {
                label.stringValue = "Recording cancelled"
                label.textColor = NSColor.secondaryLabelColor
                break
            }
        }
    }
    
    // MARK: - Timeout Protection
    private func startTimeoutTimer() {
        cancelTimeoutTimer()
        recordTimeoutTimer = Timer.scheduledTimer(withTimeInterval: RECORD_TIMEOUT, repeats: false) { [weak self] _ in
            NSLog("[EventRecorder] Recording timed out after 3 seconds")
            self?.stopRecording()
        }
    }
    private func cancelTimeoutTimer() {
        recordTimeoutTimer?.invalidate()
        recordTimeoutTimer = nil
    }
}

// MARK: - NSEvent.ModifierFlags Extension
extension NSEvent.ModifierFlags {
    /// 格式化修饰键为显示字符串
    func formattedString(excludeFnForFunctionKeys keyCode: UInt16? = nil) -> String {
        var components: [String] = []
        
        if contains(.command) { components.append("⌘") }
        if contains(.option) { components.append("⌥") }
        if contains(.control) { components.append("⌃") }
        if contains(.shift) { components.append("⇧") }
        if contains(.function) {
            // 如果是Fn+F键组合，隐去Fn避免误导
            if let keyCode = keyCode, isFunctionKey(keyCode) {
                // Fn+F键组合不显示Fn
            } else {
                components.append("Fn")
            }
        }
        
        return components.joined(separator: " ")
    }
    
    /// 检查是否为F键
    private func isFunctionKey(_ keyCode: UInt16) -> Bool {
        let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 111, 103, 109, 105, 107, 113]
        return functionKeyCodes.contains(keyCode)
    }
}
