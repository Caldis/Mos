//
//  ButtonEvent.swift
//  Mos
//  鼠标按钮事件基类
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

enum ButtonType: String, CaseIterable {
    case leftMouse = "Left"
    case rightMouse = "Right"
    case otherMouse = "Other"
    case unknown = "Unknown"
    
    var displayName: String {
        switch self {
        case .leftMouse: return "Left"
        case .rightMouse: return "Right"
        case .otherMouse: return "Other"
        case .unknown: return "Unknown"
        }
    }
}

enum ButtonAction: String, CaseIterable {
    case down = "Down"
    case up = "Up"
    case unknown = "Unknown"
    
    var displayName: String {
        switch self {
        case .down: return "Down"
        case .up: return "Up"
        case .unknown: return "Unknown"
        }
    }
}

struct ButtonEventData {
    // 基本属性
    var buttonType: ButtonType
    var action: ButtonAction
    var buttonNumber: Int
    
    // 位置信息
    var locationX: Double
    var locationY: Double
    
    // 时间戳
    var timestamp: Double
    
    // 修饰键状态
    var modifierFlags: CGEventFlags
    
    // 点击计数
    var clickCount: Int
    
    // 压力信息(如果支持)
    var pressure: Double
    
    // 是否为合成事件
    var isSynthetic: Bool
}

class ButtonEvent {
    
    // 事件数据
    private(set) var eventData: ButtonEventData
    
    // 原始事件引用
    private(set) var cgEvent: CGEvent
    
    // 初始化
    init(with event: CGEvent, type: CGEventType) {
        self.cgEvent = event
        
        // 解析事件类型和按钮类型
        let (buttonType, action, buttonNumber) = ButtonEvent.parseEventType(type, event: event)
        
        // 获取事件位置
        let location = event.location
        
        // 构建事件数据
        self.eventData = ButtonEventData(
            buttonType: buttonType,
            action: action,
            buttonNumber: buttonNumber,
            locationX: Double(location.x),
            locationY: Double(location.y),
            timestamp: Double(event.timestamp) / 1_000_000_000.0, // 转换为秒
            modifierFlags: event.flags,
            clickCount: Int(event.getIntegerValueField(.mouseEventClickState)),
            pressure: event.getDoubleValueField(.mouseEventPressure),
            isSynthetic: event.getIntegerValueField(.eventSourceStateID) != 0
        )
    }
    
    // 解析事件类型
    private static func parseEventType(_ type: CGEventType, event: CGEvent) -> (ButtonType, ButtonAction, Int) {
        var buttonType: ButtonType = .unknown
        var action: ButtonAction = .unknown
        var buttonNumber = 0
        
        switch type {
        case .leftMouseDown:
            buttonType = .leftMouse
            action = .down
            buttonNumber = 0
        case .leftMouseUp:
            buttonType = .leftMouse
            action = .up
            buttonNumber = 0
        case .rightMouseDown:
            buttonType = .rightMouse
            action = .down
            buttonNumber = 1
        case .rightMouseUp:
            buttonType = .rightMouse
            action = .up
            buttonNumber = 1
        case .otherMouseDown:
            buttonType = .otherMouse
            action = .down
            buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        case .otherMouseUp:
            buttonType = .otherMouse
            action = .up
            buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        default:
            break
        }
        
        return (buttonType, action, buttonNumber)
    }
    
    // 获取事件描述
    func getDescription() -> String {
        let modifiers = getModifierDescription()
        let modifierString = modifiers.isEmpty ? "" : "[\(modifiers)] "
        
        return "\(modifierString)\(eventData.buttonType.displayName) \(eventData.action.displayName) at (\(Int(eventData.locationX)), \(Int(eventData.locationY)))"
    }
    
    // 获取修饰键描述
    private func getModifierDescription() -> String {
        var modifiers: [String] = []
        
        if eventData.modifierFlags.contains(.maskCommand) {
            modifiers.append("⌘")
        }
        if eventData.modifierFlags.contains(.maskShift) {
            modifiers.append("⇧")
        }
        if eventData.modifierFlags.contains(.maskAlternate) {
            modifiers.append("⌥")
        }
        if eventData.modifierFlags.contains(.maskControl) {
            modifiers.append("⌃")
        }
        
        return modifiers.joined(separator: "")
    }
    
    // 格式化时间戳
    func getFormattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date(timeIntervalSince1970: eventData.timestamp))
    }
}
