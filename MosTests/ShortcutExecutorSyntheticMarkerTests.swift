import XCTest
@testable import Mos_Debug

final class ShortcutExecutorSyntheticMarkerTests: XCTestCase {

    override func tearDown() {
        ShortcutExecutor.shared.clearTestingKeyEventObserver()
        super.tearDown()
    }

    // P0-9 回归: execute(code:flags:) 的合成键盘事件必须带 syntheticCustom 标记,
    // 防止事件回流进 ButtonCore/InputProcessor 被再次匹配造成二次触发
    func testExecuteCodeFlagsMarksSyntheticEvents() {
        var observed: [(type: CGEventType, userData: Int64)] = []
        ShortcutExecutor.shared.setTestingKeyEventObserver { event in
            observed.append((event.type, event.getIntegerValueField(.eventSourceUserData)))
        }

        ShortcutExecutor.shared.execute(code: 126, flags: CGEventFlags.maskCommand.rawValue)

        XCTAssertEqual(observed.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(
            observed.map(\.userData),
            [MosEventMarker.syntheticCustom, MosEventMarker.syntheticCustom],
            "keyDown/keyUp 都应带合成标记"
        )
    }
}
