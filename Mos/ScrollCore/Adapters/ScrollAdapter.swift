//
//  ScrollAdapter.swift
//  Mos
//  应用滚动适配器的接入协议
//
//  适配器为个别应用提供替代的滚动输出: 光标位于目标窗口内时, 原始滚轮事件在 HID 层被接管,
//  经 ScrollCore 的翻转与平滑决策后, 由适配器的输出端按目标应用能识别的形式投递。
//  接入规范见 .agents/docs/scroll-adapters.md
//

import Cocoa

/// 适配器的静态声明, ScrollAdapterCenter 据此决定是否注册与监听哪些应用
struct ScrollAdapterDescriptor {
    /// 稳定标识, 用于日志
    let identifier: String
    /// 目标应用的 bundle identifier
    let bundleIdentifiers: Set<String>
    /// 最低系统版本; 低于该版本时适配器不会被创建, 也不会注册任何监听
    let minimumSystemVersion: OperatingSystemVersion
}

/// 平滑帧的输出端。全部方法在 ScrollDispatchContext 的投递队列上串行调用
protocol ScrollOutputSink: AnyObject {
    /// 一帧平滑位移 (像素, 已含翻转与速度)
    func frame(y: Double, x: Double, at location: CGPoint)
    /// 平滑会话结束、刹停或复位; 没有进行中的手势时应为空操作
    func end(at location: CGPoint)
    /// 未平滑的轴原样放行前调用, 用于同步目标应用额外读取的字段。在 tap 回调线程调用
    func preparePassthrough(_ event: CGEvent, reversedY: Bool, reversedX: Bool, clearedY: Bool, clearedX: Bool)
}

extension ScrollOutputSink {
    func preparePassthrough(_ event: CGEvent, reversedY: Bool, reversedX: Bool, clearedY: Bool, clearedX: Bool) {}
}

/// 一次 HID 层接管的路由信息
struct ScrollAdapterRoute {
    /// 用于查找例外应用设置的目标应用
    let application: NSRunningApplication
    let sink: ScrollOutputSink
}

/// 应用滚动适配器。生命周期方法与命中测试均在主线程调用
protocol ScrollAdapter: AnyObject {
    var descriptor: ScrollAdapterDescriptor { get }
    /// 目标应用启动, 或 Mos 启用滚动时目标应用已在运行
    func activate(_ application: NSRunningApplication)
    /// 目标应用退出, 或 Mos 停用滚动
    func deactivate()
    /// 激活期间的低频刷新 (见 ScrollAdapterCenter.refreshInterval), 用于更新窗口矩形等缓存
    func refresh()
    /// 位于 HID 捕获热路径: 只读缓存, 返回 nil 表示放行该位置的事件
    func route(at location: CGPoint) -> ScrollAdapterRoute?
}

/// 适配器注册项。ScrollAdapterCenter 只在系统版本满足 minimumSystemVersion 时调用 make;
/// 使用了更高版本 API 的类型仍需在调用点加 #available 以满足编译期检查
struct ScrollAdapterRegistration {
    let descriptor: ScrollAdapterDescriptor
    let make: () -> ScrollAdapter?

    func isSupported(on version: OperatingSystemVersion) -> Bool {
        let minimum = descriptor.minimumSystemVersion
        return (version.majorVersion, version.minorVersion, version.patchVersion)
            >= (minimum.majorVersion, minimum.minorVersion, minimum.patchVersion)
    }
}
