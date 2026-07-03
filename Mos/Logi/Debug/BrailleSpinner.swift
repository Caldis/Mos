//
//  BrailleSpinner.swift
//  Mos
//  终端风格 Braille spinner 帧驱动: 80ms/帧, 10 帧循环.
//  消费端订阅 didTickNotification 自行决定是否渲染 currentFrame.
//  Created by Mos on 2026/4/24.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation

final class BrailleSpinner {
    static let shared = BrailleSpinner()

    /// 帧切换时触发. UI 侧订阅后自己决定: 是否正在 loading + 渲染到哪个 NSTextField.
    static let didTickNotification = Notification.Name("BrailleSpinnerDidTick")

    private static let frames: [String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private static let tickInterval: TimeInterval = 0.08

    private var frameIndex: Int = 0
    private var timer: Timer?
    private var activeConsumers = 0

    /// 当前帧字符. 读者侧按需拉取.
    private(set) var currentFrame: String = BrailleSpinner.frames[0]

    private init() {}

    /// 消费方 (调试面板等) 需要动画时调用; 与 endTicking 配对。
    /// 无消费方时定时器完全停止, 避免 12.5Hz 常驻空转阻止 App Nap。
    func beginTicking() {
        activeConsumers += 1
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.frameIndex = (self.frameIndex + 1) % Self.frames.count
            self.currentFrame = Self.frames[self.frameIndex]
            NotificationCenter.default.post(name: Self.didTickNotification, object: nil)
        }
        // 主 RunLoop common modes: 让 timer 在 menu tracking / modal 期间也能 tick.
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func endTicking() {
        activeConsumers = max(0, activeConsumers - 1)
        if activeConsumers == 0 {
            timer?.invalidate()
            timer = nil
        }
    }
}
