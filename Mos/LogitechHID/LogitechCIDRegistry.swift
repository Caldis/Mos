//
//  LogitechCIDRegistry.swift
//  Mos
//  Logitech HID++ Control ID (CID) 名称注册表
//
//  数据来源: Solaar 项目
//  https://github.com/pwr-Solaar/Solaar
//  文件: lib/logitech_receiver/special_keys.py
//  Commit: b9e0cf823543ba1dadc8eb188083b5c8db6280b0
//  原始数据基于 Logitech 官方 controls.xml, 由 Solaar 社区维护和补充
//  Solaar 项目采用 GPL-2.0 许可证
//
//  Created by Mos on 2026/3/21.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation

/// Logitech HID++ Control ID (CID) 注册表
/// 提供 CID→名称查询 和 CID↔MosCode 转换
struct LogitechCIDRegistry {

    // MARK: - CID 名称表 (来自 Solaar special_keys.py CONTROL 字典)
    // 名称已格式化: 下划线→空格, 双下划线→" / "

    private static let cidNames: [UInt16: String] = [
        // --- 多媒体 & 系统控制 (0x0001~0x004F) ---
        0x0001: "Volume Up old",
        0x0002: "Volume Down old",
        0x0003: "Mute",
        0x0004: "Play / Pause old",
        0x0005: "Next",
        0x0006: "Previous",
        0x0007: "Stop",
        0x0008: "Application Switcher",
        0x0009: "Burn",
        0x000A: "Calculator",
        0x000B: "Calendar",
        0x000C: "Close",
        0x000D: "Eject",
        0x000E: "Mail",
        0x000F: "Help As HID",
        0x0010: "Help As F1",
        0x0011: "Launch Word Proc",
        0x0012: "Launch Spreadsheet",
        0x0013: "Launch Presentation",
        0x0014: "Undo As Ctrl Z",
        0x0015: "Undo As HID",
        0x0016: "Redo As Ctrl Y",
        0x0017: "Redo As HID",
        0x0018: "Print As Ctrl P",
        0x0019: "Print As HID",
        0x001A: "Save As Ctrl S",
        0x001B: "Save As HID",
        0x001C: "Preset A",
        0x001D: "Preset B",
        0x001E: "Preset C",
        0x001F: "Preset D",
        0x0020: "Favorites",
        0x0021: "Gadgets",
        0x0022: "My Home",
        0x0023: "Gadgets As Win G",
        0x0024: "Maximize As HID",
        0x0025: "Maximize As Win Shift M",
        0x0026: "Minimize As HID",
        0x0027: "Minimize As Win M",
        0x0028: "Media Player",
        0x0029: "Media Center Logi",
        0x002A: "Media Center Msft",
        0x002B: "Custom Menu",
        0x002C: "Messenger",
        0x002D: "My Documents",
        0x002E: "My Music",
        0x002F: "Webcam",
        0x0030: "My Pictures",
        0x0031: "My Videos",
        0x0032: "My Computer As HID",
        0x0033: "My Computer As Win E",
        0x0034: "FN Key",
        0x0035: "Launch Picture Viewer",
        0x0036: "One Touch Search",
        0x0037: "Preset 1",
        0x0038: "Preset 2",
        0x0039: "Preset 3",
        0x003A: "Preset 4",
        0x003B: "Record",
        0x003C: "Internet Refresh",
        0x003E: "Search",
        0x003F: "Shuffle",
        0x0040: "Sleep",
        0x0041: "Internet Stop",
        0x0042: "Synchronize",
        0x0043: "Zoom",
        0x0044: "Zoom In As HID",
        0x0045: "Zoom In As Ctrl Wheel",
        0x0046: "Zoom In As Cltr Plus",  // Solaar 原文如此 (Cltr 非 Ctrl)
        0x0047: "Zoom Out As HID",
        0x0048: "Zoom Out As Ctrl Wheel",
        0x0049: "Zoom Out As Ctrl Minus",
        0x004A: "Zoom Reset",
        0x004B: "Zoom Full Screen",
        0x004C: "Print Screen",
        0x004D: "Pause Break",
        0x004E: "Scroll Lock",
        0x004F: "Contextual Menu",
        // --- 鼠标按键 (0x0050~0x006D) ---
        0x0050: "Left Button",
        0x0051: "Right Button",
        0x0052: "Middle Button",
        0x0053: "Back Button",
        0x0054: "Back",
        0x0055: "Back As Alt Win Arrow",
        0x0056: "Forward Button",
        0x0057: "Forward As HID",
        0x0058: "Forward As Alt Win Arrow",
        0x0059: "Button 6",
        0x005A: "Left Scroll As Button 7",
        0x005B: "Left Tilt",
        0x005C: "Right Scroll As Button 8",
        0x005D: "Right Tilt",
        0x005E: "Button 9",
        0x005F: "Button 10",
        0x0060: "Button 11",
        0x0061: "Button 12",
        0x0062: "Button 13",
        0x0063: "Button 14",
        0x0064: "Button 15",
        0x0065: "Button 16",
        0x0066: "Button 17",
        0x0067: "Button 18",
        0x0068: "Button 19",
        0x0069: "Button 20",
        0x006A: "Button 21",
        0x006B: "Button 22",
        0x006C: "Button 23",
        0x006D: "Button 24",
        // --- 桌面 & 功能键 (0x006E~0x0082) ---
        0x006E: "Show Desktop",
        0x006F: "Screen Lock",
        0x0070: "Fn F1",
        0x0071: "Fn F2",
        0x0072: "Fn F3",
        0x0073: "Fn F4",
        0x0074: "Fn F5",
        0x0075: "Fn F6",
        0x0076: "Fn F7",
        0x0077: "Fn F8",
        0x0078: "Fn F9",
        0x0079: "Fn F10",
        0x007A: "Fn F11",
        0x007B: "Fn F12",
        0x007C: "Fn F13",
        0x007D: "Fn F14",
        0x007E: "Fn F15",
        0x007F: "Fn F16",
        0x0080: "Fn F17",
        0x0081: "Fn F18",
        0x0082: "Fn F19",
        // --- 移动平台 & Windows 特性 (0x0083~0x00B9) ---
        0x0083: "IOS Home",
        0x0084: "Android Home",
        0x0085: "Android Menu",
        0x0086: "Android Search",
        0x0087: "Android Back",
        0x0088: "Home Combo",
        0x0089: "Lock Combo",
        0x008A: "IOS Virtual Keyboard",
        0x008B: "IOS Language Switch",
        0x008C: "Mac Expose",
        0x008D: "Mac Dashboard",
        0x008E: "Win7 Snap Left",
        0x008F: "Win7 Snap Right",
        0x0090: "Minimize Window",
        0x0091: "Maximize Window",
        0x0092: "Win7 Stretch Up",
        0x0093: "Win7 Monitor Switch As Win Shift LeftArrow",
        0x0094: "Win7 Monitor Switch As Win Shift RightArrow",
        0x0095: "Switch Screen",
        0x0096: "Win7 Show Mobility Center",
        0x0097: "Analog HScroll",
        0x009F: "Metro Appswitch",
        0x00A0: "Metro Appbar",
        0x00A1: "Metro Charms",
        0x00A2: "Calc Vkeyboard",
        0x00A3: "Metro Search",
        0x00A4: "Combo Sleep",
        0x00A5: "Metro Share",
        0x00A6: "OS Settings",
        0x00A7: "Metro Devices",
        0x00A9: "Metro Start Screen",
        0x00AA: "Zoomin",
        0x00AB: "Zoomout",
        0x00AC: "Back Hscroll",
        0x00AE: "Show Desktop HPP",
        0x00B7: "Fn Left Click",
        0x00B8: "Second Left Click",
        0x00B9: "Fn Second Left Click",
        // --- 跨平台 & 高级功能 (0x00BA~0x00FF) ---
        0x00BA: "Multiplatform App Switch",
        0x00BB: "Multiplatform Home",
        0x00BC: "Multiplatform Menu",
        0x00BD: "Multiplatform Back",
        0x00BE: "Multiplatform Insert",
        0x00BF: "Screen Capture / Print Screen",
        0x00C0: "Fn Down",
        0x00C1: "Fn Up",
        0x00C2: "Multiplatform Lock",
        0x00C3: "Mouse Gesture Button",
        0x00C4: "Smart Shift",
        0x00C5: "Microphone",
        0x00C6: "Wifi",
        0x00C7: "Brightness Down",
        0x00C8: "Brightness Up",
        0x00C9: "Display Out / Project Screen ",  // Solaar 原文末尾有空格
        0x00CA: "View Open Apps",
        0x00CB: "View All Apps",
        0x00CC: "Switch App",
        0x00CD: "Fn Inversion Change",
        0x00CE: "MultiPlatform Back",
        0x00CF: "MultiPlatform Forward",
        0x00D0: "MultiPlatform Gesture Button",
        0x00D1: "Host Switch Channel 1",
        0x00D2: "Host Switch Channel 2",
        0x00D3: "Host Switch Channel 3",
        0x00D4: "MultiPlatform Search",
        0x00D5: "MultiPlatform Home / Mission Control",
        0x00D6: "MultiPlatform Menu / Show / Hide Virtual Keyboard / Launchpad",
        0x00D7: "Virtual Gesture Button",
        0x00D8: "Cursor Button Long Press",
        0x00D9: "Next Button Shortpress",
        0x00DA: "Next Button Long Press",
        0x00DB: "Back Button Short Press",
        0x00DC: "Back Button Long Press",
        0x00DD: "Multi Platform Language Switch",
        0x00DE: "F Lock",
        0x00DF: "Switch Highlight",
        0x00E0: "Mission Control / Task View",
        0x00E1: "Dashboard Launchpad / Action Center",
        0x00E2: "Backlight Down",
        0x00E3: "Backlight Up",
        0x00E4: "Previous Track",
        0x00E5: "Play / Pause",
        0x00E6: "Next Track",
        0x00E7: "Mute Sound",
        0x00E8: "Volume Down",
        0x00E9: "Volume Up",
        0x00EA: "App Contextual Menu / Right Click",
        0x00EB: "Right Arrow",
        0x00EC: "Left Arrow",
        0x00ED: "DPI Change",
        0x00EE: "Open New Tab",
        0x00EF: "F2",
        0x00F0: "F3",
        0x00F1: "F4",
        0x00F2: "F5",
        0x00F3: "F6",
        0x00F4: "F7",
        0x00F5: "F8",
        0x00F6: "F1",
        0x00F7: "Next Color Effect",
        0x00F8: "Increase Color Effect Speed",
        0x00F9: "Decrease Color Effect Speed",
        0x00FA: "Load Lighting Custom Profile",
        0x00FB: "Laser Button Short Press",
        0x00FC: "Laser Button Long Press",
        0x00FD: "DPI Switch",
        0x00FE: "Multiplatform Home / Show Desktop",
        0x00FF: "Multiplatform App Switch / Show Dashboard",
        // --- 扩展功能 (0x0100~0x01B4) ---
        0x0100: "Multiplatform App Switch 2",
        0x0101: "Fn Inversion / Hot Key",
        0x0102: "LeftAndRightClick",
        0x0103: "Dictation",
        0x0104: "Emoji Smiley Heart Eyes",
        0x0105: "Emoji Crying Face",
        0x0106: "Emoji Smiley",
        0x0107: "Emoji Smilie With Tears",
        0x0108: "Emoji",
        0x0109: "Multiplatform App Switch / Launchpad",
        0x010A: "Screen Capture",
        0x010B: "Grave Accent",
        0x010C: "Tab Key",
        0x010D: "Caps Lock",
        0x010E: "Left Shift",
        0x010F: "Left Control",
        0x0110: "Left Option / Start",
        0x0111: "Left Command / Alt",
        0x0112: "Right Command / Alt",
        0x0113: "Right Option / Start",
        0x0114: "Right Control",
        0x0115: "Right Shift",
        0x0116: "Insert",
        0x0117: "Delete",
        0x0118: "Home",
        0x0119: "End",
        0x011A: "Page Up",
        0x011B: "Page Down",
        0x011C: "Mute Microphone",
        0x011D: "Do Not Disturb",
        0x011E: "Backslash",
        0x011F: "Refresh",
        0x0120: "Close Tab",
        0x0121: "Lang Switch",
        0x0122: "Standard Key A",
        0x0123: "Standard Key B",
        0x0124: "Standard Key C",
        0x013C: "Right Option / Start / 2",
        0x0141: "Play / Pause mini",
        0x01A0: "Haptic",
        0x01A3: "Circle",
        0x01A4: "Triangle",
        0x01A5: "Diamond",
        0x01A6: "Star",
        0x01A9: "Cut",
        0x01AA: "Copy",
        0x01AB: "Paste",
        0x01AC: "Video On Off",
        0x01B4: "AI",
        // --- G键 (0x1001~0x1020) ---
        0x1001: "G1",  0x1002: "G2",  0x1003: "G3",  0x1004: "G4",
        0x1005: "G5",  0x1006: "G6",  0x1007: "G7",  0x1008: "G8",
        0x1009: "G9",  0x100A: "G10", 0x100B: "G11", 0x100C: "G12",
        0x100D: "G13", 0x100E: "G14", 0x100F: "G15", 0x1010: "G16",
        0x1011: "G17", 0x1012: "G18", 0x1013: "G19", 0x1014: "G20",
        0x1015: "G21", 0x1016: "G22", 0x1017: "G23", 0x1018: "G24",
        0x1019: "G25", 0x101A: "G26", 0x101B: "G27", 0x101C: "G28",
        0x101D: "G29", 0x101E: "G30", 0x101F: "G31", 0x1020: "G32",
        // --- M键 (0x1101~0x1108) + MR (0x1200) ---
        0x1101: "M1", 0x1102: "M2", 0x1103: "M3", 0x1104: "M4",
        0x1105: "M5", 0x1106: "M6", 0x1107: "M7", 0x1108: "M8",
        0x1200: "MR",
    ]

    // MARK: - CID → MosCode 特殊映射 (Mos 自有逻辑)

    /// 为常见鼠标按钮保留固定 MosCode (1000~1007)
    /// 其余 CID 使用公式: 2000 + CID
    private static let cidToCode: [UInt16: UInt16] = [
        0x0050: 1003,  // Left Button (diverted)
        0x0051: 1004,  // Right Button (diverted)
        0x0052: 1005,  // Middle Button (diverted)
        0x0053: 1006,  // Back Button (diverted)
        0x0056: 1007,  // Forward Button (diverted)
        0x00C3: 1000,  // Mouse Gesture Button
        0x00C4: 1001,  // Smart Shift
        0x00D7: 1002,  // Virtual Gesture Button
    ]

    // MARK: - 反向映射缓存 (预计算)

    private static let codeToCID: [UInt16: UInt16] = {
        var reversed: [UInt16: UInt16] = [:]
        for (cid, code) in cidToCode { reversed[code] = cid }
        return reversed
    }()

    // MARK: - 名称查询

    /// 通过 CID 查询名称 (Debug 面板 + 按键面板共用)
    static func name(forCID cid: UInt16) -> String {
        return cidNames[cid] ?? String(format: "Unknown(0x%04X)", cid)
    }

    /// 通过 MosCode 查询名称 (按键面板使用)
    static func name(forMosCode code: UInt16) -> String {
        guard let cid = toCID(code) else { return "Logi(\(code))" }
        return name(forCID: cid)
    }

    // MARK: - Code 转换

    /// CID → MosCode
    /// 已知 CID 最大值约 0x1200, 加 2000 后远小于 UInt16.max
    static func toMosCode(_ cid: UInt16) -> UInt16 {
        if let known = cidToCode[cid] { return known }
        let mapped = UInt32(2000) + UInt32(cid)
        return mapped <= UInt32(UInt16.max) ? UInt16(mapped) : UInt16(cid & 0x0FFF) + 2000
    }

    /// MosCode → CID (反向映射, O(1))
    static func toCID(_ mosCode: UInt16) -> UInt16? {
        if let cid = codeToCID[mosCode] { return cid }
        if mosCode >= 2000 { return mosCode - 2000 }
        return nil
    }

    /// 判断按钮码是否属于 Logitech HID++ 专有范围
    static func isLogitechCode(_ code: UInt16) -> Bool {
        return code >= 1000
    }
}
