import Foundation
import CoreGraphics
import QuartzCore

/// 一次捕获到的滚轮事件, 已由 TapController 换算成引擎可能用到的三种位移
/// 所有数值均为 CGEvent 符号约定, 已包含用户的自然滚动设置和 Lab 的翻转开关
struct ScrollInput {
    /// 指数逼近插值使用的像素位移 (格数 × stepPx, 或系统加速后的像素位移)
    var dx: Double
    var dy: Double
    /// 原始行数 (滚轮格数), 供不平滑的滚轮重投和虚拟鼠标使用
    var notchX: Double
    var notchY: Double
    /// Mos 自身读取的位移: 优先像素位移, 依次回退到定点位移和行位移 (对应 Mos ScrollEvent.initEvent)
    var mosX: Double
    var mosY: Double
    var location: CGPoint
}

/// Mos ScrollFilter: 每次输出是上一次输出向上一次输入移动 23% 的结果 (滞后一帧)
private struct MosFilter {
    private var window = [0.0, 0.0]
    /// `alpha` 为每帧靠近比例, Mos 固定为 0.23; 时间归一化时按帧间隔换算
    mutating func fill(_ next: Double, alpha: Double = 0.23) -> Double {
        let first = window[1]
        window = [first, first + alpha * (next - first)]
        return window[0]
    }
    mutating func reset() { window = [0.0, 0.0] }
}

/// Mos durationTransition: 由过渡滑块 (0...5) 换算出的每帧插值比例
func mosTransition(_ duration: Double) -> Double {
    (1000 * (1 - (duration / 5.2).squareRoot())).rounded() / 1000
}

/// 所有活动显示器中最高的刷新率, 即 Mos 的 CVDisplayLink 运行频率
func maxDisplayHz() -> Double {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 60 }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return 60 }
    let hz = ids.prefix(Int(count)).compactMap { CGDisplayCopyDisplayMode($0)?.refreshRate }.max() ?? 60
    return hz > 0 ? hz : 60
}

/// 把捕获到的滚轮输入转换成所选输出方式的逐帧输出。所有状态都只在 `queue` 上访问
///
/// 一次滚动会话的生命周期:
/// 1. `input` (由 tap 线程调用) 累积待滚动距离, 计时器未运行时启动逐帧计时器
/// 2. `tick` 按显示器刷新率 (或 `frameHz`) 运行。每帧向插值模型取本帧距离,
///    交给 `emitFrame` 转换成所选输出 (CGEvent, HID 报文等)
/// 3. 插值模型没有剩余距离且 `endGraceMs` 内没有新输入时, `finishIfIdle` 结束手势
///    (发送结束阶段或抬起手指), 按需启动合成惯性, 并停止计时器
///
/// 这里的 "手势" 指一次连续输出: phased 滚动对应 Began 到 Ended, 虚拟触控板对应落指到抬指,
/// 虚拟鼠标只用它标记是否已发送指针微动
struct FrameSnapshot {
    var gesture = 0
    var frame = 0
    var tickTime: Double = 0
}

final class ScrollEngine {
    static let frameSnapshot = Locked(FrameSnapshot())
    static let shared = ScrollEngine()
    private let queue = DispatchQueue(label: "lab.engine", qos: .userInteractive)
    /// 当前运行的帧时钟; 只在会话期间存在
    private var timer: FrameClock?
    /// 创建当前时钟时的类型与帧率, 二者变化时重建时钟
    private var timerKey = ""
    private var timerHz: Double = 0
    private lazy var forwarder = TickForwarder(queue: queue) { [weak self] in self?.tick() }

    /// 最近一次输入时的配置快照; 下一次输入到来前的每一帧都使用它
    private var cfg = LabConfig()
    /// 最近一次输入时的光标位置; 合成的 CGEvent 投递到这个位置
    private var location = CGPoint.zero
    /// 指数逼近插值尚未输出的距离
    private var pendX = 0.0, pendY = 0.0
    /// 输出只接受整数 (像素, 滚轮单位) 时, 在帧之间结转的不足一个单位的余量
    private var remX = 0.0, remY = 0.0
    /// phone-harness "事件个数" 编码的距离累加器 (每满 ptPerEvent 发一个固定增量事件)
    private var bucketY = 0.0
    private var lastInputNs: UInt64 = 0
    /// 从会话的第一帧输出到 `endGesture` 之间为 true
    private var gestureOpen = false
    /// 最近三帧输出, 取平均值作为合成惯性的初速度
    private var recent: [(x: Double, y: Double)] = []
    /// 合成惯性当前的每帧速度; 没有惯性时为 nil
    private var momentumV: (x: Double, y: Double)?
    private var momentumStarted = false
    /// 合成惯性阶段不足 1 像素的余量, 与拖动阶段一样逐帧结转
    private var momentumRem = (x: 0.0, y: 0.0)
    /// 虚拟触控板 / 虚拟妙控板上手指当前的 Y 坐标, 单位是对应设备的逻辑坐标
    private var touchY = 2048.0
    /// 虚拟妙控板: 落指后手指保持静止的剩余帧数, 以及静止期间暂存的位移
    private var magicSettleLeft = 0
    private var magicHeld = 0.0
    /// 虚拟妙控板: 手指整体横向偏移, 以及落指静止期间暂存的横向位移
    private var touchX = 0.0
    private var magicHeldX = 0.0
    // Mos 插值状态
    private var mosBuffer = (x: 0.0, y: 0.0)
    private var mosCurrent = (x: 0.0, y: 0.0)
    private var mosLastDelta = (x: 0.0, y: 0.0)
    private var mosFilterX = MosFilter(), mosFilterY = MosFilter()

    private var useMos: Bool { cfg.smooth && cfg.smoothing == .mos }

    /// 上一帧 tick 的时间 (秒), 用于计算实际帧间隔; 时钟重建时清零
    private var lastTickTime: Double = 0
    /// 本帧实际间隔, 限制在 [1/480, 0.1] 秒, 避免首帧和长时间停顿产生极端值
    private var frameDt: Double = 1.0 / 60

    /// 时间归一化系数: 本帧相当于基准帧率下的多少帧。未开启归一化时恒为 1, 即保持 Mos 的按帧定义
    private var frameScale: Double { cfg.timeNormalize ? frameDt * cfg.referenceHz : 1 }

    /// 把按帧定义的比例 p (每帧完成 p) 换算到本帧: 1 - (1 - p)^frameScale, 是连续指数衰减的精确离散化
    private func perFrame(_ p: Double) -> Double { 1 - pow(1 - p, frameScale) }
    private var effectiveHz: Double { cfg.followDisplayHz ? maxDisplayHz() : cfg.frameHz }

    /// tap 线程调用的入口。下面的代码都运行在 `queue` 上, 因此引擎状态无需加锁
    func input(_ input: ScrollInput, cfg: LabConfig) {
        queue.async { [self] in
            self.cfg = cfg
            location = input.location
            if timer == nil {
                Trace.beginGesture(mode: cfg.mode.label)
                Self.frameSnapshot.mutate { $0.gesture += 1; $0.frame = 0; $0.tickTime = 0 }
            }
            Trace.updateLatest { $0.inputEvents += 1 }
            Trace.add(.input, input.dy, x: input.dx)
            if momentumV != nil { endMomentum() }
            lastInputNs = DispatchTime.now().uptimeNanoseconds
            // 不平滑时, 两种 "滚轮" 输出直接逐格转发, 不经过逐帧输出
            if !cfg.smooth {
                switch cfg.mode {
                case .wheelRepost:
                    CGOutput.lineScroll(notchX: input.notchX, notchY: input.notchY, at: location, cfg: cfg)
                    return
                case .virtualMouse:
                    openVirtualMouseGesture()
                    VirtualMouse.shared.wheel(y: Int(input.notchY), x: Int(input.notchX))
                    ensureTimer()
                    return
                default:
                    break
                }
            }
            if useMos {
                mosAccumulate(input)
            } else {
                pendX += input.dx
                pendY += input.dy
            }
            ensureTimer()
        }
    }

    /// 结束进行中的手势和惯性; phased 滚动还会发送复位序列, 清除接收方因等待惯性而卡住的状态
    /// 在模式切换和 ⌃⌥⌘R 快捷键时调用
    func resetGestureState() {
        queue.async { [self] in
            pendX = 0; pendY = 0
            mosClear()
            let wasPhased = cfg.mode == .phasedScroll
            endGesture()
            endMomentum()
            if wasPhased { CGOutput.resetSequence(at: location, cfg: cfg) }
            recent.removeAll()
            stopTimer()
        }
    }

    // MARK: - 计时器

    /// 启动逐帧计时器, 目标帧率变化时重建。计时器只在会话期间运行
    private func ensureTimer() {
        let hz = effectiveHz
        let key = "\(cfg.frameClock.rawValue)-\(cfg.frameClock == .dispatchTimer ? hz : 0)"
        if timer != nil && timerKey == key { return }
        stopTimer()
        let clock: FrameClock
        switch cfg.frameClock {
        case .dispatchTimer: clock = DispatchFrameClock(queue: queue, hz: hz) { [weak self] in self?.tick() }
        case .cvDisplayLink: clock = CVFrameClock(forwarder: forwarder)
        case .screenDisplayLink: clock = ScreenFrameClock(forwarder: forwarder)
        }
        clock.start()
        lastTickTime = 0
        timer = clock
        timerKey = key
        // 指数逼近插值按帧间隔计算比例; 显示器时钟按最高刷新率估算
        timerHz = hz
        Lab.clockSummary.set(clock.summary)
    }

    private func stopTimer() {
        if timer != nil { Trace.endGesture() }
        timer?.stop()
        timer = nil
        Self.frameSnapshot.mutate { $0.tickTime = 0 }
    }

    /// 一帧输出。优先处理合成惯性, 其次是 Mos 插值, 最后是指数逼近插值
    private func tick() {
        let now = CACurrentMediaTime()
        Self.frameSnapshot.mutate { $0.frame += 1; $0.tickTime = now }
        frameDt = lastTickTime == 0 ? 1.0 / timerHz : min(max(now - lastTickTime, 1.0 / 480), 0.1)
        lastTickTime = now
        if let v = momentumV { stepMomentum(v); return }
        if useMos { mosTick(); return }
        defer { magicKeepAlive() }

        var ex = pendX, ey = pendY
        if cfg.smooth {
            // 指数逼近: 待输出距离的约 95% 在 durationMs 内输出
            let tau = max(cfg.durationMs, 1) / 1000 / 3
            let k = 1 - exp(-(cfg.timeNormalize ? frameDt : 1.0 / timerHz) / tau)
            ex = abs(pendX) < 0.5 ? pendX : pendX * k
            ey = abs(pendY) < 0.5 ? pendY : pendY * k
        }
        pendX -= ex
        pendY -= ey
        if ex != 0 || ey != 0 {
            if handOff(dx: ex, dy: ey) { return }
            emitFrame(dx: ex, dy: ey)
            recent.append((ex, ey))
            if recent.count > 3 { recent.removeFirst() }
            return
        }

        finishIfIdle()
    }

    /// 插值末段的交接: 单帧位移已在下降且低于阈值时, 不再等插值收尾和结束等待。
    /// phased 合成惯性: 发出 Ended 并以本帧速度起步惯性, 衔接处速度连续。
    /// 虚拟妙控板: 立即抬指, 由系统按手指当前速度生成惯性。返回 true 表示本帧已被交接处理
    private func handOff(dx: Double, dy: Double) -> Bool {
        guard gestureOpen else { return false }
        let speed = hypot(dx, dy)
        let decelerating = recent.last.map { speed < hypot($0.x, $0.y) } ?? false
        guard decelerating else { return false }
        switch cfg.mode {
        case .phasedScroll where cfg.momentum == .synthetic && cfg.momentumHandoffPx > 0 && speed < cfg.momentumHandoffPx * frameScale:
            endGesture()
            startMomentum(dx: dx, dy: dy)
        case .magicTrackpad where cfg.magicLiftPx > 0 && magicSettleLeft == 0 && speed < cfg.magicLiftPx * frameScale:
            endGesture()
            recent.removeAll()
            pendX = 0; pendY = 0
            mosClear()
            stopTimer()
        default:
            return false
        }
        return true
    }

    /// 以一帧位移为初速度启动合成惯性。速度以 "基准帧率下的每帧位移" 保存, 输出时再乘帧间隔系数
    private func startMomentum(dx: Double, dy: Double) {
        momentumV = (x: dx / frameScale, y: dy / frameScale)
        momentumStarted = false
        momentumRem = (0, 0)
        recent.removeAll()
        pendX = 0; pendY = 0
        mosClear()
    }

    /// 输入静默超过 `endGraceMs` 后结束会话; 等待期让快速连续的多格滚动合并为同一个手势
    private func finishIfIdle() {
        let idleMs = Double(DispatchTime.now().uptimeNanoseconds - lastInputNs) / 1e6
        guard idleMs >= cfg.endGraceMs else { return }
        endGesture()
        // 惯性初速度取最后一帧, 平均值会大于末段逐帧减小的最后一帧, 衔接处会突然加速
        if cfg.mode == .phasedScroll, cfg.momentum == .synthetic, let last = recent.last,
           hypot(last.x, last.y) >= cfg.momentumMinPx * 2 * frameScale {
            startMomentum(dx: last.x, dy: last.y)
            return
        }
        recent.removeAll()
        stopTimer()
    }

    // MARK: - Mos 插值 (对应 ScrollCore.handleScroll 与 ScrollPoster.update / processing)

    private func mosAccumulate(_ input: ScrollInput) {
        // 小于一个步长的输入补足到步长; 同方向输入累加, 方向反转时重新开始
        func normalized(_ v: Double) -> Double { v == 0 ? 0 : (v > 0 ? max(v, cfg.mosStep) : -max(-v, cfg.mosStep)) }
        let y = normalized(input.mosY), x = normalized(input.mosX)
        if y * mosLastDelta.y > 0 { mosBuffer.y += y * cfg.mosSpeed } else { mosBuffer.y = y * cfg.mosSpeed; mosCurrent.y = 0 }
        if x * mosLastDelta.x > 0 { mosBuffer.x += x * cfg.mosSpeed } else { mosBuffer.x = x * cfg.mosSpeed; mosCurrent.x = 0 }
        mosLastDelta = (x: x, y: y)
    }

    /// Mos 的每帧步骤: 移动剩余距离的 `trans` 比例, 经过 23% 滞后滤波, 超过死区才输出
    /// 剩余距离进入死区后结束会话
    private func mosTick() {
        defer { magicKeepAlive() }
        let trans = perFrame(mosTransition(cfg.mosDuration))
        let alpha = perFrame(0.23)
        // 死区针对单帧位移; 归一化时按帧间隔缩放, 使截断发生在相同的速度上
        let deadZone = cfg.mosDeadZone * frameScale
        let frame = (x: (mosBuffer.x - mosCurrent.x) * trans, y: (mosBuffer.y - mosCurrent.y) * trans)
        mosCurrent = (x: mosCurrent.x + frame.x, y: mosCurrent.y + frame.y)
        let out = (x: mosFilterX.fill(frame.x, alpha: alpha), y: mosFilterY.fill(frame.y, alpha: alpha))
        let residual = max(abs(mosBuffer.y - mosCurrent.y), abs(mosBuffer.x - mosCurrent.x))
        let output = max(abs(out.y), abs(out.x))
        if output > deadZone {
            if handOff(dx: out.x, dy: out.y) { return }
            emitFrame(dx: out.x, dy: out.y)
            recent.append((out.x, out.y))
            if recent.count > 3 { recent.removeFirst() }
            return
        }
        guard residual <= cfg.mosDeadZone else { return }
        finishIfIdle()
        if timer == nil || momentumV != nil { mosClear() }
    }

    /// 真实触控板在手指接触期间每帧都上报; 没有位移的帧重复上报当前位置
    private var magicFrameSent = false
    private func magicKeepAlive() {
        defer { magicFrameSent = false }
        guard cfg.mode == .magicTrackpad, cfg.magicKeepAlive, gestureOpen, !magicFrameSent else { return }
        if magicSettleLeft > 0 { magicSettleLeft -= 1 }
        VirtualMagicTrackpad.shared.touch(x: touchX, y: touchY, first: false)
    }

    private func mosClear() {
        mosBuffer = (0, 0); mosCurrent = (0, 0); mosLastDelta = (0, 0)
        mosFilterX.reset(); mosFilterY.reset()
    }

    // MARK: - 各输出方式

    /// 把一帧平滑后的距离 (CGEvent 像素, 符号即目标 App 应看到的方向) 转换成所选输出
    private func emitFrame(dx: Double, dy: Double) {
        Recorder.shared.recordFrame(dx: dx, dy: dy, cfg: cfg)
        Trace.add(.engine, dy, x: dx)
        Trace.updateLatest { $0.framesSent += 1 }
        magicFrameSent = true
        switch cfg.mode {
        case .wheelRepost:
            remX += dx; remY += dy
            let ix = remX.rounded(.towardZero), iy = remY.rounded(.towardZero)
            guard ix != 0 || iy != 0 else { return }
            remX -= ix; remY -= iy
            CGOutput.pixelScroll(dx: Int32(ix), dy: Int32(iy), at: location, cfg: cfg)
        case .phasedScroll:
            phasedFrame(dx: dx, dy: dy)
        case .virtualMouse:
            openVirtualMouseGesture()
            remX += dx / cfg.pxPerWheelUnit
            remY += dy / cfg.pxPerWheelUnit
            let ux = remX.rounded(.towardZero), uy = remY.rounded(.towardZero)
            guard ux != 0 || uy != 0 else { return }
            remX -= ux; remY -= uy
            VirtualMouse.shared.wheel(y: Int(uy), x: Int(ux))
        case .magicTrackpad:
            // 本帧距离换算成虚拟妙控板上的手指位移; 系统自己的多点触控栈再把手指位移
            // 转换成触控板滚动事件 (包含系统的加速, 以及抬指后的惯性)
            // 开启自然滚动时, 手指向下移动对应正的 CG 位移; 关闭时符号相反
            // 横向同理: 默认假设手指向右对应正的 CG 横向位移, 方向相反时用"翻转横向手指方向"纠正
            let natural: Double = VirtualMouse.naturalScrolling ? 1 : -1
            let finger = dy * cfg.magicScale * natural
            let fingerX = dx * cfg.magicScale * natural * (cfg.magicFlipHorizontal ? -1 : 1)
            if !gestureOpen {
                gestureOpen = true
                // 新手势前发送打断信号: 以虚拟妙控板的身份发送惯性结束 + 预备 + 取消, 让 iPhone 端停止惯性滑行
                if cfg.resetBeforeGesture, let sender = VirtualMagicTrackpad.serviceIDs.get().min() {
                    CGOutput.resetSequence(at: location, cfg: cfg, sender: sender, target: .hid)
                }
                touchY = Double(VirtualMagicTrackpad.centerY)
                touchX = 0
                magicSettleLeft = Int(cfg.magicSettleFrames)
                magicHeld = finger
                magicHeldX = fingerX
                VirtualMagicTrackpad.shared.touch(x: touchX, y: touchY, first: true)
                return
            }
            if magicSettleLeft > 0 {
                // 手指先原地停留几帧再移动, 期间暂存的位移在之后一并补上
                magicSettleLeft -= 1
                magicHeld += finger
                magicHeldX += fingerX
                VirtualMagicTrackpad.shared.touch(x: touchX, y: touchY, first: false)
                return
            }
            touchY += finger + magicHeld
            touchX += fingerX + magicHeldX
            magicHeld = 0
            magicHeldX = 0
            // 手指到达触控板边缘: 抬起后在中央重新落下, 与在真实触控板上换手的动作相同
            let range = VirtualMagicTrackpad.offsetXRange
            if touchY < 300 || touchY > Double(VirtualMagicTrackpad.maxY - 300)
                || touchX < Double(range.lowerBound) || touchX > Double(range.upperBound) {
                VirtualMagicTrackpad.shared.lift()
                touchY = Double(VirtualMagicTrackpad.centerY) + finger
                touchX = fingerX
                VirtualMagicTrackpad.shared.touch(x: 0, y: Double(VirtualMagicTrackpad.centerY), first: true)
            }
            VirtualMagicTrackpad.shared.touch(x: touchX, y: touchY, first: false)
        case .virtualTouchpad:
            if !gestureOpen {
                gestureOpen = true
                touchY = 2048
                VirtualTouchpad.shared.touch(y: touchY)
            }
            touchY += dy * cfg.touchpadScale
            if touchY < 200 || touchY > 3900 {
                VirtualTouchpad.shared.lift()
                touchY = 2048
            }
            VirtualTouchpad.shared.touch(y: touchY)
        case .passthrough, .rewriteInPlace:
            break
        }
    }

    /// phased 滚动: 手势第一帧为 Began (1), 之后为 Changed (2)。接收方会忽略位移为 0 的 Began
    /// (phone-harness 的结论), 因此取整为 0 的帧不发送, 余量结转到下一帧
    private func phasedFrame(dx: Double, dy: Double) {
        if cfg.distance == .count {
            let sign: Double = dy >= 0 ? 1 : -1
            if !gestureOpen {
                openPhasedGesture()
                CGOutput.phased(dx: 0, dy: sign * 9, phase: 1, momentum: 0, at: location, cfg: cfg)
                gestureOpen = true
            }
            bucketY += dy
            while abs(bucketY) >= cfg.ptPerEvent {
                let s: Double = bucketY > 0 ? 1 : -1
                CGOutput.phased(dx: 0, dy: s * 9, phase: 2, momentum: 0, at: location, cfg: cfg)
                bucketY -= s * cfg.ptPerEvent
            }
            return
        }
        remX += dx; remY += dy
        let ix = remX.rounded(.towardZero), iy = remY.rounded(.towardZero)
        guard ix != 0 || iy != 0 else { return }
        remX -= ix; remY -= iy
        if !gestureOpen {
            openPhasedGesture()
            CGOutput.phased(dx: ix, dy: iy, phase: 1, momentum: 0, at: location, cfg: cfg)
            gestureOpen = true
        } else {
            CGOutput.phased(dx: ix, dy: iy, phase: 2, momentum: 0, at: location, cfg: cfg)
        }
    }

    private func openPhasedGesture() {
        if cfg.resetBeforeGesture { CGOutput.resetSequence(at: location, cfg: cfg) }
        if cfg.mayBegin { CGOutput.phased(dx: 0, dy: 0, phase: 128, momentum: 0, at: location, cfg: cfg) }
    }

    private func openVirtualMouseGesture() {
        guard !gestureOpen else { return }
        gestureOpen = true
        if cfg.pointerNudge { VirtualMouse.shared.nudge() }
    }

    private func endGesture() {
        guard gestureOpen else { return }
        gestureOpen = false
        remX = 0; remY = 0; bucketY = 0
        switch cfg.mode {
        case .phasedScroll: CGOutput.phased(dx: 0, dy: 0, phase: 4, momentum: 0, at: location, cfg: cfg)
        case .virtualTouchpad: VirtualTouchpad.shared.lift()
        case .magicTrackpad: VirtualMagicTrackpad.shared.lift()
        default: break
        }
    }

    private func stepMomentum(_ v: (x: Double, y: Double)) {
        // 惯性的每帧衰减同样按帧间隔换算; 速度单位是每帧位移, 因此也随帧间隔缩放
        let decay = pow(cfg.momentumDecay, frameScale)
        let next = (x: v.x * decay, y: v.y * decay)
        guard hypot(next.x, next.y) >= cfg.momentumMinPx else {
            endMomentum()
            stopTimer()
            return
        }
        momentumV = next
        // 本帧位移 = 速度 × 帧间隔系数; 不足 1 像素的部分结转到下一帧, 不再强制补成 1 像素
        momentumRem.x += next.x * frameScale
        momentumRem.y += next.y * frameScale
        let ix = momentumRem.x.rounded(.towardZero), iy = momentumRem.y.rounded(.towardZero)
        Recorder.shared.recordFrame(dx: next.x * frameScale, dy: next.y * frameScale, cfg: cfg)
        Trace.add(.engine, next.y * frameScale, x: next.x * frameScale)
        guard ix != 0 || iy != 0 else { return }
        momentumRem.x -= ix; momentumRem.y -= iy
        CGOutput.phased(dx: ix, dy: iy, phase: 0, momentum: momentumStarted ? 2 : 1, at: location, cfg: cfg)
        momentumStarted = true
    }

    private func endMomentum() {
        guard momentumV != nil else { return }
        momentumV = nil
        CGOutput.phased(dx: 0, dy: 0, phase: 0, momentum: 3, at: location, cfg: cfg)
    }
}

enum CGOutput {
    static func post(_ event: CGEvent, _ target: PostTarget, cfg: LabConfig, kind: String) {
        switch target {
        case .hid: event.post(tap: .cghidEventTap)
        case .session: event.post(tap: .cgSessionEventTap)
        case .annotatedSession: event.post(tap: .cgAnnotatedSessionEventTap)
        case .mirroringPid:
            guard let pid = MirroringLocator.shared.state.get().pid else {
                Recorder.shared.recordEmitted(event, kind: kind, target: target, cfg: cfg, outcome: "dropped_no_target")
                return
            }
            event.postToPid(pid)
        }
        Recorder.shared.recordEmitted(event, kind: kind, target: target, cfg: cfg)
        Lab.stats.mutate { $0.emitted += 1 }
    }

    static func lineScroll(notchX: Double, notchY: Double, at point: CGPoint, cfg: LabConfig) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                              wheel1: Int32(notchY), wheel2: Int32(notchX), wheel3: 0) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: ownEventMarker)
        e.location = point
        post(e, cfg.postTarget, cfg: cfg, kind: "post_line")
    }

    static func pixelScroll(dx: Int32, dy: Int32, at point: CGPoint, cfg: LabConfig) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: cfg.repostContinuous ? 1 : 0)
        e.setIntegerValueField(.eventSourceUserData, value: ownEventMarker)
        e.location = point
        post(e, cfg.postTarget, cfg: cfg, kind: "post_pixel")
    }

    /// 带触控板手势阶段 (1 开始, 2 持续, 4 结束, 8 取消, 128 预备) 的连续像素滚动事件,
    /// 或带惯性阶段 (1 开始, 2 持续, 3 结束) 的事件
    static func phased(dx: Double, dy: Double, phase: Int64, momentum: Int64, at point: CGPoint, cfg: LabConfig,
                       sender: Int64? = nil, target: PostTarget? = nil) {
        guard let e = makePhased(dx: dx, dy: dy, phase: phase, momentum: momentum, at: point, cfg: cfg, sender: sender) else { return }
        post(e, target ?? cfg.postTarget, cfg: cfg, kind: "post_phased")
        if cfg.gestureCompanion && momentum == 0 { companion(dx: dx, dy: dy, phase: phase, at: point, cfg: cfg) }
    }

    static func makePhased(dx: Double, dy: Double, phase: Int64, momentum: Int64, at point: CGPoint, cfg: LabConfig,
                           sender: Int64? = nil) -> CGEvent? {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else { return nil }
        let ix = Int64(dx), iy = Int64(dy)
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        // 写入行位移 (11 / 12) 会按行重算定点位移和像素位移 (1 行 = 8 像素), 因此必须先写行位移, 再写 93 / 94 与 96 / 97
        e.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: iy.signum())
        e.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: ix.signum())
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: iy)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: ix == 0 && iy != 0 && cfg.crossAxisJitter ? -1 : ix)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy / 10)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx / 10)
        // 87 号字段非零时, 镜像的翻译器读取这四个 double 字段, 不读取像素位移
        if cfg.fillRawFields {
            e.setDoubleValueField(Field.accelY, value: dy * cfg.accelScale)
            e.setDoubleValueField(Field.accelX, value: dx * cfg.accelScale)
            e.setDoubleValueField(Field.rawY, value: dy * cfg.rawScale)
            e.setDoubleValueField(Field.rawX, value: dx * cfg.rawScale)
        }
        if let s = sender ?? senderValue(cfg) { e.setIntegerValueField(Field.sender, value: s) }
        if cfg.markOwnEvents { e.setIntegerValueField(.eventSourceUserData, value: ownEventMarker) }
        e.location = point
        return e
    }

    /// 依次发送惯性结束, 预备, 取消, 用于清除卡住的手势识别状态
    static func resetSequence(at point: CGPoint, cfg: LabConfig, sender: Int64? = nil, target: PostTarget? = nil) {
        phased(dx: 0, dy: 0, phase: 0, momentum: 3, at: point, cfg: cfg, sender: sender, target: target)
        phased(dx: 0, dy: 0, phase: 128, momentum: 0, at: point, cfg: cfg, sender: sender, target: target)
        phased(dx: 0, dy: 0, phase: 8, momentum: 0, at: point, cfg: cfg, sender: sender, target: target)
    }

    /// kCGSEventGesture (type 29) 的滚动子类型事件, 真实触控板每个滚动事件都伴随一个
    private static func companion(dx: Double, dy: Double, phase: Int64, at point: CGPoint, cfg: LabConfig) {
        guard let g = CGEvent(source: nil), let gestureType = CGEventType(rawValue: 29) else { return }
        g.type = gestureType
        g.setIntegerValueField(Field.gestureSubtype, value: 6)
        g.setIntegerValueField(Field.gesturePhase, value: phase)
        g.setDoubleValueField(Field.gestureDX, value: dx)
        g.setDoubleValueField(Field.gestureDY, value: dy)
        if let s = senderValue(cfg) { g.setIntegerValueField(Field.sender, value: s) }
        g.location = point
        post(g, cfg.postTarget, cfg: cfg, kind: "post_companion")
    }

    private static func senderValue(_ cfg: LabConfig) -> Int64? {
        switch cfg.sender {
        case .zero: return nil
        case .learnedTrackpad:
            let s = Lab.lastTrackpadSender.get()
            return s == 0 ? nil : s
        case .builtinTrackpad: return MultitouchSender.id
        case .virtualMagicTrackpad: return VirtualMagicTrackpad.serviceIDs.get().min()
        case .realMouse:
            let s = Lab.lastMouseSender.get()
            return s == 0 ? nil : s
        }
    }
}
