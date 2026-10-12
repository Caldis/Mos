import AppKit
import CoreGraphics

/// 在独立的 RunLoop 线程上持有滚动 event tap, 并把捕获到的滚轮输入交给引擎
///
/// 一格滚轮的事件路径:
/// 物理鼠标 → IOHIDEventSystem → WindowServer 生成 CGEvent → 按顺序经过各 event tap
/// (HID tap → Session tap → Annotated Session tap) → 目标 App
/// tap 位置决定本工具在这条链路的哪一处看到事件。iPhone 镜像在自身进程内读取 NSEvent 及其 CGEvent 字段;
/// sender 非零时它读取 175-178, 因此只改写公开位移字段的翻转 (Mos 的做法) 对镜像无效
///
/// 对每个滚动事件, tap 选择: 忽略 (自身输出, 范围外, 连续输入), 原地改写,
/// 或把位移交给 ScrollEngine 并返回 nil 吞掉原始事件
final class TapController {
    static let shared = TapController()
    let active = Locked(false)
    let statusText = Locked("未启动")

    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [unowned self] in
            RunLoop.current.add(NSMachPort(), forMode: .common)
            self.runLoop = CFRunLoopGetCurrent()
            ready.signal()
            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        thread.name = "lab.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        reinstall()
    }

    func reinstall() {
        guard let rl = runLoop else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) { [unowned self] in
            self.uninstall()
            self.install()
        }
        CFRunLoopWakeUp(rl)
    }

    private func install() {
        let cfg = ConfigStore.shared.live.get()
        let mask = (1 << CGEventType.scrollWheel.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: cfg.tapLocation.cg, place: cfg.tapPlacement.cg, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: tapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            active.set(false)
            statusText.set("创建失败: 需要辅助功能权限")
            return
        }
        let src = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        active.set(true)
        statusText.set("运行中: \(cfg.tapLocation.label), \(cfg.tapPlacement.label)")
    }

    private func uninstall() {
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let src = source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        tap = nil
        source = nil
        active.set(false)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
            Lab.stats.mutate { $0.tapReenabled += 1 }
            return pass
        case .keyDown:
            return handleHotkey(event) ? nil : pass
        case .scrollWheel:
            break
        default:
            return pass
        }

        let cfg = ConfigStore.shared.live.get()
        let sender = event.getIntegerValueField(Field.sender)
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        // 自身输出会回到这个 tap: CGEvent 带 UserData 标记, 虚拟 HID 设备产生的事件
        // 在 87 号字段中带有该设备 IOHIDEventService 的注册表 ID
        let own = event.getIntegerValueField(.eventSourceUserData) == ownEventMarker || Lab.ownSenders.get().contains(sender)
        if cfg.monitor && cfg.diagnostics { Lab.log(Self.describe(event, sender: sender, own: own)) }
        if own {
            Recorder.shared.recordCaptured(event, decision: "own_observed", cfg: cfg)
            let mom = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            let ptY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), ptX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            Trace.add(.system, Double(ptY), x: Double(ptX),
                      phase: event.getIntegerValueField(.scrollWheelEventScrollPhase), momentum: mom)
            Trace.updateLatest { if mom != 0 { $0.systemMomentum += 1 } else { $0.systemScroll += 1 } }
            Lab.stats.mutate { $0.ignoredOwn += 1 }
            return pass
        }
        if continuous && sender != 0 { Lab.lastTrackpadSender.set(sender) }
        if !continuous && sender != 0 { Lab.lastMouseSender.set(sender) }
        Lab.stats.mutate { $0.captured += 1 }

        guard cfg.enabled, cfg.mode != .passthrough else {
            Recorder.shared.recordCaptured(event, decision: "pass_disabled", cfg: cfg)
            return pass
        }
        if continuous && !cfg.includeContinuous {
            Recorder.shared.recordCaptured(event, decision: "pass_continuous", cfg: cfg)
            return pass
        }
        guard inScope(cfg, event.location) else {
            Recorder.shared.recordCaptured(event, decision: "pass_out_of_scope", cfg: cfg)
            Lab.stats.mutate { $0.outOfScope += 1 }
            return pass
        }
        if cfg.mode == .rewriteInPlace {
            Recorder.shared.recordCaptured(event, decision: "rewrite", cfg: cfg)
            Self.rewrite(event, cfg)
            Recorder.shared.recordEmitted(event, kind: "rewrite", target: nil, cfg: cfg, outcome: "returned_to_pipeline")
            return pass
        }

        var notchY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        var notchX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let pointY = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        let pointX = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        let useNotch = cfg.deltaSource == .notch && !continuous
        // Mos 使用系统加速后的像素位移, 依次回退到定点位移和行位移
        let fixedY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fixedX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        var mosY = pointY != 0 ? pointY : (fixedY != 0 ? fixedY : notchY)
        var mosX = pointX != 0 ? pointX : (fixedX != 0 ? fixedX : notchX)
        var dy = useNotch ? notchY * cfg.stepPx : pointY
        var dx = useNotch ? notchX * cfg.stepPx : pointX
        if cfg.invertVertical { dy = -dy; notchY = -notchY; mosY = -mosY }
        if cfg.invertHorizontal { dx = -dx; notchX = -notchX; mosX = -mosX }

        Recorder.shared.recordCaptured(event, decision: cfg.consumeOriginal ? "repost" : "repost_keep_original", cfg: cfg)
        if dx != 0 || dy != 0 || notchX != 0 || notchY != 0 || mosX != 0 || mosY != 0 {
            ScrollEngine.shared.input(ScrollInput(dx: dx, dy: dy, notchX: notchX, notchY: notchY, mosX: mosX, mosY: mosY,
                                                  location: event.location), cfg: cfg)
        }
        guard cfg.consumeOriginal else { return pass }
        Lab.stats.mutate { $0.consumed += 1 }
        return nil
    }

    private func inScope(_ cfg: LabConfig, _ point: CGPoint) -> Bool {
        let m = MirroringLocator.shared.state.get()
        switch cfg.scope {
        case .global: return true
        case .mirroringWindow: return m.rect?.contains(point) ?? false
        case .mirroringFrontmost: return m.frontmost
        }
    }

    /// ⌃⌥⌘M 开关处理, ⌃⌥⌘R 复位合成手势状态
    private func handleHotkey(_ event: CGEvent) -> Bool {
        let flags = event.flags
        guard flags.contains(.maskControl), flags.contains(.maskAlternate), flags.contains(.maskCommand) else { return false }
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 46:
            DispatchQueue.main.async { ConfigStore.shared.config.enabled.toggle() }
            return true
        case 15:
            ScrollEngine.shared.resetGestureState()
            return true
        default:
            return false
        }
    }

    /// 翻转原事件的方向。三组字段可以分别翻转:
    /// 普通 App 读取的公开位移 (11/12, 93/94, 96/97); sender 非零时 iPhone 镜像读取的原始与加速位移 (175-178);
    /// 以及镜像对 175-178 应用的 "设备方向已翻转" 标记 137
    private static func rewrite(_ e: CGEvent, _ cfg: LabConfig) {
        if cfg.rewritePublic && cfg.invertVertical {
            negate(e, .scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1)
        }
        if cfg.rewritePublic && cfg.invertHorizontal {
            negate(e, .scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2)
        }
        if cfg.rewriteRaw && cfg.invertVertical { negateDoubles(e, Field.accelY, Field.rawY) }
        if cfg.rewriteRaw && cfg.invertHorizontal { negateDoubles(e, Field.accelX, Field.rawX) }
        if cfg.rewriteFlag137 && (cfg.invertVertical || cfg.invertHorizontal) {
            e.setIntegerValueField(Field.inverted, value: e.getIntegerValueField(Field.inverted) == 1 ? 0 : 1)
        }
        Lab.stats.mutate { $0.emitted += 1 }
    }

    private static func negateDoubles(_ e: CGEvent, _ fields: CGEventField...) {
        for f in fields { e.setDoubleValueField(f, value: -e.getDoubleValueField(f)) }
    }

    private static func negate(_ e: CGEvent, _ line: CGEventField, _ point: CGEventField, _ fixed: CGEventField) {
        let l = e.getIntegerValueField(line), p = e.getIntegerValueField(point), f = e.getDoubleValueField(fixed)
        e.setIntegerValueField(point, value: -p)
        e.setDoubleValueField(fixed, value: -f)
        e.setIntegerValueField(line, value: -l)
    }

    private static func describe(_ e: CGEvent, sender: Int64, own: Bool) -> String {
        let i = { (f: CGEventField) in e.getIntegerValueField(f) }
        let d = { (f: CGEventField) in String(format: "%.2f", e.getDoubleValueField(f)) }
        return "\(own ? "自身" : "输入") sender=\(sender) cont=\(i(.scrollWheelEventIsContinuous)) phase=\(i(.scrollWheelEventScrollPhase)) mom=\(i(.scrollWheelEventMomentumPhase)) opt173=\(i(Field.momentumOption)) inv137=\(i(Field.inverted)) line=\(i(.scrollWheelEventDeltaAxis1)) pt=\(i(.scrollWheelEventPointDeltaAxis1)) fix=\(d(.scrollWheelEventFixedPtDeltaAxis1)) accY176=\(d(Field.accelY)) rawY178=\(d(Field.rawY)) x: pt=\(i(.scrollWheelEventPointDeltaAxis2)) acc175=\(d(Field.accelX)) raw177=\(d(Field.rawX))"
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    Unmanaged<TapController>.fromOpaque(refcon!).takeUnretainedValue().handle(type: type, event: event)
}
