//
//  ScrollEvent.swift
//  Mos
//  滚动事件基类
//  Created by Caldis on 2018/2/24.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollEvent {
    
    // 轴
    static let axis = ( Y: "Y", X: "X" )
    
    // 滚动事件
    private var event: CGEvent
    // 基本参数
    private var scrollFix:Int64
    private var scrollPt:Double
    private var scrollFixPt:Double
    // 滚动数据是否为 Fix 类型 (非 Fix 类型在可用数据过小时需要归一化处理)
    private var fixed = false
    // 滚动数据数据是否可用
    private var usable = false
    // 可用的滚动数据
    private var usableValue = 0.0
    
    // 初始化
    required init(with cgevent: CGEvent, use axis: String) {
        // 保存事件引用
        event = cgevent
        // 获取对应轴的数据
        if axis == "Y" {
            scrollFix = Int64(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            scrollPt = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            scrollFixPt = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        } else {
            scrollFix = Int64(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            scrollPt = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            scrollFixPt = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        }
        // 生成可用的滚动数据
        if scrollPt != 0.0 {
            fixed = false
            usable = true
            usableValue = scrollPt
        } else if scrollFixPt != 0.0 {
            fixed = true
            usable = true
            usableValue = scrollFixPt
        } else if scrollFix != 0 {
            fixed = true
            usable = true
            usableValue = Double(scrollFix)
        }
    }
    
    // 操作相关
    // 翻转数据方向
    func reverse(axis: String) {
        if axis == "Y" {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -scrollFix)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -scrollPt)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -scrollFixPt)
        } else {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -scrollFix)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -scrollPt)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -scrollFixPt)
        }
        usableValue = -usableValue
    }
    // 归一化数据
    func normalize(threshold: Double) {
        let absValue = abs(usableValue)
        usableValue = usableValue>0.0 ? max(absValue, threshold) : -max(absValue, threshold)
    }
    
    // 检查类型相关
    // 数据是否可用
    func isUsable() -> Bool {
        return usable
    }
    // 是否为 Fixed 类型
    func isFixedType() -> Bool {
        return fixed
    }
    
    // 获取数据相关
    // 获取原始事件引用
    func getOriginalEvent() -> CGEvent {
        return event
    }
    // 获取可用数据
    func getValue() -> Double {
        return usableValue
    }
    
}
