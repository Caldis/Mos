/*
 iPhone Mirroring 滚动处理链路, 2026-10-09.

 这是本机二进制的语义还原, 不是 Apple 源码.
 Swift 风格伪代码不能直接 build, 也不包含事件注入实现.
 名称带 observed / opaque / reconstructed 的函数由研究者命名.
 已确认的 Apple 类型和方法保留原名; 匿名函数只标 image offset.
 注释中的代码片段表示已确认分支, 不能代替未展开的完整函数.

 环境: macOS 26.7.1 (25G241), arm64e.
 SCUI = iPhone Mirroring.app 内的 ScreenContinuityUI.framework.
 UHK = UniversalHIDKit.framework; UH = UniversalHID.framework.
 SSK = ScreenSharingKit.framework. offset 均相对于对应 image 的 __TEXT.
 各 image UUID 和校正后的汇编:
   evidence/2026-10-09/mos-iphone-scroll-core.txt
 SCUI 上层: evidence/2026-10-09/screencontinuity-ui-segments.txt.
 AppKit phase: evidence/2026-10-09/appkit-phase-mapping.txt.

 Opaque 类型表示未还原的数据, 不是建议新增的生产类型.
 HIDEvent / IOHIDEventRef 的引用 / 桥接 / 内存所有权未完全还原.
 HIDFixed 的具体比例 / 报告字节布局 / 消息枚举布局未完全还原.
 网络封装 / 密钥 / iPhone 接收代码没有分析.
 */

// 1. AppKit 将滚轮事件交给镜像窗口的 responder.
// 已确认符号: -[CaptureViewController scrollWheel:], SCUI +0x33DF0.
// 它进入通用入口 +0x33338, 再进入 HIDCaptureViewModel 匿名函数 +0x1ECBC.
// 证据: evidence/2026-10-09/screencontinuity-ui-segments.txt.
extension CaptureViewController {
    override func scrollWheel(with event: NSEvent) {
        observedCommonEntry(event) // 解释名称, 对应 +0x33338.
    }
}

// 2. HIDCaptureViewModel 中已经到达 observer 的处理片段.
// SCUI +0x1F4D4: HIDEventObserverPrimitives.processEvent(NSEvent).
// +0x1F4E4..0x1F4F0: 报告数组为空时退出该处理片段.
// 证据: evidence/2026-10-09/screencontinuity-ui-segments.txt.
// 前置门控 / 拖动期间抑制 / 其他事件分支尚未完整重建.
// 已发现 "Dropping HID event because drag events are waiting..." 日志.
// 因此这里不构造一个假定完整的 guard, 也不承诺所有事件都到达 observer.
extension HIDCaptureViewModel {
    func observedAcceptedNSEventSegment(_ event: NSEvent) {
        let reportPairs = hidEventObserver.processEvent(event)
        if reportPairs.isEmpty { return }

        for pair in reportPairs {
            var senderID = pair.senderID
            let report = pair.report

            // +0x1F87C: 非零 sender 跳过回退.
            // +0x204A4..0x204DC: 零 sender 的 scroll 报告选择 basicMouseServiceID.
            // +0x1F9AC: 将取得的 ID 写回本次 report 的局部 sender.
            if senderID == 0 && report.reportID == ReportID.scroll {
                senderID = hidServicePrimitives.basicMouseServiceID
            }
            // 原函数还处理 pointer / keyboard 等报告, 本片段限定 scroll.

            // +0x1FEA0: 同时传入 report 与归一后的 senderID.
            guard let serviceInfo = hidServicePrimitives.lookUpServiceInfo(
                for: report, senderID: senderID
            ) else {
                // +0x1FEF0..0x202CC: 记录 lookup 错误, 回到 +0x1F814 下一报告.
                observedLookupErrorBoundary(report, senderID)
                continue
            }

            // 已确认后续存在设备属性/cache 处理和异步消息投递.
            // 更新条件及 HIDMessage 枚举 case 未完整还原, 见第 10 节.
            // 此处保留结果边界, 不把报告直接等同于一个 yield 消息.
            observedPostLookupBoundary(serviceInfo, report, event)
        }
    }
}

// 3. UHK.EventObserver<NSEvent>.processEvent, UHK +0x698C.
// 证据: evidence/2026-10-09/mos-iphone-scroll-core.txt 的 Observer 摘段.
// 默认构造器按 eventMask 选 translator 和 filter, UHK +0x3000.
// translator 包含 Scroll / Mouse / Key / FlagsChanged / Magnify / Rotate /
// SystemDefined / Translate. filter 包含 Digitizer / FluidTouchGesture /
// GameController / Keyboard / Pointer / Scroll, 各自受所选 eventMask 限制.
extension EventObserver where EventType == NSEvent {
    func processEvent(_ event: NSEvent) -> [(report: HIDReport, senderID: UInt64)] {
        var output: [(report: HIDReport, senderID: UInt64)] = []
        for translator in selectedTranslators {
            for hidEvent in translator.translateEvent(event) {
                // +0x6B60: 读取生成的 HIDEvent.senderID.
                let originalSenderID = hidEvent.senderID
                for filter in selectedFilters {
                    // +0x6CF8: EventFilterProtocol.filterEvent.
                    let result = filter.filterEvent(hidEvent)
                    for report in result.reports {
                        // +0x6D90..0x6D94: 给每份报告附上同一个原 senderID.
                        output.append((report, originalSenderID))
                    }
                    // result.event / notify 的完整协议语义未展开.
                    // 此处只还原原函数已确认的 reports 收集路径.
                }
            }
        }
        return output
    }
}

// 4. UHK.NSEventProtocol.senderID getter, UHK +0x5A94.
// +0x5C58: CGEventGetIntegerValueField 所用 field = 87.
// 证据: evidence/2026-10-09/mos-iphone-scroll-core.txt 的 sender getter.
func reconstructedSenderID(_ event: NSEvent) -> UInt64 {
    guard let cg = event.cgEvent else { return 0 }
    return UInt64(cg.getIntegerValueField(fieldNumber: 87))
}

// 5. UHK.ScrollEventTranslator.translateEvent, 实体 UHK +0x53AC.
// 证据: evidence/2026-10-09/mos-iphone-scroll-core.txt 的 translator 全部摘段.
// 整数 field 使用 getIntegerValueField, delta field 使用 getDoubleValueField.
// 173 / 175..178 的名字已在当前 SDK 的 CGEventTypes.h 公开.
// 字段名称对照: evidence/2026-10-09/sdk-and-service-properties.txt.
extension ScrollEventTranslator {
    func translateEvent(_ event: NSEvent) -> [HIDEvent] {
        // +0x54F4: NSEvent.EventType.scrollWheel.rawValue = 22.
        guard event.type == .scrollWheel else { return [] }
        let senderID = reconstructedSenderID(event)
        let timestamp = HIDTime(nanoseconds: event.timestamp * 1_000_000_000)
        var interrupted = false
        let parent: OpaqueHIDScrollReference

        // +0x5538..0x5560: cgEvent 缺失或 senderID = 0 时进入 fallback.
        if let cg = event.cgEvent, senderID != 0 {
            let optionPhase = cg.getIntegerValueField(fieldNumber: 173)
            interrupted = (optionPhase & 0x10) != 0
            var rawX = cg.getDoubleValueField(fieldNumber: 177) // RawDeltaAxis2.
            var rawY = cg.getDoubleValueField(fieldNumber: 178) // RawDeltaAxis1.
            var accelX = cg.getDoubleValueField(fieldNumber: 175) // AcceleratedDeltaAxis2.
            var accelY = cg.getDoubleValueField(fieldNumber: 176) // AcceleratedDeltaAxis1.

            // +0x5640..0x5698: field 137 严格等于 1 时四轴同时反号.
            // AppKit -[NSEvent isDirectionInvertedFromDevice] 证实其方向语义.
            if cg.getIntegerValueField(fieldNumber: 137) == 1 {
                rawX = -rawX; rawY = -rawY
                accelX = -accelX; accelY = -accelY
            }
            // +0x574C: 创建 raw 父事件, flags = 0.
            parent = IOHIDEventCreateScrollEvent(nil, timestamp, rawX, rawY, 0, flags: 0)
            // +0x579C: 创建 accelerated 子事件, 不写自造的 flag 数字.
            let child = IOHIDEventCreateScrollEvent(
                nil, timestamp, accelX, accelY, 0, flags: HIDEventFlags.accelerated
            )
            // +0x57DC: 父子关联. 桥接引用 / retain/release 细节未展开.
            IOHIDEventAppendEvent(parent, child, 0)
        } else {
            // +0x56C4..0x5708: 只有 fallback 读取 AppKit 的 scrollingDelta.
            // fallback 没有 accelerated 子事件, 也没有 interrupted 标记.
            parent = IOHIDEventCreateScrollEvent(
                nil, timestamp, event.scrollingDeltaX, event.scrollingDeltaY, 0, flags: 0
            )
        }

        IOHIDEventSetSenderID(parent, senderID) // +0x5814.
        IOHIDEventSetPhase(parent, reconstructedHIDPhase(event.phase)) // +0x585C.
        var momentum = reconstructedHIDMomentum(event.momentumPhase)
        if interrupted { momentum |= HIDScrollMomentum.interrupted } // rawValue 0x10.
        // +0x58E4 / +0x5954: 真实 IOKit 符号 _IOHIDEventSetScrollMomentum.
        IOHIDEventSetScrollMomentum(parent, momentum)
        return [opaqueBridgeToHIDEvent(parent)]
        // 该 translator 没有读取 field 88 / 96 / 97 或 hasPreciseScrollingDeltas.
        // 非零 sender 分支没有按 Magic Trackpad 型号 / vendor / descriptor 分流.
    }
}

// 6. CG phase -> NSEvent.Phase -> UH.HIDEventPhase, 数值不可混用.
// AppKit -[NSEvent phase], AppKit +0x1D1E88, scrollWheel 分支读取 CG field 99.
// CG -> NSEvent: evidence/2026-10-09/appkit-phase-mapping.txt.
// NSEvent -> HID: evidence/2026-10-09/mos-iphone-scroll-core.txt.
func reconstructedAppKitScrollPhase(_ cg: CGEvent) -> NSEvent.Phase {
    // AppKit 比较低 8 位的完整值, 不是按每一位合并 phase.
    switch cg.getIntegerValueField(fieldNumber: 99) & 0xFF {
    case 1: return .began       // NSEvent rawValue 1.
    case 2: return .changed     // NSEvent rawValue 4.
    case 4: return .ended       // NSEvent rawValue 8.
    case 8: return .cancelled   // NSEvent rawValue 16.
    case 128: return .mayBegin  // NSEvent rawValue 32.
    default: return []
    }
}

// UHK +0x88B0: 这里处理的是 NSEvent 的 OptionSet, 按位合并 HID phase.
// NSEvent.stationary = 2; 当前 AppKit 的 CG scroll phase 分支没有生成它.
// 证据: evidence/2026-10-09/mos-iphone-scroll-core.txt 的 phase 映射.
func reconstructedHIDPhase(_ ns: NSEvent.Phase) -> HIDEventPhase {
    var phase: HIDEventPhase = []
    if ns.contains(.began) { phase.insert(.began) }
    if ns.contains(.stationary) { phase.insert(.changed) }
    if ns.contains(.changed) { phase.insert(.changed) }
    if ns.contains(.ended) { phase.insert(.ended) }
    if ns.contains(.cancelled) { phase.insert(.canceled) }
    if ns.contains(.mayBegin) { phase.insert(.mayBegin) }
    return phase
}

// AppKit -[NSEvent momentumPhase], AppKit +0x26C2B0.
// CG field 123 的 1 / 2 / 3 经查表成为 NSEvent 的 1 / 4 / 8.
// 证据: evidence/2026-10-09/appkit-phase-mapping.txt.
func reconstructedAppKitMomentumPhase(_ cg: CGEvent) -> NSEvent.Phase {
    switch cg.getIntegerValueField(fieldNumber: 123) {
    case 1: return .began
    case 2: return .changed
    case 3: return .ended
    default: return []
    }
}

// UHK +0x5880..0x58BC, 使用 NSEvent 完整 rawValue 做精确比较.
// UH getter +0x18D54..0x18D6C: start = 2, continue = 1, end = 4, interrupted = 16.
// 证据: evidence/2026-10-09/mos-iphone-scroll-core.txt 的 momentum 摘段.
func reconstructedHIDMomentum(_ ns: NSEvent.Phase) -> HIDScrollMomentum {
    switch ns.rawValue {
    case 1, 32: return .start
    case 4: return .continue
    case 8, 16: return .end
    default: return []
    }
}

// 7. UH.ScrollFilter.filterEvent, UH +0x6257C.
// +0x625E4: 先匹配 filter.eventMask 与 HID event 类型 mask.
// +0x62624: 查找 first<ScrollEvent>; +0x62638: ScrollReport(scrollEvent:).
// 证据: evidence/2026-10-09/mos-iphone-scroll-core.txt 的 ScrollFilter 摘段.
extension ScrollFilter {
    func observedScrollReportSegment(_ event: HIDEventProtocol) -> [HIDReport] {
        guard event.eventType.maskValue & eventMask != 0 else { return [] }
        guard let scroll = event.first(ScrollEvent.self) else { return [] }
        var report = ScrollReport(scrollEvent: scroll)
        // +0x62658..0x6277C: 读取 event.time, 写入报告时间数据.
        // 这里没有与旧 timestamp 比较, 具体报告尾部布局未完整还原.
        opaqueSerializeEventTime(&report, event.time)
        // +0x627A8..0x62850: update/copy mask 决定返回报告和保留事件.
        // event/notify 完整返回值留给接口说明, 不把本片段冒充完整 filter.
        return copyMask.contains(.scroll) ? [report.report] : []
    }
}

// 8. UH.ScrollCollection(scrollEvent:), UH +0x4E668.
// UH.ScrollReport(scrollEvent:), UH +0x4F044.
// 证据: evidence/2026-10-09/mos-iphone-scroll-core.txt 的 Collection 摘段.
extension ScrollCollection {
    init(scrollEvent: ScrollEvent) {
        self = opaqueAllocateScrollCollection()
        // +0x4E6B8..0x4E798: 编码 momentum / phase 与父 scroll 的 raw delta.
        opaqueEncodePhaseAndMomentum(scrollEvent.phase, scrollEvent.momentum)
        rawX = reconstructedRawByte(scrollEvent.x)
        rawY = reconstructedRawByte(scrollEvent.y)

        // +0x4E79C: 查找 accelerated scroll 自身/子事件的辅助函数.
        // 在第 5 节创建的树中, accelerated 数据来自子 scroll.
        if let accelerated = opaqueFindAcceleratedScroll(scrollEvent) {
            accelX = HIDFixed(doubleValue: accelerated.x) ?? opaqueHIDFixedZero()
            accelY = HIDFixed(doubleValue: accelerated.y) ?? opaqueHIDFixedZero()
        } else {
            accelX = opaqueHIDFixedZero()
            accelY = opaqueHIDFixedZero()
        }
        // HIDFixed 的精确比例 / 溢出语义 / 字节排列未完整重建.
        // 不用 16.16 等猜测格式替代已有构造器.
    }
}

// UH +0x4EA9C: frinta -> 整数转换 -> 下限/上限选择 -> Int8 写入.
// 下限辅助 +0x4FBDC, 上限辅助 +0x4FB30. 有限且可表示的值具有以下语义.
// 非有限/无法转换值可触发原函数的 trap; 此处不虚构恢复策略.
func reconstructedRawByte(_ delta: Double) -> Int8 {
    let rounded = delta.rounded(.toNearestOrAwayFromZero)
    let integer = opaqueCheckedIntegerConversion(rounded)
    return Int8(min(127, max(-128, integer)))
}

extension ScrollReport {
    init(scrollEvent: ScrollEvent) {
        let collection = ScrollCollection(scrollEvent: scrollEvent)
        self = opaqueAllocateReport(for: ReportID.scroll)
        opaqueStoreScrollCollection(collection)
        // UH +0x4F0BC 将 ReportID.scroll 的已确认值 7 传给 HIDReport 构造器.
        // 这个 7 是报告类别, 不能当作 senderID / CG phase / 每次滚动的 eventID.
    }
}

// 9. SSK.UHIDBackedHIDServicePrimitives.lookUpServiceInfo, SSK +0x88284.
// 证据: evidence/2026-10-09/mos-iphone-scroll-core.txt 的 lookup 摘段.
extension UHIDBackedHIDServicePrimitives {
    func observedLookupSegment(for report: HIDReport, senderID: UInt64)
        -> OpaqueServiceInfo? {
        if senderID == 0 { return nil } // +0x88368 -> +0x88444 -> +0x88830.
        for service in currentObservedHIDServices {
            if service.serviceID == senderID { // +0x88410..0x88418.
                return opaqueBuildServiceInfo(service)
            }
        }
        return nil
        // 上层第 2 节在 lookup 前完成零 sender 的 basicMouseServiceID 回退.
        // 属性构造细节未完全还原; 此处没有已发现的 Magic 型号白名单.
    }
}

// 已确认 UH.HIDServiceProperties 存在以下字段, 不据字段名推导远端判定.
// 字段符号与 offset: evidence/2026-10-09/sdk-and-service-properties.txt.
// deviceTypeHint / reportDescriptor / deviceUsagePairs / primaryUsagePair.
// supportsGestureScrolling / dispatchScrollEvents / useRemoteAcceleration.
// scrollResolution / scrollReportRate / scrollAccelerationType.
// mouseScrollAcceleration / trackpadScrollAcceleration / vendorID / productID.
// 上述符号可在同版本 UH exports 对照. iPhone 下游消费方式未分析.

// 10. 异步边界. 消息 case / 队列次序 / 更新条件尚未还原.
// SCUI +0x1F7AC / +0x20428: AsyncStream.Continuation.yield.
// 私有类型符号: HIDCaptureViewModel.HIDMessage.
// 同一处理链还有 HID inputDevices 更新 / cache 处理 / 更新统计调用.
// +0x2036C: HIDDebugInfo.updatedHIDInputDevices, 不能单凭统计确定网络已发送.
// 证据: evidence/2026-10-09/screencontinuity-ui-segments.txt.
protocol UnreconstructedCaptureAsyncBoundary {
    func yield(_ message: OpaqueHIDMessage)
    // 以下是发送边界的真实方法签名, 未表示每个滚轮都调用设备更新.
    func sendHIDInputDevices(deviceID: UUID, inputDevices: [SSKHIDServiceProperties]) async
    func sendHIDReport(sender: EventReportSenderID, reportData: Data, eventID: UInt64?) async
}

// 11. ScreenSharingKit.ScreenSharingSession 的确认入口.
// SCUI imports 的 sendHIDReport async TjTu 原型已 demangle 复核.
// SCUI GOT offset +0x10DCD8; 具体调用的 async 函数起始 offset 未定位.
// sendHIDInputDevices 的原型也已确认, 实际触发条件和传输编码未展开.
// 证据: evidence/2026-10-09/screencontinuity-ui-segments.txt.
extension ScreenSharingSession {
    func sendHIDReport(
        sender: UniversalHID.EventReportSenderID,
        reportData: Foundation.Data,
        eventID: Swift.UInt64?
    ) async {
        /* 已确认接口边界. session 内部网络封装与 iPhone 接收代码未分析. */
    }
}

// 已检查的 Translator / Observer / ScrollFilter 路径没有按相同 delta /
// eventID 或旧 timestamp 丢弃重复事件的分支. 这不覆盖未分析的发送/接收层.
// 在 CGEvent 存在且 sender 非零的分支, 只改 PointDelta 96/97 无法改变被编码的 raw/accelerated.
// sender = 0 可进入 AppKit delta fallback, 但 raw Int8 取整与 accel = 0
// 仍与带 accelerated 子事件的路径不同, 不能由此推断修复已经完成.
