//
//  GlowWindowController.swift
//  Mos
//  为宿主窗口挂载一个绘制背景光晕的透明子窗口
//  Created by Caldis on 2026/7/11. Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import MetalKit

class GlowWindowController {

    // 当前生效的光晕实例 (供 GlowDebugPanel 操控)
    private(set) static weak var active: GlowWindowController?

    private let glowWindow: NSWindow
    private let metalView: GlowMetalView
    private weak var hostWindow: NSWindow?
    private var observers = [NSObjectProtocol]()

    // 暂停/恢复渲染
    var isPaused: Bool {
        get { metalView.isPaused }
        set { metalView.isPaused = newValue }
    }

    // 为宿主窗口挂载光晕, 无 Metal 支持的设备返回 nil (不影响主流程)
    static func attach(to host: NSWindow) -> GlowWindowController? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let metalView = GlowMetalView(device: device) else { return nil }
        return GlowWindowController(host: host, metalView: metalView)
    }

    private init(host: NSWindow, metalView: GlowMetalView) {
        self.hostWindow = host
        self.metalView = metalView
        // 光晕窗口: 无边框透明, 比宿主大一圈, 点击穿透
        let margin = CGFloat(GlowParams.shared.margin)
        glowWindow = NSWindow(
            contentRect: host.frame.insetBy(dx: -margin, dy: -margin),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        glowWindow.isOpaque = false
        glowWindow.backgroundColor = .clear
        glowWindow.hasShadow = false
        glowWindow.ignoresMouseEvents = true
        glowWindow.isReleasedWhenClosed = false
        glowWindow.contentView = metalView
        // 垫在宿主窗口下方, 拖动时自动跟随
        host.addChildWindow(glowWindow, ordered: .below)
        // 位置补偿 1/2: 每帧绘制前校验相对位置 —— child window 机制在快速拖拽/
        // 瞬间松手时会丢失最终位置更新, 任何错位最多存活一帧 (16ms) 即被校正
        metalView.frameSync = { [weak self] in self?.syncFrameToHost() }
        // 位置补偿 2/2: 移动/缩放通知兜底, 渲染暂停 (遮挡/减弱动态效果) 时也能校正
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: host, queue: .main
            ) { [weak self] _ in
                self?.syncFrameToHost()
            })
        }
        // 被遮挡时暂停渲染
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: glowWindow, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.metalView.isPaused = !self.glowWindow.occlusionState.contains(.visible)
                || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        })
        Self.active = self
    }

    // 将光晕窗口校正到宿主窗口外扩 margin 的位置 (margin 可被调试面板实时修改)
    func syncFrameToHost() {
        guard let host = hostWindow else { return }
        let margin = CGFloat(GlowParams.shared.margin)
        let desired = host.frame.insetBy(dx: -margin, dy: -margin)
        if glowWindow.frame != desired {
            glowWindow.setFrame(desired, display: false)
        }
    }

    // 卸载光晕
    func detach() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        metalView.frameSync = nil
        metalView.isPaused = true
        hostWindow?.removeChildWindow(glowWindow)
        glowWindow.orderOut(nil)
        if Self.active === self {
            Self.active = nil
        }
    }

    deinit {
        detach()
    }

}
