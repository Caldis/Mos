//
//  EventRecorder.swift
//  Mos
//
//  Created by Claude on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

protocol EventRecorderDelegate: AnyObject {
    func eventRecorder(_ recorder: EventRecorder, didRecordButton buttonNumber: Int)
}

class EventRecorder: NSObject {
    
    // Delegate
    weak var delegate: EventRecorderDelegate?
    // Recording
    private var interceptor: Interceptor?
    private var isRecording = false
    private var recordTimeoutTimer: Timer? // 超时保护定时器
    // Popover
    private var popover: NSPopover?
    private weak var popoverSourceView: NSView?
    
    // MARK: - Life Cycle
    deinit {
        cancelTimeoutTimer()
        stopRecording()
    }
    
    // MARK: - Event Masks
    // 事件掩码 (目前仅支持鼠标按钮)
    private var mouseEventMask: CGEventMask {
        let leftDown = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let rightDown = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        let otherDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        return leftDown | rightDown | otherDown
    }
    
    // MARK: - Recording Manager
    // 开始记录事件
    func startRecording(from sourceView: NSView) {
        // Guard: 防止重复执行
        guard !isRecording else { return }
        isRecording = true
        // 确保清理任何存在的 popover
        hidePopover()
        // Log
        NSLog("startRecording")
        // 监听事件
        do {
            // 使用通知转发回调
            let callback: CGEventTapCallBack = { (proxy, type, event, refcon) in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MouseEventRecorded"),
                        object: Int(event.getIntegerValueField(.mouseEventButtonNumber))
                    )
                }
                return nil
            }
            // 启动拦截器
            interceptor = try Interceptor(
                event: mouseEventMask,
                handleBy: callback,
                listenOn: CGEventTapLocation.cgSessionEventTap,
                placeAt: CGEventTapPlacement.headInsertEventTap,
                for: CGEventTapOptions.defaultTap
            )
            // 监听回调事件通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRecordedEvent(_:)),
                name: NSNotification.Name("MouseEventRecorded"),
                object: nil
            )
            // 展示 Popover
            showPopover(at: sourceView)
            // 启动3秒超时保护定时器
            startTimeoutTimer()
            // Log
            NSLog("[EventRecorder] Started recording mouse events")
        } catch {
            NSLog("[EventRecorder] Failed to start recording: \(error)")
            // 如果创建失败，重置状态
            isRecording = false
        }
    }
    // 通知事件处理
    @objc private func handleRecordedEvent(_ notification: NSNotification) {
        // Guard: 需要 Recording 才进行后续处理
        guard isRecording else { return }
        // Guard: 获取 button number
        guard let buttonNumber = notification.object as? Int else { return }
        // 更新 popover 显示操作的按键
        updatePopoverText(for: buttonNumber)
        // 关闭 popover (延迟 300ms 确保能看完提示)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.hidePopover()
        }
        // 将结果发给 delegate
        self.delegate?.eventRecorder(self, didRecordButton: buttonNumber)
        // 停止录制
        self.stopRecording()
    }
    // 停止记录
    func stopRecording() {
        // Guard: 需要 Recording 才进行后续处理
        guard isRecording else { return }
        // Log
        NSLog("[EventRecorder] Stopping recording mouse events")
        // 取消超时定时器
        cancelTimeoutTimer()
        // 取消通知和监听
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("MouseEventRecorded"), object: nil)
        interceptor?.stop()
        interceptor = nil
        // 重置状态 (添加延迟确保能看完动画不会导致多个 popover 重复出现导致卡住)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isRecording = false
            NSLog("[EventRecorder] Recording fully stopped")
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
    
    private func hidePopover() {
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
        default:
            return "Other Button (\(buttonNumber + 1))"
        }
    }
    
    // MARK: - Timeout Protection
    private func startTimeoutTimer() {
        cancelTimeoutTimer()
        recordTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            NSLog("[EventRecorder] Recording timed out after 3 seconds")
            self?.stopRecording()
        }
    }
    private func cancelTimeoutTimer() {
        recordTimeoutTimer?.invalidate()
        recordTimeoutTimer = nil
    }
}

// MARK: - NSPopoverDelegate
extension EventRecorder: NSPopoverDelegate {
    // 关闭 Popover 时连带停止 recording
    func popoverDidClose(_ notification: Notification) {
        stopRecording()
    }
}
