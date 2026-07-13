//
//  GlowWindowController.swift
//  Mos
//  为宿主窗口挂载一个绘制背景光晕的透明子窗口
//  Created by Caldis on 2026/7/11. Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import MetalKit

class GlowWindowController {

    private let glowWindow: NSWindow
    private let metalView: GlowMetalView
    private weak var hostWindow: NSWindow?
    private var observers = [NSObjectProtocol]()

    // 为宿主窗口挂载光晕, 无 Metal 支持的设备返回 nil (不影响主流程)
    static func attach(to host: NSWindow, margin: CGFloat = 150) -> GlowWindowController? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let metalView = GlowMetalView(device: device, margin: margin) else { return nil }
        return GlowWindowController(host: host, metalView: metalView, margin: margin)
    }

    private init(host: NSWindow, metalView: GlowMetalView, margin: CGFloat) {
        self.hostWindow = host
        self.metalView = metalView
        // 光晕窗口: 无边框透明, 比宿主大一圈, 点击穿透
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
        // 宿主窗口尺寸变化时同步外扩范围
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: host, queue: .main
        ) { [weak self] _ in
            guard let self = self, let host = self.hostWindow else { return }
            self.glowWindow.setFrame(host.frame.insetBy(dx: -margin, dy: -margin), display: true)
        })
        // 被遮挡时暂停渲染
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: glowWindow, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.metalView.isPaused = !self.glowWindow.occlusionState.contains(.visible)
                || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        })
    }

    // 卸载光晕
    func detach() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        metalView.isPaused = true
        hostWindow?.removeChildWindow(glowWindow)
        glowWindow.orderOut(nil)
    }

    deinit {
        detach()
    }

}
