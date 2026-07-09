import XCTest
@testable import Mos_Debug

/// Scroll Force / Ratchet Torque (0x2111 SmartShift Enhanced) 协议解析与参数编码的纯函数测试.
/// 字节布局对齐 Solaar ScrollRatchetTorque: fn0 payload[0] bit0 = 可调 torque,
/// fn1 payload = [mode, autoDisengage, torque], SetState 参数 = [mode, 0x00, torque].
final class LogiScrollForceTests: XCTestCase {

    // MARK: - GetCapabilities (fn0) 可调 torque 位

    func testParseTunableTorque_bitZeroSet() {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11; report[1] = 0xFF; report[2] = 0x22; report[3] = 0x01
        report[4] = 0x01  // bit0 = 1
        XCTAssertEqual(LogiDeviceSession.parseScrollForceTunableTorqueForTests(report), true)
    }

    func testParseTunableTorque_onlyBitZeroMatters() {
        var report = [UInt8](repeating: 0, count: 20)
        report[4] = 0xFE  // bit0 = 0, 高位置位不应误判为支持
        XCTAssertEqual(LogiDeviceSession.parseScrollForceTunableTorqueForTests(report), false)
    }

    func testParseTunableTorque_shortReportReturnsNil() {
        XCTAssertNil(LogiDeviceSession.parseScrollForceTunableTorqueForTests([0x11, 0xFF, 0x22, 0x01]))
    }

    // MARK: - GetStatus (fn1) 解析

    func testParseStatus_modeAndTorque() {
        // payload = [mode=2(ratchet), autoDisengage=15, torque=72]
        var report = [UInt8](repeating: 0, count: 20)
        report[4] = 0x02; report[5] = 15; report[6] = 72
        XCTAssertEqual(
            LogiDeviceSession.parseScrollForceStatusForTests(report),
            LogiDeviceSession.ScrollForceStatus(mode: 2, torque: 72)
        )
    }

    func testParseStatus_skipsAutoDisengageByte() {
        // byte[5] (autoDisengage 阈值) 不得混入 torque
        var report = [UInt8](repeating: 0, count: 20)
        report[4] = 0x01; report[5] = 0xFF; report[6] = 30
        XCTAssertEqual(
            LogiDeviceSession.parseScrollForceStatusForTests(report),
            LogiDeviceSession.ScrollForceStatus(mode: 1, torque: 30)
        )
    }

    func testParseStatus_shortReportReturnsNil() {
        XCTAssertNil(LogiDeviceSession.parseScrollForceStatusForTests([0x11, 0xFF, 0x22, 0x11, 0x02, 0x0F]))
    }

    // MARK: - SetState (fn2) 参数编码

    func testSetTorqueParams_dontChangeModeWhenUnknown() {
        // mode=0 表示不改变 wheel mode / autoDisengage, 仅写 torque
        XCTAssertEqual(LogiDeviceSession.scrollForceSetTorqueParamsForTests(torque: 60, mode: 0), [0x00, 0x00, 60])
    }

    func testSetTorqueParams_carriesModeForMXMaster4() {
        // MX Master 4 需带回当前 mode 才生效
        XCTAssertEqual(LogiDeviceSession.scrollForceSetTorqueParamsForTests(torque: 88, mode: 2), [0x02, 0x00, 88])
    }

    func testSetTorqueParams_clampsToOneHundred() {
        XCTAssertEqual(LogiDeviceSession.scrollForceSetTorqueParamsForTests(torque: 255, mode: 0), [0x00, 0x00, 100])
    }

    func testSetTorqueParams_clampsUpToOne() {
        // torque 下界为 1 (0 会被 Options+ 当作 freespin 语义, 此处力度最小档为 1)
        XCTAssertEqual(LogiDeviceSession.scrollForceSetTorqueParamsForTests(torque: 0, mode: 0), [0x00, 0x00, 1])
    }

    // MARK: - Feature 目录

    func testFeatureDirectory_containsSmartShiftEnhanced() {
        XCTAssertEqual(HIDPPInfo.featureNames[LogiDeviceSession.featureSmartShiftEnhanced]?.0, "SmartShiftV2")
    }
}
