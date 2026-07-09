//
//  Interceptor.swift
//  Mos
//  事件截取工具函数
//  Created by Caldis on 2018/3/18.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Interceptor {

    private var keeper: Timer?
    private var _eventTapRef: CFMachPort?
    private var _runLoopSourceRef: CFRunLoopSource?
    // source 所属 run loop 在创建时捕获: stop/deinit 可能发生在其他线程
    // (deinit 由最后一个强引用的释放线程决定), 届时再取 current run loop 会指向错误的 run loop
    private let owningRunLoop: CFRunLoop = CFRunLoopGetCurrent()

    /// keeper 触发的自动重启时间戳, 仅保留冷却窗口内的记录
    private var autoRestartHistory: [Date] = []

    // 防自锁: 主线程被阻塞时 (如 TCC 权限弹窗挂起同步文件调用), active tap 无响应,
    // 系统超时禁用 tap 后输入才恢复; keeper 若盲目重启会把刚恢复的输入再次冻住,
    // 用户永远点不到弹窗. 窗口期内重启达到上限即进入冷却, 让系统输入保持可用.
    static let autoRestartWindow: TimeInterval = 60
    static let autoRestartLimit = 3

    /// 纯函数: 窗口期内自动重启次数达到上限 → 冷却 (跳过本轮重启)
    static func isAutoRestartThrottled(history: [Date], now: Date) -> Bool {
        let windowStart = now.addingTimeInterval(-autoRestartWindow)
        return history.filter { $0 > windowStart }.count >= autoRestartLimit
    }

    /// 重启时的额外清理操作 (由调用方注入, 避免 Interceptor 耦合特定子系统)
    /// 注意: 闭包不应捕获 Interceptor 实例, 否则会形成循环引用
    var onRestart: (() -> Void)?
    /// 控制是否继续执行自动重启逻辑 (默认 true)
    var shouldRestart: (() -> Bool)?
    
    // 可访问对象只读
    public var eventTapRef: CFMachPort? { _eventTapRef }
    public var runLoopSourceRef: CFRunLoopSource? { _runLoopSourceRef }
    
    public init(event mask: CGEventMask, handleBy eventHandler: @escaping CGEventTapCallBack, listenOn eventTap: CGEventTapLocation, placeAt eventPlace: CGEventTapPlacement, for behaver: CGEventTapOptions) throws {
        // 创建拦截层
        guard let tap = CGEvent.tapCreate(tap: eventTap, place: eventPlace, options: behaver, eventsOfInterest: mask, callback: eventHandler, userInfo: nil) else {
            throw InterceptorError.eventTapCreationFailed
        }
        _eventTapRef = tap
        _runLoopSourceRef = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        // 启动
        try start()
    }
    
    deinit {
        // 先停止所有操作
        stop()
        // 清理 event tap
        if let tap = _eventTapRef {
            CGEvent.tapEnable(tap: tap, enable: false)
            _eventTapRef = nil
        }
        // 清理 run loop source
        if let source = _runLoopSourceRef {
            if CFRunLoopContainsSource(owningRunLoop, source, .commonModes) {
                CFRunLoopRemoveSource(owningRunLoop, source, .commonModes)
            }
            _runLoopSourceRef = nil
        }
    }
}

// MARK: - Error Type
extension Interceptor {
    enum InterceptorError: Error {
        case eventTapCreationFailed
        case eventTapEnableFailed
    }
}

// MARK: - 开关
extension Interceptor {
    @objc public func start() throws {
        // 创建拦截层
        guard let tap = _eventTapRef, let source = _runLoopSourceRef else {
            throw InterceptorError.eventTapEnableFailed
        }
        // 权限已被撤销时, 不启用 tap, 避免僵尸 tap 吞没系统事件
        guard AXIsProcessTrusted() else {
            NotificationCenter.default.post(name: .mosAccessibilityPermissionLost, object: nil)
            throw InterceptorError.eventTapEnableFailed
        }
        // 确保 source 没有被重复添加
        if !CFRunLoopContainsSource(owningRunLoop, source, .commonModes) {
            CFRunLoopAddSource(owningRunLoop, source, .commonModes)
        }
        // 启动拦截层
        CGEvent.tapEnable(tap: tap, enable: true)
        // 启动守护
        keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // 权限被撤销时, 主动停止 tap 并通知, 不等 restart 判断
            guard AXIsProcessTrusted() else {
                self.stop()
                self.onRestart?()
                NotificationCenter.default.post(name: .mosAccessibilityPermissionLost, object: nil)
                return
            }
            if !self.isRunning() {
                let now = Date()
                self.autoRestartHistory.removeAll { now.timeIntervalSince($0) >= Self.autoRestartWindow }
                guard !Self.isAutoRestartThrottled(history: self.autoRestartHistory, now: now) else {
                    NSLog("Mos: event tap auto-restart throttled (%d restarts within %.0fs), cooling down",
                          Self.autoRestartLimit, Self.autoRestartWindow)
                    return
                }
                self.autoRestartHistory.append(now)
                self.restart()
            }
        }
    }
    
    public func stop() {
        stop(removeFromRunLoop: true)
    }

    public func pause() {
        stop(removeFromRunLoop: false)
    }

    private func stop(removeFromRunLoop: Bool) {
        // 停止守护
        keeper?.invalidate()
        keeper = nil
        // 关闭拦截层
        if let tap = _eventTapRef, let source = _runLoopSourceRef {
            CGEvent.tapEnable(tap: tap, enable: false)
            if removeFromRunLoop, CFRunLoopContainsSource(owningRunLoop, source, .commonModes) {
                CFRunLoopRemoveSource(owningRunLoop, source, .commonModes)
            }
        }
    }
}

// MARK: - 状态
extension Interceptor {
    public func isRunning() -> Bool {
        if let tap = _eventTapRef {
            return CGEvent.tapIsEnabled(tap: tap)
        } else {
            return false
        }
    }
    
    public func restart() {
        // 权限已被撤销时, 不再尝试重新启用 tap
        guard AXIsProcessTrusted() else {
            stop()
            onRestart?()
            NotificationCenter.default.post(name: .mosAccessibilityPermissionLost, object: nil)
            return
        }
        pause()
        onRestart?()
        guard shouldRestart?() ?? true else { return }
        // 使用 closure timer 避免 @objc throws 方法作为 selector 的 ObjC bridge 问题
        keeper = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            try? self?.start()
        }
    }
}
