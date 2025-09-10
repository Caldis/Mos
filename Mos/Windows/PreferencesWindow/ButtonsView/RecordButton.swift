//
//  RecordButton.swift
//  Mos
//
//  Created by 陈标 on 2025/8/31.
//  Copyright © 2025 Caldis. All rights reserved.
//

import AppKit

class RecordButton: PrimaryButton {
    
    private var recorder = EventRecorder()
    public var onRecordEnd: ((RecordedEvent) -> Void)?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        recorder.delegate = self
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        recorder.startRecording(from: self)
    }
}

// MARK: - EventRecorderDelegate
extension RecordButton: EventRecorderDelegate {
    // Record 回调
    func eventRecorder(_ recorder: EventRecorder, didRecordEvent event: RecordedEvent) {
        NSLog("[RecordButton] Recorded event: \(event.displayName())")
        onRecordEnd?(event)
    }
}
