import XCTest
@testable import Mos_Debug

final class KeyRecorderTapPassthroughTests: XCTestCase {

    private func makeKeyEvent(keyDown: Bool = true, virtualKey: CGKeyCode = 6) -> CGEvent? {
        CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: keyDown)
    }

    // P0-8 回归: 带合成标记的事件必须被放行 (返回非 nil)
    // 录制 tap 是 defaultTap, 吞掉合成的 flagsChanged 会让系统修饰键状态卡死
    func testSyntheticEventPassesThrough() {
        guard let event = makeKeyEvent() else {
            XCTFail("无法创建 CGEvent")
            return
        }
        event.type = .flagsChanged
        event.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
        let result = KeyRecorder.handleRecordingTapEvent(type: .flagsChanged, event: event)
        XCTAssertNotNil(result, "合成事件应被放行而非吞掉")
    }

    // 真实输入仍被吞掉 (录制期间按键不应传给目标应用)
    func testRealKeyDownIsSwallowed() {
        guard let event = makeKeyEvent() else {
            XCTFail("无法创建 CGEvent")
            return
        }
        let result = KeyRecorder.handleRecordingTapEvent(type: .keyDown, event: event)
        XCTAssertNil(result, "被录制的真实按键应被吞掉")
    }

    func testRealFlagsChangedIsSwallowed() {
        guard let event = makeKeyEvent() else {
            XCTFail("无法创建 CGEvent")
            return
        }
        event.type = .flagsChanged
        let result = KeyRecorder.handleRecordingTapEvent(type: .flagsChanged, event: event)
        XCTAssertNil(result, "被录制的真实修饰键变化应被吞掉")
    }
}
