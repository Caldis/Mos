//
//  scrollSmooth.swift
//  Mos
//  滚动事件截取与判断核心类
//  Created by Cb on 2017/1/14.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class ScrollCore: NSObject {
    
    // 全局设置相关
    static let defOption = ( smooth: true, reverse: true )
    static let defAdvancedOption = ( speed: 0.95, time: 320 )
    static var option = ( smooth: true, reverse: true )
    static var advancedOption = ( speed: 0.95, time: 400 )
    
    // 延迟执行相关
    static var delayTimer:Timer!
    static var delayGap = 0.010 // 延迟时间(ms)
    
    // 处理鼠标事件的方向
    static var handleScrollType = ScrollCore.mousePos.Y
    static let mousePos = ( Y: UInt32(1), YX: UInt32(2), YXZ: UInt32(3) )
    
    // 事件发送器相关
    static var scrollEventPosterStopCountY = 0
    static var scrollEventPosterStopCountX = 0
    static var scrollEventPoster:CVDisplayLink?
    
    // 新滚动事件相关
    static var pulseGap = 0.3 // 间隔时间(s)
    static var pulseTimeCache: NSDate? //用于缓存上一次的时间
    
    // 滚动数据
    static var beforeLastScrollRef = ( Y: 0.0, X: 0.0 )
    static var lastScrollRef = ( Y: 0.0, X: 0.0 )
    static var scrollRef = ( Y: 0.0, X: 0.0 )
    static var autoScrollRef = ( Y: 0.0, X: 0.0 ) // 缓动生成的滚动信息
    static var singleScrollCount = 0 // 单次滚动计数
    
    // 曲线数据相关
    static var headPulseScale = 4.0
    static var headPulseNormalize = 1.032
    static var tailPulseScale = 4.0
    static var tailPulseNormalize = 1.032
    // 动画相关
    static var fps = 60.0 // 帧数
    static var animTime = 380.0 // 动画时间 (这里已经由全局设置代替)
    static var turningPoint = 0.22 // 转折点
    static var scrollScale = 0.95 // 放大系数 (这里已经由全局设置代替)
    static var totalPoint = Int(ScrollCore.fps * Double(ScrollCore.defAdvancedOption.time) / 1000.0)
    
    // 初始化缓动曲线
    static var basePluseData = ScrollCore.initPluseData()
    static var realPluseDataY = [Double]()
    static var realPluseDataX = [Double]()
    
    // 新: Smoothstep插值
    static var totalScroll = ( Y: 0.0, X: 0.0 )
    static var correntScroll = ( Y: 0.0, X: 0.0 )
    
    
    // 开始截取事件
    static func startCapture(event mask: CGEventMask, to eventHandler: @escaping CGEventTapCallBack, at eventTap: CGEventTapLocation, where eventPlace: CGEventTapPlacement, for behaver: CGEventTapOptions) -> CFMachPort {
        guard let eventTap = CGEvent.tapCreate(tap: eventTap, place: eventPlace, options: behaver, eventsOfInterest: mask, callback: eventHandler, userInfo: nil) else {
            fatalError("Failed to create event tap")
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return eventTap
    }
    // 停止截取事件
    static func stopCapture(tap: CFMachPort?) {
        if let eventTap = tap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        } else {
            fatalError("Failed to disable eventTap")
        }
    }
    
    
    
    // 延迟执行
    static func delayPreScroll() {
        if ScrollCore.delayTimer !== nil {
            ScrollCore.delayTimer.invalidate()
        }
        ScrollCore.delayTimer = Timer.scheduledTimer(timeInterval: ScrollCore.delayGap, target:ScrollCore.self, selector: #selector(ScrollCore.startScrollEventPoster), userInfo:nil, repeats:false)
    }
    
    
    
    // 事件发送器 (CVDisplayLink)
    static func initScrollEventPoster() {
        // 新建一个CVDisplayHandler来执行循环
        CVDisplayLinkCreateWithActiveCGDisplays(&ScrollCore.scrollEventPoster)
        CVDisplayLinkSetOutputHandler(ScrollCore.scrollEventPoster!, {
            (displayLink, inNow, inOutputTime, flagsIn, flagsOut) -> CVReturn in
                // TODO: 处理X轴数据
                // 处理Y轴事件
                ScrollCore.handleScrollY()
                return kCVReturnSuccess
        })
    }
    static func startScrollEventPoster() {
        ScrollCore.updateRealPluseData(Y: ScrollCore.scrollRef.Y, X: ScrollCore.scrollRef.X)
        // 如果事件发送器没有在运行, 就运行一下
        if !CVDisplayLinkIsRunning(ScrollCore.scrollEventPoster!) {
            CVDisplayLinkStart(ScrollCore.scrollEventPoster!)
        } else {
            // TODO: 处理X轴数据
            // 如果已经在运行, 则重设一下计步器
            ScrollCore.scrollEventPosterStopCountY = 0
            ScrollCore.scrollEventPosterStopCountX = 0
        }
    }
    static func stopScrollEventPoster() {
        if let poster = ScrollCore.scrollEventPoster {
            CVDisplayLinkStop(poster)
        }
    }

    
    // 更新滚动数据
    static func updateScrollData(Y: Double, X: Double) {
        ScrollCore.beforeLastScrollRef = ScrollCore.lastScrollRef
        ScrollCore.lastScrollRef = ScrollCore.scrollRef
        ScrollCore.scrollRef.Y = Y
        ScrollCore.scrollRef.X = X
    }
    // 更新滚动数据 (增量)
    static func updataScrollDataIncremental(Y: Double, X: Double) {
        ScrollCore.totalScroll.Y += Y
        ScrollCore.totalScroll.X += X
    }
    // 更新实际滚动曲线
    static func updateRealPluseData(Y: Double, X: Double) {
        // TODO: 处理X轴数据
        var realPluseDataY = [Double]()
        // var realPluseDataX = [Double]()
        for i in ScrollCore.basePluseData {
            realPluseDataY.append(i*Y)
            // realPluseDataX.append(i*X)
        }
        ScrollCore.realPluseDataY = realPluseDataY
        // ScrollCore.realPluseDataX = realPluseDataX
    }
    
    
    
    // 判断是否触控板事件
    static func isTouchPad(of event: CGEvent) -> Bool {
        if event.getDoubleValueField(.scrollWheelEventScrollCount) != 0.0 {
            return true
        }
        if event.getDoubleValueField(.scrollWheelEventMomentumPhase) != 0.0 {
            return true
        }
        if event.getDoubleValueField(.scrollWheelEventScrollPhase) != 0.0 && event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) != 0.0 {
            return true
        }
        if event.getDoubleValueField(.scrollWheelEventScrollPhase) != 0.0 && event.getDoubleValueField(.eventSourceUnixProcessID) == 0 {
            return true
        }
        return false
    }
    
    
    
    // 判断是否新的滚动事件
    static func isNewScroll(of event: CGEvent) -> Bool {
        // 内部函数, 用于重设时间戳
        func updatePulseTime() {
            let nowTime = NSDate()
            ScrollCore.pulseTimeCache = nowTime
        }
        
        // 如果scrollWheelEventScrollCount字段存在, 则为触控板继续加速运动, 非新滚动
        if event.getDoubleValueField(.scrollWheelEventScrollCount) != 0.0 {
            updatePulseTime()
            return false
        }
        // 如果pulseTimeCache存在
        let nowTime = NSDate()
        if let pulseTimeCache = ScrollCore.pulseTimeCache {
            updatePulseTime()
            if nowTime.timeIntervalSince(pulseTimeCache as Date) > ScrollCore.pulseGap {
                // pulseTimeCache存在, 且大于pulseGap, 则判定为新滚动
                return true
            } else {
                // pulseTimeCache存在, 但小于pulseGap, 则判定为非新滚动
                return false
            }
        } else {
            // 如果pulseTimeCache不存在, 则是第一次滚动, 判定为新滚动
            updatePulseTime()
            return true
        }
    }
    
    
    
    // Legency Interpolation BEGIN
    // 主处理函数(CVDisplayLink)
    static func handleScrollY() {
        if ScrollCore.scrollEventPosterStopCountY >= ScrollCore.totalPoint {
            // 如果到达既定步数, 则停止事件
            ScrollCore.stopScrollEventPoster()
            ScrollCore.scrollEventPosterStopCountY = 0
            ScrollCore.singleScrollCount = 0
        } else {
            // 否则则截取ScrollRef内的值来发送
            if ScrollCore.scrollEventPosterStopCountY == 0 {
                if ScrollCore.autoScrollRef.Y != 0 {
                    // 输入的滚动事件, 且不是第一次滚动, 则查找最接近的值来滚动
                    // let startIndexY = ScrollCore.findApproachMaxValue(of: ScrollCore.autoScrollRef.Y, from: ScrollCore.realPluseDataY)
                    var startIndexY = 0
                    if ScrollCore.singleScrollCount >= 3 {
                        // 如果单次滚动计数大于等于3, 则直接跳到后面的下降区间
                        startIndexY = ScrollCore.findApproachMaxDownValue(of: ScrollCore.autoScrollRef.Y, from: ScrollCore.realPluseDataY)
                    } else {
                        // 否则按照套路来, 从前面计数
                        startIndexY = ScrollCore.findApproachMaxValue(of: ScrollCore.autoScrollRef.Y, from: ScrollCore.realPluseDataY)
                    }
                    MouseEvent().scroll(ScrollCore.mousePos.Y, yScroll: Int32(ScrollCore.realPluseDataY[startIndexY]), xScroll: 0)
                    ScrollCore.scrollEventPosterStopCountY = startIndexY==0 ? 1 : startIndexY // 避免一直在0循环
                } else {
                    // 否则就按正常缓动的滚动事件, 按照正常递增
                    MouseEvent().scroll(ScrollCore.mousePos.Y, yScroll: Int32(ScrollCore.realPluseDataY[ScrollCore.scrollEventPosterStopCountY]), xScroll: 0)
                    ScrollCore.autoScrollRef.Y = ScrollCore.realPluseDataY[ScrollCore.scrollEventPosterStopCountY]
                    ScrollCore.scrollEventPosterStopCountY += 1
                }
            } else {
                // 缓动的滚动事件, 按照正常递增
                MouseEvent().scroll(ScrollCore.mousePos.Y, yScroll: Int32(ScrollCore.realPluseDataY[ScrollCore.scrollEventPosterStopCountY]), xScroll: 0)
                ScrollCore.autoScrollRef.Y = ScrollCore.realPluseDataY[ScrollCore.scrollEventPosterStopCountY]
                ScrollCore.scrollEventPosterStopCountY += 1
            }
        }
    }
    // 缓动曲线
    static func headPulse(pos: Double) -> Double {
        //  防止数据越界
        if pos >= 1.0 {
            return 1.0
        }
        if pos <= 0.0 {
            return 0.0
        }
        // 计算位置
        var val = 0.0, start = 0.0, expx = 0.0
        var x = pos * ScrollCore.headPulseScale;
        if (x < 1) {
            // 加速
            val = x - (1.0 - exp(-x));
        } else {
            // 减速
            start = exp(-1.0);
            x -= 1.0;
            expx = 1.0 - exp(-x);
            val = start + (expx * (1.0 - start));
        }
        return val*ScrollCore.headPulseNormalize
    }
    static func tailPulse(pos: Double) -> Double {
        //  防止数据越界
        if pos >= 1.0 {
            return 0.0
        }
        if pos <= 0.0 {
            return 1.0
        }
        // 计算位置
        var val = 0.0, start = 0.0, expx = 0.0
        var x = pos * ScrollCore.tailPulseScale;
        if (x < 1) {
            // 加速
            val = x - (1.0 - exp(-x));
        } else {
            // 减速
            start = exp(-1.0);
            x -= 1.0;
            expx = 1.0 - exp(-x);
            val = start + (expx * (1.0 - start));
        }
        return 1 - (val*ScrollCore.tailPulseNormalize)
    }
    // 根据设定的步数和曲线拟合成减速缓动数据
    static func initPluseData() -> [Double] {
        var pulseData = [Double]()
        var plusePoint:Double!
        var samplePoint:Double!
        var basePoint:Double!
        for i in 1...ScrollCore.totalPoint {
            let di = Double(i)
            let dTotalPoint = Double(ScrollCore.totalPoint)
            if (di <= dTotalPoint*ScrollCore.turningPoint) {
                samplePoint = di
                basePoint = dTotalPoint*ScrollCore.turningPoint
                plusePoint = ScrollCore.headPulse(pos: samplePoint/basePoint)
            } else {
                samplePoint = di - dTotalPoint*ScrollCore.turningPoint
                basePoint = dTotalPoint*(1-ScrollCore.turningPoint)
                plusePoint = ScrollCore.tailPulse(pos: samplePoint/basePoint)
            }
            pulseData.append(plusePoint * ScrollCore.advancedOption.speed)
        }
        return pulseData
    }
    // 查找数组中最接近输入值的项的Index
    static func findApproachValue(of value: Double, from array: [Double]) -> Int {
        for i in 1...array.count {
            let left = array[i-1]
            let right = array[i]
            if left/right<1 {
                // 右边大于左边, 上升期
                let leftDiff = value - left
                let rightDiff = value - right
                if leftDiff*rightDiff<=0 {
                    // 判断是给左值的还是右值
                    if abs(leftDiff) < abs(rightDiff) {
                        return i-1
                    } else {
                        return i
                    }
                }
            } else {
                // 左大于右, 减速, 直接返回最大值
                return i
            }
        }
        return 0
    }
    // 查找数组中最接近输入值中最大的的项的Index
    static func findApproachMaxValue(of value: Double, from array: [Double]) -> Int {
        for i in 1...array.count {
            let left = array[i-1]
            let right = array[i]
            if left/right<1 {
                // 右边大于左边, 上升期
                let leftDiff = value - left
                let rightDiff = value - right
                if leftDiff*rightDiff<=0 {
                    return array.index(of: right)!
                }
            } else {
                // 左边大于右边, 开始下降, 直接返回最大值
                return i
            }
        }
        return 0
    }
    // 查找数组中最接近输入值中最大的的项位于下降区间的Index
    static func findApproachMaxDownValue(of value: Double, from array: [Double]) -> Int {
        let peakIndex = findPeakIndex(from: array)
        // 直接从峰值之后找
        for i in peakIndex..<array.count {
            let left = array[i-1]
            let right = array[i]
            
            let leftDiff = value - left
            let rightDiff = value - right
            if leftDiff*rightDiff<=0 {
                return array.index(of: left)! - 2
            }
        }
        // 找不到, 直接返回最大值
        return peakIndex
    }
    // 返回峰值的Index
    static func findPeakIndex(from array: [Double]) -> Int {
        if array[1] < 0 {
            // 正极数组, 返回最小值
            return array.index(of: array.min()!)!
        } else {
            // 正值数组, 返回最大值
            return array.index(of: array.max()!)!
        }
    }
    // Legency Interpolation END
    
    
    
    // 从UserDefaults中读取用户设置
    static func readPreferencesData() {
        if let smooth = UserDefaults.standard.string(forKey: "smooth") {
            ScrollCore.option.smooth = smooth=="true" ? true : false
        }
        if let reverse = UserDefaults.standard.string(forKey: "reverse") {
            ScrollCore.option.reverse = reverse=="true" ? true : false
        }
        if UserDefaults.standard.double(forKey: "speed") != 0.0 {
            ScrollCore.advancedOption.speed = UserDefaults.standard.double(forKey: "speed")
        }
        if UserDefaults.standard.integer(forKey: "time") != 0 {
            ScrollCore.advancedOption.time = UserDefaults.standard.integer(forKey: "time")
        }
    }
    
    
    
    
    // 打印Log
    static func printLog(of event: CGEvent) {
        print(ScrollCore.getScrollLog(of: event))
    }
    // 获取滚动相关信息
    static func getScrollLog(of event: CGEvent) -> String {
        return (
            "Is using TouchPad: \(ScrollCore.isTouchPad(of: event))\n" +
                "Y: \(event.getDoubleValueField(.scrollWheelEventDeltaAxis1))\n" +
                "X: \(event.getDoubleValueField(.scrollWheelEventDeltaAxis2))\n" +
                "Pt Y: \(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))\n" +
                "Pt X: \(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))\n" +
                "FixPt Y: \(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))\n" +
            "FixPt X: \(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))\n"
        )
    }
    // 获取处理进程相关信息
    static func getScrollDetailLog(of event: CGEvent) -> String {
        return (
            "scrollWheelEventInstantMouser: \(event.getDoubleValueField(.scrollWheelEventInstantMouser))\n" +
                // 该字段影响采样精度, 设为1时为像素级别
                "scrollWheelEventIsContinuous: \(event.getDoubleValueField(.scrollWheelEventIsContinuous))\n" +
                "scrollWheelEventMomentumPhase: \(event.getDoubleValueField(.scrollWheelEventMomentumPhase))\n" +
                "scrollWheelEventScrollCount: \(event.getDoubleValueField(.scrollWheelEventScrollCount))\n" +
                // 该字段根据多点触控反馈改变, 128:双指触碰未滑动,8:双指触碰未滑动拿开,2:双指滑动中/MM左侧滚轮滑动中,4:双指滑动完拿开,0:双指未在触控板上(是滑动事件缓动或滚轮)
            "scrollWheelEventScrollPhase: \(event.getDoubleValueField(.scrollWheelEventScrollPhase))\n"
        )
    }
    // 获取鼠标其他信息
    static func getOtherLog(of event: CGEvent) -> String {
        return (
            "mouseEventNumber: \(event.getDoubleValueField(.mouseEventNumber))\n" +
                "mouseEventClickState: \(event.getDoubleValueField(.mouseEventClickState))\n" +
                "mouseEventPressure: \(event.getDoubleValueField(.mouseEventPressure))\n" +
                "mouseEventButtonNumber: \(event.getDoubleValueField(.mouseEventButtonNumber))\n" +
                "mouseEventDeltaX: \(event.getDoubleValueField(.mouseEventDeltaX))\n" +
                "mouseEventDeltaY: \(event.getDoubleValueField(.mouseEventDeltaY))\n" +
                "mouseEventInstantMouser: \(event.getDoubleValueField(.mouseEventInstantMouser))\n" +
                "mouseEventSubtype: \(event.getDoubleValueField(.mouseEventSubtype))\n" +
                "mouseEventWindowUnderMousePointer: \(event.getDoubleValueField(.mouseEventWindowUnderMousePointer))\n" +
            "mouseEventWindowUnderMousePointerThatCanHandleThisEvent: \(event.getDoubleValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent))\n"
        )
    }
    // 获取处理进程相关信息
    static func getProcessLog(of event: CGEvent) -> String {
        return (
            "eventTargetProcessSerialNumber: \(event.getDoubleValueField(.eventTargetProcessSerialNumber))\n" +
                "eventTargetUnixProcessID: \(event.getDoubleValueField(.eventTargetUnixProcessID))\n" +
                "eventSourceUnixProcessID: \(event.getDoubleValueField(.eventSourceUnixProcessID))\n" +
                "eventSourceUserData: \(event.getDoubleValueField(.eventSourceUserData))\n" +
                "eventSourceUserID: \(event.getDoubleValueField(.eventSourceUserID))\n" +
                "eventSourceGroupID: \(event.getDoubleValueField(.eventSourceGroupID))\n" +
            "eventSourceStateID: \(event.getDoubleValueField(.eventSourceStateID))\n"
        )
    }
    // 获取tablet(画板)相关信息
    static func getTabletLog(of event: CGEvent) -> String {
        return (
            "tabletEventPointX: \(event.getDoubleValueField(.tabletEventPointX))\n" +
                "tabletEventPointY: \(event.getDoubleValueField(.tabletEventPointY))\n" +
                "tabletEventPointZ: \(event.getDoubleValueField(.tabletEventPointZ))\n" +
                "tabletEventPointButtons: \(event.getDoubleValueField(.tabletEventPointButtons))\n" +
                "tabletEventPointPressure: \(event.getDoubleValueField(.tabletEventPointPressure))\n" +
                "tabletEventTiltX: \(event.getDoubleValueField(.tabletEventTiltX))\n" +
                "tabletEventTiltY: \(event.getDoubleValueField(.tabletEventTiltY))\n" +
                "tabletEventRotation: \(event.getDoubleValueField(.tabletEventRotation))\n" +
                "tabletEventTangentialPressure: \(event.getDoubleValueField(.tabletEventTangentialPressure))\n" +
                "tabletEventDeviceID: \(event.getDoubleValueField(.tabletEventDeviceID))\n" +
                "tabletEventVendor1: \(event.getDoubleValueField(.tabletEventVendor1))\n" +
                "tabletEventVendor2: \(event.getDoubleValueField(.tabletEventVendor2))\n" +
                "tabletEventVendor3: \(event.getDoubleValueField(.tabletEventVendor3))\n" +
                "tabletProximityEventVendorID: \(event.getDoubleValueField(.tabletProximityEventVendorID))\n" +
                "tabletProximityEventTabletID: \(event.getDoubleValueField(.tabletProximityEventTabletID))\n" +
                "tabletProximityEventPointerID: \(event.getDoubleValueField(.tabletProximityEventPointerID))\n" +
                "tabletProximityEventDeviceID: \(event.getDoubleValueField(.tabletProximityEventDeviceID))\n" +
                "tabletProximityEventSystemTabletID: \(event.getDoubleValueField(.tabletProximityEventSystemTabletID))\n" +
                "tabletProximityEventVendorPointerType: \(event.getDoubleValueField(.tabletProximityEventVendorPointerType))\n" +
                "tabletProximityEventVendorPointerSerialNumber: \(event.getDoubleValueField(.tabletProximityEventVendorPointerSerialNumber))\n" +
                "tabletProximityEventVendorUniqueID: \(event.getDoubleValueField(.tabletProximityEventVendorUniqueID))\n" +
                "tabletProximityEventCapabilityMask: \(event.getDoubleValueField(.tabletProximityEventCapabilityMask))\n" +
                "tabletProximityEventPointerType: \(event.getDoubleValueField(.tabletProximityEventPointerType))\n" +
            "tabletProximityEventEnterProximity: \(event.getDoubleValueField(.tabletProximityEventEnterProximity))\n"
        )
    }
}
