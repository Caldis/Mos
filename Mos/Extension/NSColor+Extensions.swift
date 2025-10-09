//
//  NSColor+Extensions.swift
//  Mos
//  NSColor 相关的扩展方法
//  Created by Claude on 2025/10/05
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

extension NSColor {
    static let mainBlue = NSColor(calibratedRed: 41/255, green: 108/255, blue: 255/255, alpha: 1.0)
    static let mainGreen = NSColor(calibratedRed: 0.15, green: 0.65, blue: 0.30, alpha: 1.0)
    static func getMainLightBlack(for view: NSView?) -> NSColor {
        return Utils.isDarkMode(for: view)
            ? NSColor(calibratedWhite: 0.5, alpha: 0.2)
            : NSColor(calibratedWhite: 0.0, alpha: 0.1)
    }
    static func getWarningColor(for view: NSView?) -> NSColor {
        return Utils.isDarkMode(for: view)
            ? NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.20, alpha: 1.0)
            : NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.30, alpha: 1.0)
    }

    // MARK: - PrimaryButton Colors

    /// PrimaryButton 背景色 (普通状态)
    static func getPrimaryButtonBackground(for view: NSView?) -> NSColor {
        return Utils.isDarkMode(for: view)
            ? NSColor(red: 0.08, green: 0.26, blue: 0.52, alpha: 0.75)
            : NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.15)
    }

    /// PrimaryButton 背景色 (Hover 状态)
    static func getPrimaryButtonBackgroundHovered(for view: NSView?) -> NSColor {
        return Utils.isDarkMode(for: view)
            ? NSColor(red: 0.08, green: 0.26, blue: 0.52, alpha: 0.95)
            : NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.25)
    }

    /// PrimaryButton 边框色
    static func getPrimaryButtonBorder(for view: NSView?) -> NSColor {
        return Utils.isDarkMode(for: view)
            ? NSColor(red: 0.36, green: 0.64, blue: 1.0, alpha: 1.0)
            : NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.6)
    }
}

