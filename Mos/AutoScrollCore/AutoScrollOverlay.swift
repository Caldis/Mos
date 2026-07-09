//
//  AutoScrollOverlay.swift
//  Mos
//  自动滚动覆盖窗口 - 在初始点击位置显示固定图标
//  Created by Auto-Scroll Implementation on 2025/11/29.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class AutoScrollOverlay {

    private var overlayWindow: NSWindow?
    private var imageView: NSImageView?

    /// 在指定位置显示自动滚动图标
    func show(at point: CGPoint) {
        NSLog("[AutoScrollOverlay] ========== SHOW SVG ==========")
        NSLog("[AutoScrollOverlay] Received point (NSScreen coords): (\(point.x), \(point.y))")

        // CRITICAL: Always hide any existing window first to ensure clean state
        if overlayWindow != nil {
            NSLog("[AutoScrollOverlay] WARNING: overlayWindow exists! Hiding first...")
            hide()
        }

        // Get current actual mouse position to compare
        let actualMouse = NSEvent.mouseLocation
        NSLog("[AutoScrollOverlay] Actual mouse position NOW: (\(actualMouse.x), \(actualMouse.y))")
        NSLog("[AutoScrollOverlay] Difference: dx=\(actualMouse.x - point.x), dy=\(actualMouse.y - point.y)")

        // Find which screen contains this point
        var containingScreen: NSScreen?
        for screen in NSScreen.screens {
            if NSPointInRect(point, screen.frame) {
                containingScreen = screen
                NSLog("[AutoScrollOverlay] Point is on screen: \(screen.frame)")
                break
            }
        }

        if containingScreen == nil {
            NSLog("[AutoScrollOverlay] WARNING: Point not in any screen! Using main screen")
            containingScreen = NSScreen.main
        }

        // 创建图标图像
        let iconSize: CGFloat = 32
        let image = createAutoScrollIcon(size: iconSize)

        // 创建图像视图
        imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))
        imageView?.image = image

        // CRITICAL: NSEvent.mouseLocation and NSWindow coordinates use a global coordinate space
        // where Y=0 is at the BOTTOM of the primary screen, and extends across all screens
        // The point parameter should already be in this coordinate space
        // Just center the icon on the point
        let windowRect = NSRect(
            x: point.x - iconSize / 2,
            y: point.y - iconSize / 2,
            width: iconSize,
            height: iconSize
        )

        NSLog("[AutoScrollOverlay] Requested windowRect: \(windowRect)")
        NSLog("[AutoScrollOverlay] Window center will be: (\(windowRect.midX), \(windowRect.midY))")

        overlayWindow = NSWindow(
            contentRect: windowRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        overlayWindow?.backgroundColor = .clear
        overlayWindow?.isOpaque = false
        overlayWindow?.hasShadow = false
        overlayWindow?.level = .statusBar
        overlayWindow?.ignoresMouseEvents = true
        overlayWindow?.contentView = imageView
        overlayWindow?.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        overlayWindow?.orderFrontRegardless()

        // Verify the actual window position after creation
        if let actualFrame = overlayWindow?.frame {
            NSLog("[AutoScrollOverlay] Actual window frame: \(actualFrame)")
            NSLog("[AutoScrollOverlay] Actual window center: (\(actualFrame.midX), \(actualFrame.midY))")
            NSLog("[AutoScrollOverlay] Position difference from requested: dx=\(actualFrame.origin.x - windowRect.origin.x), dy=\(actualFrame.origin.y - windowRect.origin.y)")

            // Write to file for easy checking
            let timestamp = Date()
            let screenInfo = containingScreen.map { "Screen: \($0.frame)" } ?? "Screen: UNKNOWN"
            let log = """
            ========== SVG POSITIONING @ \(timestamp) ==========
            \(screenInfo)
            Received point: (\(point.x), \(point.y))
            Actual mouse NOW: (\(actualMouse.x), \(actualMouse.y))
            Mouse difference: dx=\(actualMouse.x - point.x), dy=\(actualMouse.y - point.y)

            Requested window: \(windowRect)
            Actual window: \(actualFrame)
            Window difference: dx=\(actualFrame.origin.x - windowRect.origin.x), dy=\(actualFrame.origin.y - windowRect.origin.y)

            Center offset from mouse: dx=\(actualFrame.midX - actualMouse.x), dy=\(actualFrame.midY - actualMouse.y)

            Point in windowRect: \(NSPointInRect(point, windowRect))
            Mouse in actualFrame: \(NSPointInRect(actualMouse, actualFrame))
            ====================================

            """
            // Append to file to track multiple clicks
            if let handle = FileHandle(forWritingAtPath: "/tmp/mos_svg_position.txt") {
                handle.seekToEndOfFile()
                if let data = log.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try? log.write(toFile: "/tmp/mos_svg_position.txt", atomically: false, encoding: .utf8)
            }
        }
        NSLog("[AutoScrollOverlay] Window shown: \(overlayWindow?.isVisible ?? false)")
        NSLog("[AutoScrollOverlay] ========================================")
    }

    /// 隐藏覆盖窗口
    func hide() {
        NSLog("[AutoScrollOverlay] Hiding overlay, window exists: \(overlayWindow != nil)")
        if let window = overlayWindow {
            window.orderOut(nil)
            // Don't call close() - just hide and release
        }
        overlayWindow = nil
        imageView = nil
        NSLog("[AutoScrollOverlay] Overlay hidden and cleared")
    }

    /// 创建自动滚动图标（基于SVG参考）
    private func createAutoScrollIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()

        let isDarkMode = Options.shared.autoScroll.darkMode

        // 绘制背景圆圈（如果启用深色模式）
        if isDarkMode {
            NSColor.white.withAlphaComponent(0.95).set()
            let background = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: size - 2, height: size - 2))
            background.fill()
        }

        // 缩放和翻转Y轴（SVG坐标系与NSView坐标系相反）
        // 使用更小的缩放比例，让SVG图标不触碰圆圈边界
        let scale = (size * 0.85) / 16.0  // 减小到85%，留出15%的边距
        let offset = size * 0.075  // 居中偏移量
        let transform = NSAffineTransform()
        transform.translateX(by: offset, yBy: size - offset)
        transform.scaleX(by: scale, yBy: -scale)
        transform.concat()

        // 设置图标颜色：深色模式用黑色，否则用灰色 #b5b5b5
        let iconColor = isDarkMode ? NSColor.black : NSColor(red: 0xb5/255.0, green: 0xb5/255.0, blue: 0xb5/255.0, alpha: 1.0)
        iconColor.setFill()

        // Path 1: 中心圆圈 (circle at center)
        let centerCircle = NSBezierPath()
        centerCircle.appendOval(in: NSRect(x: 6, y: 6, width: 4, height: 4))
        let innerCircle = NSBezierPath()
        innerCircle.appendOval(in: NSRect(x: 7, y: 7, width: 2, height: 2))
        centerCircle.append(innerCircle.reversed)
        centerCircle.fill()

        // Path 2: 下箭头
        let downArrow = NSBezierPath()
        downArrow.move(to: NSPoint(x: 8, y: 13.585))
        downArrow.line(to: NSPoint(x: 5.2, y: 10.79))
        downArrow.line(to: NSPoint(x: 4.5, y: 11.5))
        downArrow.line(to: NSPoint(x: 8, y: 15))
        downArrow.line(to: NSPoint(x: 11.5, y: 11.5))
        downArrow.line(to: NSPoint(x: 10.795, y: 10.795))
        downArrow.line(to: NSPoint(x: 8, y: 13.585))
        downArrow.close()
        downArrow.fill()

        // Path 3: 上箭头
        let upArrow = NSBezierPath()
        upArrow.move(to: NSPoint(x: 8, y: 2.415))
        upArrow.line(to: NSPoint(x: 10.79, y: 5.2))
        upArrow.line(to: NSPoint(x: 11.5, y: 4.5))
        upArrow.line(to: NSPoint(x: 8, y: 1))
        upArrow.line(to: NSPoint(x: 4.5, y: 4.5))
        upArrow.line(to: NSPoint(x: 5.205, y: 5.205))
        upArrow.line(to: NSPoint(x: 8, y: 2.415))
        upArrow.close()
        upArrow.fill()

        image.unlockFocus()

        return image
    }
}
