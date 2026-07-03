import XCTest
@testable import Mos_Debug

final class UtilsParseNameTests: XCTestCase {

    // P0-3 回归: 显示名含无效百分号序列时不崩溃, 保留原名
    func testInvalidPercentSequenceDoesNotCrash() {
        let name = Utils.parseName(fromPath: "/nonexistent/100% Orange Juice.app")
        XCTAssertEqual(name, "100% Orange Juice")
    }

    // 合法百分号编码仍被解码 (保持既有行为)
    func testValidPercentEncodingStillDecoded() {
        let name = Utils.parseName(fromPath: "/nonexistent/Test%20App.app")
        XCTAssertEqual(name, "Test App")
    }

    func testPlainNameStripsAppSuffix() {
        let name = Utils.parseName(fromPath: "/nonexistent/PlainApp.app")
        XCTAssertEqual(name, "PlainApp")
    }

    // 名字中含 "<字符>app" 的应用不能被误截 (如 WhatsApp)
    func testNameContainingAppSubstringIsNotMangled() {
        let name = Utils.parseName(fromPath: "/nonexistent/WhatsApp.app")
        XCTAssertEqual(name, "WhatsApp")
    }
}
