//
//  MouseEventRecorder.swift
//  Mos
//
//  Created by Claude on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

protocol MouseEventRecorderDelegate: AnyObject {
    func mouseEventRecorder(_ recorder: MouseEventRecorder, didRecordButton buttonNumber: Int)
}

class MouseEventRecorder: NSObject {
    
    weak var delegate: MouseEventRecorderDelegate?
    private var interceptor: Interceptor?
    private var isRecording = false
    
    // Popover for recording status
    private var popover: NSPopover?
    private weak var sourceView: NSView?
    
    // 超时保护定时器
    private var timeoutTimer: Timer?
    
    // 鼠标按钮事件掩码
    private var mouseEventMask: CGEventMask {
        let leftDown = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let rightDown = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        let otherDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        return leftDown | rightDown | otherDown
    }
    
    // 开始记录鼠标事件
    func startRecording(from sourceView: NSView) {
        // 立即设置录制状态，防止重入
        guard !isRecording else { return }
        isRecording = true
        
        // 确保清理任何存在的 popover
        if popover != nil {
            hideRecordingPopover()
        }
        
        
            NSLog("startRecording")
        
        self.sourceView = sourceView
        
        // 使用通知的方式来避免复杂的回调参数传递
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) in
            // 获取按钮编号
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            
            // 使用通知发送到主队列
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("MouseEventRecorded"),
                    object: Int(buttonNumber)
                )
            }
            
            // 消费事件，防止传递到其他应用
            return nil
        }
        
        do {
            interceptor = try Interceptor(
                event: mouseEventMask,
                handleBy: callback,
                listenOn: CGEventTapLocation.cgSessionEventTap,
                placeAt: CGEventTapPlacement.headInsertEventTap,
                for: CGEventTapOptions.defaultTap
            )
            
            // 监听通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRecordedEvent(_:)),
                name: NSNotification.Name("MouseEventRecorded"),
                object: nil
            )
            
            showRecordingPopover()
            
            // 启动3秒超时保护定时器
            startTimeoutTimer()
            
            NSLog("[MouseEventRecorder] Started recording mouse events")
        } catch {
            NSLog("[MouseEventRecorder] Failed to start recording: \(error)")
            // 如果创建失败，重置状态
            isRecording = false
        }
    }
    
    @objc private func handleRecordedEvent(_ notification: NSNotification) {
        guard let buttonNumber = notification.object as? Int, isRecording else { return }
        
        // 取消超时定时器，因为已经有操作了
        cancelTimeoutTimer()
        
        // 先更新 popover 文本显示按键
        updatePopoverText(for: buttonNumber)
        
        // 延迟停止录制，让用户看到按键信息
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.stopRecording()
            self.delegate?.mouseEventRecorder(self, didRecordButton: buttonNumber)
        }
    }
    
    // 停止记录
    func stopRecording() {
        guard isRecording else { return }
        
        NSLog("[MouseEventRecorder] Stopping recording mouse events")
        
        // 取消超时定时器
        cancelTimeoutTimer()
        
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("MouseEventRecorded"), object: nil)
        interceptor?.stop()
        interceptor = nil
        
        // 延迟 300ms 关闭 popover 和重置状态，等待动画完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.hideRecordingPopover()
            self?.isRecording = false
            NSLog("[MouseEventRecorder] Recording fully stopped")
        }
    }
    
    var recording: Bool {
        return isRecording
    }
    
    // MARK: - Popover Management
    
    private func showRecordingPopover() {
        guard let sourceView = sourceView else { return }
        
        // 强制关闭并等待任何现有的 popover 完全关闭
        if let existingPopover = popover {
            existingPopover.close() // 使用 close() 而不是 performClose()，确保立即关闭
            popover = nil
        }
        
        // 确保 popover 为 nil 后再创建新的
        guard popover == nil else { return }
        
        // 创建 popover 内容
        let contentController = NSViewController()
        let contentView = NSView()
        contentView.wantsLayer = true
        
        let label = NSTextField(labelWithString: NSLocalizedString("Recording mouse button...", comment: ""))
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            contentView.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        contentController.view = contentView
        
        // 创建并配置 popover
        let newPopover = NSPopover()
        newPopover.contentViewController = contentController
        newPopover.behavior = .transient
        newPopover.delegate = self
        
        // 设置引用并显示
        popover = newPopover
        newPopover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }
    
    private func hideRecordingPopover() {
        if let currentPopover = popover {
            currentPopover.close() // 使用 close() 确保立即关闭
            popover = nil
        }
    }
    
    private func updatePopoverText(for buttonNumber: Int) {
        guard let contentViewController = popover?.contentViewController else {
            return
        }
        
        let contentView = contentViewController.view
        
        // 查找 NSTextField 并更新文本
        for subview in contentView.subviews {
            if let label = subview as? NSTextField {
                let buttonName = getButtonName(for: buttonNumber)
                label.stringValue = "[\(buttonName)] Pressed"
                break
            }
        }
    }
    
    private func getButtonName(for buttonNumber: Int) -> String {
        switch buttonNumber {
        case 0:
            return "Left Click"
        case 1:
            return "Right Click"
        case 2:
            return "Middle Click"
        case 3:
            return "Button 4"
        case 4:
            return "Button 5"
        default:
            return "Button \(buttonNumber + 1)"
        }
    }
    
    // MARK: - Timeout Protection
    
    private func startTimeoutTimer() {
        cancelTimeoutTimer()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            NSLog("[MouseEventRecorder] Recording timed out after 3 seconds")
            self?.stopRecording()
        }
    }
    
    private func cancelTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
    
    deinit {
        cancelTimeoutTimer()
        stopRecording()
    }
}

// MARK: - NSPopoverDelegate

extension MouseEventRecorder: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        if isRecording {
            stopRecording()
        }
    }
}
