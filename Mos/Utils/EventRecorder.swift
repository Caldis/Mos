//
//  EventRecorder.swift
//  Mos
//
//  Created by Claude on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

// MARK: - 常量定义
private struct EventRecorderConstants {
    // 通知名称
    static let recordNotificationName = NSNotification.Name("EventRecorded")
    static let modifierFlagsChangedNotificationName = NSNotification.Name("ModifierFlagsChanged")
    static let recordingCancelledNotificationName = NSNotification.Name("RecordingCancelled")
    
    // 超时时间
    static let recordTimeout: TimeInterval = 10.0
    
    // KeyCode 定义
    struct KeyCode {
        // 特殊功能键
        static let escape: UInt16 = 53
        static let space: UInt16 = 49
        static let backspace: UInt16 = 51
        static let enter: UInt16 = 76
        static let returnKey: UInt16 = 36
        static let tab: UInt16 = 48
        static let grave: UInt16 = 50 // `键
        
        // 修饰键
        static let leftCommand: UInt16 = 55
        static let rightCommand: UInt16 = 54
        static let leftShift: UInt16 = 56
        static let rightShift: UInt16 = 60
        static let leftOption: UInt16 = 58
        static let rightOption: UInt16 = 61
        static let leftControl: UInt16 = 59
        static let rightControl: UInt16 = 62
        static let function: UInt16 = 179
        
        static let modifierKeys: Set<UInt16> = [54, 55, 58, 59, 60, 61, 62, 179]
        
        // F键系列
        static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 111, 103, 109, 105, 107, 113]
        
        // 完整键盘映射
        static let keyMap: [UInt16: String] = [
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
    }
}

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
        return EventRecorderConstants.KeyCode.modifierKeys.contains(keyCode)
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
            case 0: components.append("🖱L") // 左键
            case 1: components.append("🖱R") // 右键
            case 2: components.append("🖱M") // 中键
            default: components.append("🖱\(mouseButton + 1)") // 其他鼠标按键
            }
        }
        
        if let keyCode = keyCode {
            components.append(keyCodeToString(keyCode))
        }
        
        return components.joined(separator: " + ")
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        return EventRecorderConstants.KeyCode.keyMap[keyCode] ?? "Key(\(keyCode))"
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
    // 呼吸动画引用
    private var breathingAnimation: NSView?
    
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
                name: EventRecorderConstants.recordNotificationName,
                object: nil
            )
            // 监听修饰键变化通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleModifierFlagsChanged(_:)),
                name: EventRecorderConstants.modifierFlagsChangedNotificationName,
                object: nil
            )
            // 监听录制取消通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRecordingCancelled(_:)),
                name: EventRecorderConstants.recordingCancelledNotificationName,
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
                                name: EventRecorderConstants.modifierFlagsChangedNotificationName,
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
                                name: EventRecorderConstants.recordNotificationName,
                                object: recordedEvent
                            )
                        }
                    case .keyDown:
                        // 其他键盘按键
                        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                        
                        // ESC键特殊处理：取消录制
                        if keyCode == EventRecorderConstants.KeyCode.escape {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: EventRecorderConstants.recordingCancelledNotificationName,
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
                                    name: EventRecorderConstants.recordNotificationName,
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
        // 停止呼吸动画（录制取消）
        stopBreathingAnimation()
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
        // 停止呼吸动画（录制完成）
        stopBreathingAnimation()
        // 更新 popover 显示操作的按键
        updatePopoverText(for: event)
        // 将结果发给 delegate
        self.delegate?.eventRecorder(self, didRecordEvent: event)
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
        // 隐藏 Popover
        hidePopover()
        // 取消超时定时器
        cancelTimeoutTimer()
        // 取消通知和监听
        interceptor?.stop()
        interceptor = nil
        NotificationCenter.default.removeObserver(self, name: EventRecorderConstants.recordNotificationName, object: nil)
        NotificationCenter.default.removeObserver(self, name: EventRecorderConstants.modifierFlagsChangedNotificationName, object: nil)
        NotificationCenter.default.removeObserver(self, name: EventRecorderConstants.recordingCancelledNotificationName, object: nil)
        // 重置状态 (添加延迟确保 Popover 结束动画完成, 避免多个 popover 重复出现导致卡住)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isRecording = false
            self?.isRecorded = false
            self?.currentModifiers = NSEvent.ModifierFlags()
            NSLog("[EventRecorder] Stopped")
        }
    }
    
    // MARK: - Popover Management
    
    // 创建带样式的按键视图
    private func createKeyView(for text: String, isRecorded: Bool = false) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = isRecorded ? NSColor.systemGreen.cgColor : NSColor.quaternaryLabelColor.cgColor
        container.layer?.cornerRadius = 4
        
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = isRecorded ? NSColor.white : NSColor.labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 12),
            container.heightAnchor.constraint(equalToConstant: 20),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 20)
        ])
        
        // 如果是"?"，添加呼吸动画
        if text == "?" && !isRecorded {
            startBreathingAnimation(for: container)
            breathingAnimation = container // 保存引用用于后续停止动画
        }
        
        return container
    }
    
    // 创建按键序列的水平布局
    private func createKeySequenceView(for components: [String], isRecorded: Bool = false, showSeparators: Bool = true) -> NSView {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        for (index, component) in components.enumerated() {
            if index > 0 && showSeparators {
                // 添加"+"分隔符
                let plusLabel = NSTextField(labelWithString: "+")
                plusLabel.font = NSFont.systemFont(ofSize: 11)
                plusLabel.textColor = NSColor.secondaryLabelColor
                stackView.addArrangedSubview(plusLabel)
            }
            
            // 添加按键视图
            let keyView = createKeyView(for: component, isRecorded: isRecorded)
            stackView.addArrangedSubview(keyView)
        }
        
        return stackView
    }
    
    // 开始呼吸动画
    private func startBreathingAnimation(for view: NSView) {
        // 确保视图有layer
        view.wantsLayer = true
        
        // 创建呼吸动画（透明度从1.0到0.3再回到1.0）
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 0.35
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        view.layer?.add(animation, forKey: "breathingAnimation")
    }
    
    // 停止呼吸动画
    private func stopBreathingAnimation() {
        breathingAnimation?.layer?.removeAnimation(forKey: "breathingAnimation")
        breathingAnimation?.layer?.opacity = 1.0 // 恢复完全不透明
        breathingAnimation = nil
    }
    
    private func showPopover(at sourceView: NSView?) {
        // Guard: 没有 sourceView 直接不展示
        guard let sourceView = sourceView else { return }
        // 清理现有 popover
        hidePopover()
        
        // 创建 popover 内容
        let contentController = NSViewController()
        let contentView = NSView()
        contentView.wantsLayer = true
        
        // 创建初始提示标签
        let instructionLabel = NSTextField(labelWithString: NSLocalizedString("Press any key...", comment: ""))
        instructionLabel.font = NSFont.systemFont(ofSize: 13)
        instructionLabel.textColor = NSColor.secondaryLabelColor
        instructionLabel.alignment = .center
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(instructionLabel)
        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            instructionLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 165),
            contentView.heightAnchor.constraint(equalToConstant: 50)
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
        stopBreathingAnimation() // 隐藏popover时停止动画
        if let currentPopover = popover {
            currentPopover.close() // 使用 close() 确保立即关闭
            popover = nil
        }
    }
    
    // 为修饰键实时更新popover显示
    private func updatePopoverForModifiers(_ flags: NSEvent.ModifierFlags) {
        guard let contentViewController = popover?.contentViewController else { return }
        let contentView = contentViewController.view
        
        // 停止之前的呼吸动画
        stopBreathingAnimation()
        // 清除现有内容
        contentView.subviews.forEach { $0.removeFromSuperview() }
        
        let modifierString = formatModifiers(flags)
        
        if modifierString.isEmpty {
            // 没有修饰键，显示原始提示
            let instructionLabel = NSTextField(labelWithString: NSLocalizedString("Press any key...", comment: ""))
            instructionLabel.font = NSFont.systemFont(ofSize: 13)
            instructionLabel.textColor = NSColor.secondaryLabelColor
            instructionLabel.alignment = .center
            instructionLabel.translatesAutoresizingMaskIntoConstraints = false
            
            contentView.addSubview(instructionLabel)
            NSLayoutConstraint.activate([
                instructionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                instructionLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        } else {
            // 有修饰键，显示按键组合预览（修饰键作为一个整体块显示）
            let components = [modifierString, "?"]  // 修饰键 + "?" 提示
            
            let keySequenceView = createKeySequenceView(for: components, showSeparators: true)
            contentView.addSubview(keySequenceView)
            
            NSLayoutConstraint.activate([
                keySequenceView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                keySequenceView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        }
    }
    
    private func updatePopoverText(for event: RecordedEvent) {
        guard let contentViewController = popover?.contentViewController else { return }
        let contentView = contentViewController.view
        
        // 清除现有内容
        contentView.subviews.forEach { $0.removeFromSuperview() }
        
        // 解析按键组合并创建样式化视图（绿色背景表示已录制）
        let displayName = event.displayName()
        let components = displayName.components(separatedBy: " + ").filter { !$0.isEmpty }
        
        let keySequenceView = createKeySequenceView(for: components, isRecorded: true)
        
        contentView.addSubview(keySequenceView)
        NSLayoutConstraint.activate([
            keySequenceView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            keySequenceView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    // 格式化修饰键显示（预览时用紧凑格式，和录制成功时保持一致）
    private func formatModifiers(_ flags: NSEvent.ModifierFlags) -> String {
        return flags.formattedString()
    }
    
    // 显示取消录制提示
    private func updatePopoverTextForCancellation() {
        guard let contentViewController = popover?.contentViewController else { return }
        let contentView = contentViewController.view
        
        // 清除现有内容
        contentView.subviews.forEach { $0.removeFromSuperview() }
        
        // 创建取消提示
        let cancelledLabel = NSTextField(labelWithString: "Recording cancelled")
        cancelledLabel.font = NSFont.systemFont(ofSize: 13)
        cancelledLabel.textColor = NSColor.systemOrange
        cancelledLabel.alignment = .center
        cancelledLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(cancelledLabel)
        NSLayoutConstraint.activate([
            cancelledLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cancelledLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    // MARK: - Timeout Protection
    private func startTimeoutTimer() {
        cancelTimeoutTimer()
        recordTimeoutTimer = Timer.scheduledTimer(withTimeInterval: EventRecorderConstants.recordTimeout, repeats: false) { [weak self] _ in
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
        return EventRecorderConstants.KeyCode.functionKeys.contains(keyCode)
    }
}
