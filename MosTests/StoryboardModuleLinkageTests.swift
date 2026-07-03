import XCTest
import DGCharts
@testable import Mos_Debug

/// Storyboard ↔ 依赖模块链接金丝雀。
///
/// 为什么普通单测覆盖不到: storyboard 里的 customModule 是运行时才解析的字符串,
/// 编译期与 ibtool 都不校验它与依赖真实模块名的一致性; 依赖改名 (Charts→DGCharts)
/// 后类解析静默回落为 NSView, 只有真正打开窗口、以 Swift 字段偏移访问属性时才
/// EXC_BAD_ACCESS。本测试在不显示窗口的前提下实例化场景并断言 outlet 的真实类型,
/// 把这类断裂拦在 CI。
final class StoryboardModuleLinkageTests: XCTestCase {

    func testMonitorChartOutletResolvesToDGChartsClass() {
        let storyboard = NSStoryboard(name: "Main", bundle: Bundle.main)
        guard let windowController = storyboard.instantiateController(
            withIdentifier: WINDOW_IDENTIFIER.monitorWindowController
        ) as? NSWindowController else {
            return XCTFail("无法实例化 monitorWindowController")
        }
        guard let monitorVC = windowController.window?.contentViewController as? MonitorViewController else {
            return XCTFail("contentViewController 不是 MonitorViewController")
        }
        // 触发 outlet 连接; 窗口不 makeKeyAndOrderFront, 不会走 viewWillAppear/initCharts
        _ = monitorVC.view

        let chart = monitorVC.value(forKey: "lineChart") as AnyObject?
        XCTAssertNotNil(chart, "lineChart outlet 未连接")
        XCTAssertTrue(
            chart is LineChartView,
            "lineChart 解码为 \(chart.map { String(describing: type(of: $0)) } ?? "nil") — " +
            "storyboard 的 customModule 与图表依赖的实际模块名不一致 (类解析回落 NSView 会导致打开窗口即崩)"
        )
    }
}
