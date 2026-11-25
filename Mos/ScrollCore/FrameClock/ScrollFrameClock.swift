//
//  ScrollFrameClock.swift
//  Mos
//  平滑滚动的帧驱动抽象
//

import Foundation

/// 一帧的时间信息
struct FrameTick {
    /// 本帧回调时刻 (CACurrentMediaTime)
    let timestamp: CFTimeInterval
    /// 与上一帧的实际间隔 (秒); 启动后的第一帧取时钟的标称周期
    let interval: CFTimeInterval
}

/// 帧时钟种类
enum ScrollFrameClockKind: String {
    /// CVDisplayLink (CVDisplayLinkCreateWithActiveCGDisplays)
    case displayLink = "cvdisplaylink"
    /// A monotonic timer with a 60 Hz target cadence.
    case fixedRate = "timer"
    /// CADisplayLink bound to the display where the scroll session begins.
    case screen = "nsscreen"

    static func launchOverride(in arguments: [String]) -> Self? {
        guard let flag = arguments.lastIndex(of: "--mos-scroll-clock") else { return nil }
        let value = arguments.index(after: flag)
        guard arguments.indices.contains(value), let kind = Self(rawValue: arguments[value].lowercased()) else {
            NSLog("ScrollPoster: --mos-scroll-clock expects cvdisplaylink, timer, or nsscreen")
            return nil
        }
        return kind
    }
}

/// 驱动 ScrollPoster 逐帧计算的时钟。只负责出帧, 不含插值逻辑。
/// 生命周期方法在主线程调用; onTick 在时钟自己的线程上调用
protocol ScrollFrameClock: AnyObject {
    var kind: ScrollFrameClockKind { get }
    var onTick: ((FrameTick) -> Void)? { get set }
    /// 底层时钟已创建, 可以启动
    var isAvailable: Bool { get }
    var isRunning: Bool { get }
    /// 创建底层时钟 (会替换已有实例)
    func prepare()
    /// 开始出帧; 底层时钟不可用且无法重建时返回 false
    @discardableResult func start() -> Bool
    func stop()
    /// 按需重建底层时钟 (显示器变化等), 受冷却期约束; 被冷却期拒绝时返回 false
    @discardableResult func rebuild() -> Bool
    /// 启动或停止健康检查 (僵尸检测, 刷新率复查等)
    func startMonitoring()
    func stopMonitoring()
}
