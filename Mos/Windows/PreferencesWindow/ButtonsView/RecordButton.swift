//
//  RecordButton.swift
//  Mos
//
//  Created by 陈标 on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import AppKit

class RecordButton: NSVisualEffectView {
    
    private var recorder = EventRecorder()
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupAppearance()
        setupTrackingArea()
        setupRecorder()
    }
    
    // MARK: - 按键样式和交互处理
    // 样式
    private func setupAppearance() {
        // 使用语义化material，系统自动适配外观
        self.material = .hudWindow
        self.blendingMode = .withinWindow
        self.state = .active
        self.wantsLayer = true
        self.layer?.cornerRadius = 8.0
        
        // 为Light和Dark模式设置不同的配色
        let backgroundColor: NSColor
        let borderColor: NSColor
        
        if NSApp.effectiveAppearance.name == NSAppearance.Name.darkAqua {
            // Dark模式：保持原有配色
            backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.6)
            borderColor = NSColor.selectedControlColor
        } else {
            // Light模式：使用更适合的配色
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
            borderColor = NSColor.controlAccentColor.withAlphaComponent(0.3)
        }
        
        self.layer?.backgroundColor = backgroundColor.cgColor
        self.layer?.borderColor = borderColor.cgColor
        self.layer?.borderWidth = 0.5
        self.layer?.masksToBounds = true
    }
    // Hover 效果处理
    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: self.bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
    }
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            let hoverColor: NSColor
            if NSApp.effectiveAppearance.name == NSAppearance.Name.darkAqua {
                hoverColor = NSColor.selectedControlColor.withAlphaComponent(0.8)
            } else {
                hoverColor = NSColor.controlAccentColor.withAlphaComponent(0.25)
            }
            self.layer?.backgroundColor = hoverColor.cgColor
        })
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            let normalColor: NSColor
            if NSApp.effectiveAppearance.name == NSAppearance.Name.darkAqua {
                normalColor = NSColor.selectedControlColor.withAlphaComponent(0.6)
            } else {
                normalColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
            }
            self.layer?.backgroundColor = normalColor.cgColor
        })
    }
    // Click 回调
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        startRecording()
    }
}

// MARK: - MouseEventRecorderDelegate
extension RecordButton: EventRecorderDelegate {
    // 初始化 delegate
    private func setupRecorder() {
        recorder.delegate = self
    }
    // 开始录制事件
    private func startRecording() {
        recorder.startRecording(from: self)
    }
    // 事件回调
    func eventRecorder(_ recorder: EventRecorder, didRecordEvent event: RecordedEvent) {
        NSLog("[RecordButton] Recorded event: \(event.displayName())")
    }
}
