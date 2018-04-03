//
//  Logger.swift
//  Mos
//  日志工具
//  Created by Caldis on 2018/2/20.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Logger {
    
    // 滚动相关信息
    class func getScrollLog(form event: CGEvent) -> String {
        return """
            Is using TouchPad: \(ScrollUtils.shared.isTouchPad(of: event))
            Fix Y: \(event.getDoubleValueField(.scrollWheelEventDeltaAxis1))
            Fix X: \(event.getDoubleValueField(.scrollWheelEventDeltaAxis2))
            Pt Y: \(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
            Pt X: \(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
            Fix Pt Y: \(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
            Fix Pt X: \(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
        """
    }
    
    // 处理进程相关信息
    class func getScrollDetailLog(form event: CGEvent) -> String {
        // scrollWheelEventIsContinuous 采样精度(设为 1 时为像素级别)
        // scrollWheelEventScrollCount 加速度累计
        // scrollWheelEventMomentumPhase 根据触控板响应阶段改变
        //       2: [触控板]缓动动画进行中
        //       3: [触控板]缓动动画完成(最后一下)
        // scrollWheelEventScrollPhase 根据触控板响应阶段改变
        //     128: [触控板]双指触碰未滑动
        //       8: [触控板]双指触碰未滑动拿开
        //       2: [触控板]双指滑动(无缓动), [鼠标]左侧滚轮滑动中
        //       4: [触控板]双指滑动完拿开(无缓动)(最后一下)
        //       0: [触控板]滑动事件缓动, [鼠标]滚轮滚动中 (未接触触控板)
        return """
            scrollWheelEventInstantMouser: \(event.getDoubleValueField(.scrollWheelEventInstantMouser))
            scrollWheelEventIsContinuous: \(event.getDoubleValueField(.scrollWheelEventIsContinuous))
            scrollWheelEventScrollCount: \(event.getDoubleValueField(.scrollWheelEventScrollCount))
            scrollWheelEventMomentumPhase: \(event.getDoubleValueField(.scrollWheelEventMomentumPhase))
            scrollWheelEventScrollPhase: \(event.getDoubleValueField(.scrollWheelEventScrollPhase))
        """
    }
    
    // 鼠标其他信息
    class func getOtherLog(form event: CGEvent) -> String {
        return """
            mouseEventNumber: \(event.getDoubleValueField(.mouseEventNumber))
            mouseEventClickState: \(event.getDoubleValueField(.mouseEventClickState))
            mouseEventPressure: \(event.getDoubleValueField(.mouseEventPressure))
            mouseEventButtonNumber: \(event.getDoubleValueField(.mouseEventButtonNumber))
            mouseEventDeltaX: \(event.getDoubleValueField(.mouseEventDeltaX))
            mouseEventDeltaY: \(event.getDoubleValueField(.mouseEventDeltaY))
            mouseEventInstantMouser: \(event.getDoubleValueField(.mouseEventInstantMouser))
            mouseEventSubtype: \(event.getDoubleValueField(.mouseEventSubtype))
            mouseEventWindowUnderMousePointer: \(event.getDoubleValueField(.mouseEventWindowUnderMousePointer))
            mouseEventWindowUnderMousePointerThatCanHandleThisEvent: \(event.getDoubleValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent))
        """
    }
    
    // 处理进程相关信息
    class func getProcessLog(form event: CGEvent) -> String {
        return """
            eventTargetProcessSerialNumber: \(event.getDoubleValueField(.eventTargetProcessSerialNumber))
            eventTargetUnixProcessID: \(event.getDoubleValueField(.eventTargetUnixProcessID))
            eventSourceUnixProcessID: \(event.getDoubleValueField(.eventSourceUnixProcessID))
            eventSourceUserData: \(event.getDoubleValueField(.eventSourceUserData))
            eventSourceUserID: \(event.getDoubleValueField(.eventSourceUserID))
            eventSourceGroupID: \(event.getDoubleValueField(.eventSourceGroupID))
            eventSourceStateID: \(event.getDoubleValueField(.eventSourceStateID))
        """
    }
    
    // tablet(画板) 相关信息
    class func getTabletLog(form event: CGEvent) -> String {
        return """
            tabletEventPointX: \(event.getDoubleValueField(.tabletEventPointX))
            tabletEventPointY: \(event.getDoubleValueField(.tabletEventPointY))
            tabletEventPointZ: \(event.getDoubleValueField(.tabletEventPointZ))
            tabletEventPointButtons: \(event.getDoubleValueField(.tabletEventPointButtons))
            tabletEventPointPressure: \(event.getDoubleValueField(.tabletEventPointPressure))
            tabletEventTiltX: \(event.getDoubleValueField(.tabletEventTiltX))
            tabletEventTiltY: \(event.getDoubleValueField(.tabletEventTiltY))
            tabletEventRotation: \(event.getDoubleValueField(.tabletEventRotation))
            tabletEventTangentialPressure: \(event.getDoubleValueField(.tabletEventTangentialPressure))
            tabletEventDeviceID: \(event.getDoubleValueField(.tabletEventDeviceID))
            tabletEventVendor1: \(event.getDoubleValueField(.tabletEventVendor1))
            tabletEventVendor2: \(event.getDoubleValueField(.tabletEventVendor2))
            tabletEventVendor3: \(event.getDoubleValueField(.tabletEventVendor3))
            tabletProximityEventVendorID: \(event.getDoubleValueField(.tabletProximityEventVendorID))
            tabletProximityEventTabletID: \(event.getDoubleValueField(.tabletProximityEventTabletID))
            tabletProximityEventPointerID: \(event.getDoubleValueField(.tabletProximityEventPointerID))
            tabletProximityEventDeviceID: \(event.getDoubleValueField(.tabletProximityEventDeviceID))
            tabletProximityEventSystemTabletID: \(event.getDoubleValueField(.tabletProximityEventSystemTabletID))
            tabletProximityEventVendorPointerType: \(event.getDoubleValueField(.tabletProximityEventVendorPointerType))
            tabletProximityEventVendorPointerSerialNumber: \(event.getDoubleValueField(.tabletProximityEventVendorPointerSerialNumber))
            tabletProximityEventVendorUniqueID: \(event.getDoubleValueField(.tabletProximityEventVendorUniqueID))
            tabletProximityEventCapabilityMask: \(event.getDoubleValueField(.tabletProximityEventCapabilityMask))
            tabletProximityEventPointerType: \(event.getDoubleValueField(.tabletProximityEventPointerType))
            tabletProximityEventEnterProximity: \(event.getDoubleValueField(.tabletProximityEventEnterProximity))
        """
    }
    
    // 打印 Log
    class func printLog(form event: CGEvent) {
        print(self.getScrollLog(form: event))
    }
    
}
