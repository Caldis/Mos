import XCTest
@testable import Mos_Debug

final class LogiUsageBootstrapTests: XCTestCase {

    /// Smoke: refreshAll runs without crashing and reads Options without trapping.
    /// Cannot deterministically assert registry content because Options.shared has live state.
    func testRefreshAll_runsWithoutCrash() {
        LogiUsageBootstrap.refreshAll()
        XCTAssertNotNil(LogiCenter.shared)
    }

    /// app 从列表移除后, refreshAll 应推送空集清理其 appScroll 用量 (防注册表残留)
    func testRefreshAllClearsUsageForRemovedApp() {
        let key = "/tmp/MosUsageBootstrapTest.app"
        let code: UInt16 = 1006  // Logi Back 的 MosCode (与 LogiCenterDeviceIntegrationTests 一致)
        let app = Application(path: key)
        app.inherit = false
        app.scroll.dash = ScrollHotkey(type: .mouse, code: code)
        Options.shared.application.applications.append(app)
        defer {
            if Options.shared.application.applications.get(by: key) != nil {
                Options.shared.application.applications.remove(from: key)
            }
            LogiUsageBootstrap.refreshAll()
        }

        LogiUsageBootstrap.refreshAll()
        XCTAssertTrue(LogiCenter.shared.usages(of: code).contains(.appScroll(key: key, role: .dash)),
                      "注册后应能查询到 appScroll 用量")

        Options.shared.application.applications.remove(from: key)
        LogiUsageBootstrap.refreshAll()
        XCTAssertFalse(LogiCenter.shared.usages(of: code).contains(.appScroll(key: key, role: .dash)),
                       "app 移除后用量应被清理")
    }
}
