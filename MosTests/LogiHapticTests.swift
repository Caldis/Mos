import XCTest
@testable import Mos_Debug

/// HAPTIC (0x19B0) 协议解析与参数编码的纯函数测试.
/// 字节布局对齐 Solaar: fn0 payload[4..7] 为波形位掩码, fn1 payload[0..2] 为状态三元组.
final class LogiHapticTests: XCTestCase {

    // MARK: - GetCapabilities (fn0) 位掩码解析

    func testParseCapabilitiesMask_bigEndianAssembly() {
        // 20 字节长报文, bytes[8..11] = 0x08 00 7F FF
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11; report[1] = 0xFF; report[2] = 0x21; report[3] = 0x01
        report[8] = 0x08; report[9] = 0x00; report[10] = 0x7F; report[11] = 0xFF
        XCTAssertEqual(LogiDeviceSession.parseHapticCapabilitiesMaskForTests(report), 0x0800_7FFF)
    }

    func testParseCapabilitiesMask_shortReportReturnsNil() {
        XCTAssertNil(LogiDeviceSession.parseHapticCapabilitiesMaskForTests([0x11, 0xFF, 0x21, 0x01, 0, 0, 0]))
    }

    func testWaveformMaskFiltering_includesSparseHighBit() {
        // 典型掩码: bit 0..14 (0x00~0x0E) + bit 27 (Whisper Collision 0x1B) = 全部 16 个已知波形
        let mask: UInt32 = 0x0800_7FFF
        let supported = HIDPPInfo.hapticWaveforms.filter { (mask >> UInt32($0.id)) & 1 != 0 }
        XCTAssertEqual(supported.count, HIDPPInfo.hapticWaveforms.count)
        XCTAssertTrue(supported.contains { $0.id == 0x1B })
    }

    func testWaveformMaskFiltering_partialMask() {
        // 只支持 bit 0 和 bit 5 (Sharp State Change + Happy Alert)
        let mask: UInt32 = (1 << 0) | (1 << 5)
        let supported = HIDPPInfo.hapticWaveforms.filter { (mask >> UInt32($0.id)) & 1 != 0 }
        XCTAssertEqual(supported.map { $0.id }, [0x00, 0x05])
    }

    // MARK: - GetState (fn1) 解析

    func testParseState_enabledLevelAndFourLevelFlag() {
        var report = [UInt8](repeating: 0, count: 20)
        report[4] = 0x01; report[5] = 80; report[6] = 0x01
        XCTAssertEqual(
            LogiDeviceSession.parseHapticStateForTests(report),
            LogiDeviceSession.HapticState(enabled: true, level: 80, fourLevelsOnly: true)
        )
    }

    func testParseState_flagsOnlyReadBitZero() {
        var report = [UInt8](repeating: 0, count: 20)
        report[4] = 0xFE  // bit0 = 0, 高位不应影响
        report[5] = 50
        report[6] = 0xFE  // bit0 = 0
        XCTAssertEqual(
            LogiDeviceSession.parseHapticStateForTests(report),
            LogiDeviceSession.HapticState(enabled: false, level: 50, fourLevelsOnly: false)
        )
    }

    func testParseState_shortReportReturnsNil() {
        XCTAssertNil(LogiDeviceSession.parseHapticStateForTests([0x11, 0xFF, 0x21]))
    }

    // MARK: - SetState (fn2) 参数编码

    func testSetLevelParams_zeroMapsToDisableAtHalfPower() {
        // Solaar 约定: 关闭时写 [disable, 50%], 保留合理的重开默认值
        XCTAssertEqual(LogiDeviceSession.hapticSetLevelParamsForTests(0), [0x00, 0x32])
    }

    func testSetLevelParams_normalLevelEnables() {
        XCTAssertEqual(LogiDeviceSession.hapticSetLevelParamsForTests(80), [0x01, 80])
    }

    func testSetLevelParams_clampsAboveHundred() {
        XCTAssertEqual(LogiDeviceSession.hapticSetLevelParamsForTests(255), [0x01, 100])
    }

    // MARK: - 波形字典完整性

    func testWaveformTable_idsUniqueAndWithinKnownRange() {
        let ids = HIDPPInfo.hapticWaveforms.map { $0.id }
        XCTAssertEqual(ids.count, 16)
        XCTAssertEqual(Set(ids).count, ids.count, "waveform ID 不允许重复")
        XCTAssertTrue(ids.allSatisfy { $0 <= 0x1B }, "已知波形 ID 上界为 0x1B")
    }

    func testFeatureDirectory_containsHaptic() {
        XCTAssertEqual(HIDPPInfo.featureNames[LogiDeviceSession.featureHaptic]?.0, "Haptic")
    }
}
