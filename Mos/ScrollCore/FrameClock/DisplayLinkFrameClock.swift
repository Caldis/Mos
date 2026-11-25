//
//  DisplayLinkFrameClock.swift
//  Mos
//  基于 CVDisplayLink 的帧时钟, 包含僵尸检测、冷却期重建与刷新率自纠
//

import Cocoa
import CoreVideo
import os

final class DisplayLinkFrameClock: ScrollFrameClock {

    let kind = ScrollFrameClockKind.displayLink
    var onTick: ((FrameTick) -> Void)?

    private var link: CVDisplayLink?
    private var preferredDisplay: ScrollDisplayLayout.Display?
    // 帧时间记录 (CVDisplayLink 线程写, 主线程的健康检查读)
    private var tickLock = os_unfair_lock_s()
    private var lastCallbackTime: CFTimeInterval = 0.0
    private var lastTickTimestamp: CFTimeInterval = 0.0
    // CVDisplayLink 恢复机制
    private var keeper: Timer?
    private var lastRecreateAttempt: CFTimeInterval = 0.0
    private let recreateCooldown: CFTimeInterval = 3.0
    // CVDisplayLink 刷新率自纠 (issue #958):
    // 显示器唤醒/重连时会先短暂报告过渡刷新率 (如先 60Hz 再升 144Hz), 若重建正好落在这个窗口,
    // 就会把 link 绑到偏低的刷新率, 使平滑滚动只按低帧率绘制 (卡顿), 而现有恢复机制识别不了.
    // 对策: 每次建立 link 后延迟复查若干次, 发现 link 标称率明显低于显示器实际率就重建追平.
    private var rateVerifyTimer: Timer?
    private var rateVerifyAttemptsLeft = 0
    private var isVerifying = false
    private let rateVerifyDelays: [TimeInterval] = [2.0, 4.0, 8.0]
    private let rateVerifyRatio = 0.7

    var isAvailable: Bool { link != nil }
    var isRunning: Bool { link.map { CVDisplayLinkIsRunning($0) } ?? false }

    // MARK: - 生命周期

    func setPreferredDisplay(_ display: ScrollDisplayLayout.Display?) {
        let previous = preferredDisplay
        guard previous != display else { return }
        preferredDisplay = display
        guard let current = link else { return }

        // Session setup owns the stopped clock. A mode change on the same display
        // recreates the link so it picks up the new nominal period.
        if let display, previous?.id != display.id {
            if CVDisplayLinkIsRunning(current) { CVDisplayLinkStop(current) }
            if bind(display, to: current) == kCVReturnSuccess {
                scheduleRateVerify()
                return
            }
        }
        prepare()
    }

    private func bind(_ display: ScrollDisplayLayout.Display, to clock: CVDisplayLink) -> CVReturn {
        if CVDisplayLinkGetCurrentCGDisplay(clock) == display.id { return kCVReturnSuccess }
        return CVDisplayLinkSetCurrentCGDisplay(clock, display.id)
    }

    func prepare() {
        // 清理旧的 CVDisplayLink
        if let old = link {
            if CVDisplayLinkIsRunning(old) {
                CVDisplayLinkStop(old)
            }
            link = nil
        }
        // 创建新的 CVDisplayLink, 检查返回值
        var created: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&created)
        if result == kCVReturnSuccess, let valid = created {
            if let display = preferredDisplay {
                let binding = bind(display, to: valid)
                if binding != kCVReturnSuccess {
                    NSLog("ScrollPoster: display link binding to %u failed (%d)", display.id, binding)
                }
            }
            CVDisplayLinkSetOutputCallback(valid, { (_, _, _, _, _, context) in
                Unmanaged<DisplayLinkFrameClock>.fromOpaque(context!).takeUnretainedValue().fire()
                return kCVReturnSuccess
            }, Unmanaged.passUnretained(self).toOpaque())
            link = valid
            // 建立成功后安排刷新率复查; 复查内部触发的重建 (isVerifying) 不重置复查序列
            if !isVerifying { scheduleRateVerify() }
        } else {
            link = nil
            NSLog("ScrollPoster: CVDisplayLink creation failed (%d)", result)
        }
    }

    @discardableResult
    func start() -> Bool {
        guard let valid = link else {
            // cooldown 拒绝重建时由调用方清理陈旧 buffer, 防止恢复后滚动跳变
            return rebuild()
        }
        if !CVDisplayLinkIsRunning(valid) {
            markStarted()
            if CVDisplayLinkStart(valid) != kCVReturnSuccess {
                rebuild()
            }
        }
        return true
    }

    func stop() {
        if let valid = link {
            CVDisplayLinkStop(valid)
        }
    }

    @discardableResult
    func rebuild() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRecreateAttempt >= recreateCooldown else { return false }
        lastRecreateAttempt = now
        prepare()
        if let valid = link {
            markStarted()
            let result = CVDisplayLinkStart(valid)
            if result != kCVReturnSuccess {
                NSLog("ScrollPoster: CVDisplayLink start failed after recreate (%d)", result)
            }
        }
        return true
    }

    // MARK: - 出帧

    /// 启动时重置帧间隔基准, 并给 keeper 一个宽限期, 防止误判新启动的 link 为僵尸
    private func markStarted() {
        os_unfair_lock_lock(&tickLock)
        lastCallbackTime = CFAbsoluteTimeGetCurrent()
        lastTickTimestamp = 0
        os_unfair_lock_unlock(&tickLock)
    }

    private func fire() {
        let now = CACurrentMediaTime()
        os_unfair_lock_lock(&tickLock)
        lastCallbackTime = CFAbsoluteTimeGetCurrent()
        let previous = lastTickTimestamp
        lastTickTimestamp = now
        os_unfair_lock_unlock(&tickLock)
        let interval = previous > 0 ? now - previous : nominalPeriod()
        onTick?(FrameTick(timestamp: now, interval: interval))
    }

    private func nominalPeriod() -> CFTimeInterval {
        guard let link = link else { return 1.0 / 60.0 }
        let hz = Self.nominalHz(link)
        return hz > 1 ? 1.0 / hz : 1.0 / 60.0
    }

    // MARK: - 健康检查 (与 Interceptor 的 keeper 模式一致)

    func startMonitoring() {
        keeper?.invalidate()
        keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.healthCheck()
        }
    }

    func stopMonitoring() {
        keeper?.invalidate()
        keeper = nil
        rateVerifyTimer?.invalidate()
        rateVerifyTimer = nil
        rateVerifyAttemptsLeft = 0
    }

    private func healthCheck() {
        guard let valid = link else {
            rebuild()
            return
        }
        if CVDisplayLinkIsRunning(valid) {
            os_unfair_lock_lock(&tickLock)
            let lastTime = lastCallbackTime
            os_unfair_lock_unlock(&tickLock)
            // lastTime > 0 避免首次回调前误判
            if lastTime > 0 && CFAbsoluteTimeGetCurrent() - lastTime > 2.0 {
                NSLog("ScrollPoster: zombie CVDisplayLink detected, recreating")
                rebuild()
            }
        }
    }

    // MARK: 刷新率自纠 (见属性处说明)

    // 建立 link 后调用: 重置复查序列并安排第一次复查
    private func scheduleRateVerify() {
        rateVerifyAttemptsLeft = rateVerifyDelays.count
        armNextRateVerify()
    }

    private func armNextRateVerify() {
        rateVerifyTimer?.invalidate()
        guard rateVerifyAttemptsLeft > 0 else { rateVerifyTimer = nil; return }
        let delay = rateVerifyDelays[rateVerifyDelays.count - rateVerifyAttemptsLeft]
        rateVerifyTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.verifyRateAndFixIfNeeded()
        }
    }

    // 复查: link 标称率明显低于显示器实际率 -> 重建追平 (幂等, 不受 recreateCooldown 限制)
    private func verifyRateAndFixIfNeeded() {
        rateVerifyAttemptsLeft -= 1
        guard let current = link else { rateVerifyTimer = nil; return }
        let nominal = Self.nominalHz(current)
        let expectedHz = preferredDisplay?.hz ?? Self.maxActiveDisplayHz()
        let wrongDisplay = preferredDisplay.map { CVDisplayLinkGetCurrentCGDisplay(current) != $0.id } ?? false
        let slow = nominal > 1 && expectedHz > 1 && nominal < expectedHz * rateVerifyRatio
        guard wrongDisplay || slow else {
            // 已追平显示器刷新率, 结束复查
            rateVerifyTimer = nil
            rateVerifyAttemptsLeft = 0
            return
        }
        if wrongDisplay {
            NSLog("ScrollPoster: display link is bound to another display, recreating")
        } else {
            NSLog("ScrollPoster: display link rate %.0fHz below display %.0fHz, recreating", nominal, expectedHz)
        }
        // 保持原运行状态: 若正在滚动 (running) 则重建后重新启动
        let wasRunning = CVDisplayLinkIsRunning(current)
        isVerifying = true
        prepare()
        isVerifying = false
        if wasRunning, let refreshed = link {
            markStarted()
            CVDisplayLinkStart(refreshed)
        }
        // 自纠说明显示器仍在过渡: 清除冷却, 让后续 screenChange 能及时用最终配置重建
        lastRecreateAttempt = 0
        // 这次重建可能仍落在过渡态, 继续后续复查直到追平或用尽次数
        armNextRateVerify()
    }

    // MARK: - 显示器刷新率查询 (刷新率自纠使用)

    /// CVDisplayLink 当前绑定显示器的标称刷新率 (Hz); 无效返回 -1
    static func nominalHz(_ link: CVDisplayLink) -> Double {
        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
        // 无效/indefinite 周期时 timeValue 或 timeScale 为 0
        guard period.timeValue != 0, period.timeScale != 0 else { return -1 }
        let seconds = Double(period.timeValue) / Double(period.timeScale)
        return seconds > 0 ? 1.0 / seconds : -1
    }

    /// 当前活跃显示器里最高刷新率 (Hz); 取不到返回 -1
    static func maxActiveDisplayHz() -> Double {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return -1 }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return -1 }
        var mx = -1.0
        for id in ids.prefix(Int(count)) {
            if let hz = CGDisplayCopyDisplayMode(id)?.refreshRate, hz > mx { mx = hz }
        }
        return mx
    }
}
