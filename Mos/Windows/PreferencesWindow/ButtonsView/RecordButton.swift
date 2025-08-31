//
//  RecordButton.swift
//  Mos
//
//  Created by 陈标 on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import AppKit

class RecordButton: NSVisualEffectView {
    
    private var mouseRecorder = MouseEventRecorder()
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupAppearance()
        setupTrackingArea()
        setupMouseRecorder()
    }
    
    private func setupAppearance() {
        self.material = .dark
        self.blendingMode = .withinWindow
        self.state = .active
        self.wantsLayer = true
        self.layer?.cornerRadius = 8.0
        self.layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.6).cgColor
        self.layer?.borderColor = NSColor.selectedControlColor.cgColor
        self.layer?.borderWidth = 0.5
        
        // Ensure background color shows over visual effect
        self.layer?.masksToBounds = true
    }
    
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
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        startRecording()
    }
    
    // MARK: - Mouse Recording
    
    private func setupMouseRecorder() {
        mouseRecorder.delegate = self
    }
    
    private func startRecording() {
        // 防止重复点击启动多次录制
        guard !mouseRecorder.recording else { return }
        
        mouseRecorder.startRecording(from: self)
    }
    
}

// MARK: - MouseEventRecorderDelegate

extension RecordButton: MouseEventRecorderDelegate {
    func mouseEventRecorder(_ recorder: MouseEventRecorder, didRecordButton buttonNumber: Int) {
        NSLog("Recorded mouse button: \(buttonNumber)")
        // 这里可以将录制的按钮信息传递给父控制器或保存到配置中
    }
}
