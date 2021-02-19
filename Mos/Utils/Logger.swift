//
//  Logger.swift
//  Mos
//  日志工具
//  Created by Caldis on 2018/2/20.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Logger {
    
    // 解析信息
    class func getParsedLog(form event: CGEvent) -> String {
        let isTrackPad = ScrollEvent.isTrackpadEvent(event: event)
        let runningApplication = ScrollUtils.shared.getRunningApplication(from: event)
        return """
        Trackpad: \(isTrackPad)
        Path: \(runningApplication?.bundleURL?.path ?? runningApplication?.executableURL?.path ?? "")
        """
    }
    
    // 滚动方向信息
    class func getScrollLog(form event: CGEvent) -> String {
        return """
        scrollWheelEventDeltaAxis1 (FixY): \(event.getDoubleValueField(.scrollWheelEventDeltaAxis1))
        scrollWheelEventDeltaAxis2 (FixX): \(event.getDoubleValueField(.scrollWheelEventDeltaAxis2))
        scrollWheelEventPointDeltaAxis1 (PtY): \(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        scrollWheelEventPointDeltaAxis2 (PtX): \(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
        scrollWheelEventFixedPtDeltaAxis1 (FixPtY): \(String(format: "%.1f", event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)))
        scrollWheelEventFixedPtDeltaAxis2 (FixPtX): \(String(format: "%.1f", event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)))
        unacceleratedPointerMovementY: \(event.getDoubleValueField(.eventUnacceleratedPointerMovementY))
        unacceleratedPointerMovementX: \(event.getDoubleValueField(.eventUnacceleratedPointerMovementX))
        """
    }
    
    // 滚动额外信息
    class func getScrollDetailLog(form event: CGEvent) -> String {
        // scrollWheelEventInstantMouser 事件是否应该被 inkWell 子系统忽略 (手写板处理模块), 如果不为零则将会被忽略
        // scrollWheelEventIsContinuous 事件是否包含连续滚动状态(触控板), 如果事件为行滚动则该值为零, 像素滚动则为非零
        // scrollWheelEventScrollCount 加速度累计
        // scrollWheelEventScrollPhase 根据触控板响应阶段改变
        // CGScrollPhase (触控板滑动阶段)
        //       1: [触控板]开始(kCGScrollPhaseBegan)
        //       2: [触控板]双指滑动(无缓动)(kCGScrollPhaseChanged)
        //       4: [触控板]双指滑动完拿开(无缓动)(最后一下)(kCGScrollPhaseEnded)
        //       8: [触控板]双指触碰未滑动拿开(kCGScrollPhaseCancelled)
        //     128: [触控板]双指触碰未滑动(kCGScrollPhaseMayBegin)
        // scrollWheelEventMomentumPhase 根据触控板响应阶段改变
        // CGMomentumScrollPhase (触控板缓动阶段)
        //       1: [触控板]开始(begin)
        //       2: [触控板]缓动动画进行中(continuous)
        //       3: [触控板]缓动动画完成(最后一下)(end)
        // 2-1 内置bounce正常, chrome完全动不了
        return """
        scrollWheelEventInstantMouser: \(event.getDoubleValueField(.scrollWheelEventInstantMouser))
        scrollWheelEventIsContinuous: \(event.getDoubleValueField(.scrollWheelEventIsContinuous))
        scrollWheelEventScrollCount: \(event.getDoubleValueField(.scrollWheelEventScrollCount))
        scrollWheelEventScrollPhase: \(event.getDoubleValueField(.scrollWheelEventScrollPhase))
        scrollWheelEventMomentumPhase: \(event.getDoubleValueField(.scrollWheelEventMomentumPhase))
        """
    }
    
    // 鼠标信息
    class func getMouseLog(form event: CGEvent) -> String {
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
    
    // 进程信息
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
    class func getTabletEventLog(form event: CGEvent) -> String {
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
        """
    }
    class func getTabletProximityLog(form event: CGEvent) -> String {
        return """
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
//        print(self.getTabletLog(form: event))
    }
    
}
