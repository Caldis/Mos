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
        self.material = .dark
        self.blendingMode = .withinWindow
        self.state = .active
        self.wantsLayer = true
        self.layer?.cornerRadius = 8.0
        self.layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.6).cgColor
        self.layer?.borderColor = NSColor.selectedControlColor.cgColor
        self.layer?.borderWidth = 0.5
        self.layer?.masksToBounds = true // Ensure background color shows over visual effect
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
            self.layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.8).cgColor
        })
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.6).cgColor
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
    func eventRecorder(_ recorder: EventRecorder, didRecordButton buttonNumber: Int) {
        NSLog("Recorded mouse button: \(buttonNumber)")
    }
}
