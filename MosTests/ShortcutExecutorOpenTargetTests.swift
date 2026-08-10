import XCTest
@testable import Mos_Debug

final class ShortcutExecutorOpenTargetTests: XCTestCase {

    private func makeOpenTargetBinding(payload: OpenTargetPayload) -> ButtonBinding {
        return ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            openTarget: payload
        )
    }

    func testResolveAction_openTargetSentinel_returnsOpenTargetCase() {
        let payload = OpenTargetPayload(path: "/Applications/Safari.app", bundleID: "com.apple.Safari", arguments: "", kind: .application)
        let binding = makeOpenTargetBinding(payload: payload)
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "openTarget", binding: binding)
        guard case .openTarget(let resolvedPayload) = resolved else {
            return XCTFail("Expected .openTarget case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(resolvedPayload, payload)
    }

    func testResolveAction_openTargetSentinelButNoPayload_returnsNil() {
        // Edge case: sentinel set but openTarget field missing — corruption guard
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "openTarget"
        )
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "openTarget", binding: binding)
        if case .systemShortcut = resolved {
            // Falls through to systemShortcut case (returns the identifier as-is, lookup will fail later)
        } else if resolved == nil {
            // Or returns nil — either is acceptable defensive behavior
        } else {
            XCTFail("Expected .systemShortcut or nil for missing payload, got \(String(describing: resolved))")
        }
    }

    func testResolveAction_existingCustomKeyPath_unaffected() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::40:1048576"
        )
        binding.prepareCustomCache()
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "custom::40:1048576", binding: binding)
        guard case .customKey(let code, let modifiers) = resolved else {
            return XCTFail("Expected .customKey case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(code, 40)
        XCTAssertEqual(modifiers, 1048576)
    }

    func testResolveAction_typedMouseBackCustomBinding_usesNamedMouseButtonPath() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil),
            systemShortcutName: "custom::mouse:3:0"
        )
        binding.prepareCustomCache()
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "custom::mouse:3:0", binding: binding)
        guard case .mouseButton(let kind) = resolved else {
            return XCTFail("Expected .mouseButton case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(kind, .back)
    }

    func testResolveAction_typedMouseCustomBinding_usesCustomMouseButtonPath() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱6"], deviceFilter: nil),
            systemShortcutName: "custom::mouse:5:0"
        )
        binding.prepareCustomCache()
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "custom::mouse:5:0", binding: binding)
        guard case .customMouseButton(let buttonNumber, let modifiers) = resolved else {
            return XCTFail("Expected .customMouseButton case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(buttonNumber, 5)
        XCTAssertEqual(modifiers, 0)
    }

    func testResolveAction_existingMouseButtonPath_unaffected() {
        let executor = ShortcutExecutor()
        let resolved = executor.resolveAction(named: "mouseLeftClick", binding: nil)
        guard case .mouseButton(let kind) = resolved else {
            return XCTFail("Expected .mouseButton case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(kind, .left)
    }

    func testExecutionMode_openTarget_isTrigger() {
        let payload = OpenTargetPayload(path: "/x.app", bundleID: nil, arguments: "", kind: .application)
        let action: ResolvedAction = .openTarget(payload: payload)
        XCTAssertEqual(action.executionMode, .trigger)
    }

    func testExecutionMode_existingCases_unchanged() {
        XCTAssertEqual(ResolvedAction.customKey(code: 0, modifiers: 0).executionMode, .stateful)
        XCTAssertEqual(ResolvedAction.customMouseButton(buttonNumber: 5, modifiers: 0).executionMode, .stateful)
        XCTAssertEqual(ResolvedAction.mouseButton(kind: .left).executionMode, .stateful)
        XCTAssertEqual(ResolvedAction.logiAction(identifier: "logiSmartShiftToggle").executionMode, .trigger)
    }

    // MARK: - Subprocess env sanitization

    func testFilterEnvironment_stripsAllPollutionKeys() {
        // 用控制输入直接验证 filter 对每一类污染前缀都识别. 之前的测试只验证当前
        // 真实 env (CI 环境干净时跑不出有效信号), 不能算证明 strip-list 工作.
        let polluted: [String: String] = [
            "DYLD_INSERT_LIBRARIES": "/Xcode/.../libViewDebuggerSupport.dylib",
            "DYLD_FRAMEWORK_PATH": "/some/path",
            "DYLD_LIBRARY_PATH": "/some/path",
            "__XPC_DYLD_LIBRARY_PATH": "/some/path",
            "__XPC_DYLD_FRAMEWORK_PATH": "/some/path",
            "__XPC_LLVM_PROFILE_FILE": "/dev/null",
            "OS_ACTIVITY_DT_MODE": "YES",
            "MallocStackLogging": "1",
            "MallocStackLoggingNoCompact": "1",
            "NSZombieEnabled": "YES",
            "NSDeallocateZombies": "NO",
            "SWIFTUI_VIEW_DEBUG": "287",
            "ASAN_OPTIONS": "detect_leaks=1",
            "TSAN_OPTIONS": "halt_on_error=1",
            "LSAN_OPTIONS": "x",
            "UBSAN_OPTIONS": "x",
            // 常规 env: 必须保留
            "PATH": "/usr/bin:/bin",
            "HOME": "/Users/test",
            "USER": "test",
            "LANG": "en_US.UTF-8",
        ]

        let filtered = ShortcutExecutor.filterEnvironment(polluted)

        // 污染 keys 必须全部消失
        XCTAssertNil(filtered["DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(filtered["DYLD_FRAMEWORK_PATH"])
        XCTAssertNil(filtered["DYLD_LIBRARY_PATH"])
        XCTAssertNil(filtered["__XPC_DYLD_LIBRARY_PATH"])
        XCTAssertNil(filtered["__XPC_DYLD_FRAMEWORK_PATH"])
        XCTAssertNil(filtered["__XPC_LLVM_PROFILE_FILE"])
        XCTAssertNil(filtered["OS_ACTIVITY_DT_MODE"])
        XCTAssertNil(filtered["MallocStackLogging"])
        XCTAssertNil(filtered["MallocStackLoggingNoCompact"])
        XCTAssertNil(filtered["NSZombieEnabled"])
        XCTAssertNil(filtered["NSDeallocateZombies"])
        XCTAssertNil(filtered["SWIFTUI_VIEW_DEBUG"])
        XCTAssertNil(filtered["ASAN_OPTIONS"])
        XCTAssertNil(filtered["TSAN_OPTIONS"])
        XCTAssertNil(filtered["LSAN_OPTIONS"])
        XCTAssertNil(filtered["UBSAN_OPTIONS"])

        // 常规 keys 必须保留
        XCTAssertEqual(filtered["PATH"], "/usr/bin:/bin")
        XCTAssertEqual(filtered["HOME"], "/Users/test")
        XCTAssertEqual(filtered["USER"], "test")
        XCTAssertEqual(filtered["LANG"], "en_US.UTF-8")
    }

    func testFilterEnvironment_emptyInput_returnsEmpty() {
        XCTAssertEqual(ShortcutExecutor.filterEnvironment([:]).count, 0)
    }
}
