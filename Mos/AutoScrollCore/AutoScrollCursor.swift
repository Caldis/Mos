//
//  AutoScrollCursor.swift
//  Mos
//  自动滚动自定义光标 - 带上下箭头指示器
//  Created by Auto-Scroll Implementation on 2025/11/29.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class AutoScrollCursor {

    /// 创建带有上下箭头的自定义光标
    static func create() -> NSCursor {
        let size = CGSize(width: 48, height: 48)
        let image = NSImage(size: size)

        image.lockFocus()

        // 清除背景
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()

        // 绘制蓝色圆圈（中心指示器）- 更大更明显
        NSColor.systemBlue.withAlphaComponent(0.8).setFill()
        NSColor.white.setStroke()
        let circleRect = NSRect(x: 14, y: 14, width: 20, height: 20)
        let circlePath = NSBezierPath(ovalIn: circleRect)
        circlePath.lineWidth = 2
        circlePath.fill()
        circlePath.stroke()

        // 设置白色填充和描边用于箭头
        NSColor.white.setFill()
        NSColor.systemBlue.setStroke()

        // 绘制上箭头（更大更明显）
        let upArrow = NSBezierPath()
        upArrow.move(to: NSPoint(x: 24, y: 6))
        upArrow.line(to: NSPoint(x: 19, y: 11))
        upArrow.line(to: NSPoint(x: 22, y: 11))
        upArrow.line(to: NSPoint(x: 22, y: 13))
        upArrow.line(to: NSPoint(x: 26, y: 13))
        upArrow.line(to: NSPoint(x: 26, y: 11))
        upArrow.line(to: NSPoint(x: 29, y: 11))
        upArrow.close()
        upArrow.lineWidth = 1.5
        upArrow.fill()
        upArrow.stroke()

        // 绘制下箭头（更大更明显）
        let downArrow = NSBezierPath()
        downArrow.move(to: NSPoint(x: 24, y: 42))
        downArrow.line(to: NSPoint(x: 19, y: 37))
        downArrow.line(to: NSPoint(x: 22, y: 37))
        downArrow.line(to: NSPoint(x: 22, y: 35))
        downArrow.line(to: NSPoint(x: 26, y: 35))
        downArrow.line(to: NSPoint(x: 26, y: 37))
        downArrow.line(to: NSPoint(x: 29, y: 37))
        downArrow.close()
        downArrow.lineWidth = 1.5
        downArrow.fill()
        downArrow.stroke()

        image.unlockFocus()

        // 创建光标，热点在中心
        let hotSpot = NSPoint(x: 24, y: 24)
        return NSCursor(image: image, hotSpot: hotSpot)
    }

    /// 创建带动画效果的光标（可选，用于未来增强）
    static func createAnimated(frame: Int) -> NSCursor {
        // TODO: 实现动画光标
        return create()
    }
}
