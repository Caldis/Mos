import XCTest
@testable import Mos_Debug

final class OptionsButtonsLoaderTests: XCTestCase {

    private func makeBinding() -> ButtonBinding {
        let trigger = RecordedEvent(
            type: .mouse,
            code: 3,
            modifiers: 0,
            displayComponents: ["Mouse 4"],
            deviceFilter: nil
        )
        return ButtonBinding(triggerEvent: trigger, systemShortcutName: "copy", isEnabled: true)
    }

    private func makeBindingJSON(
        id: String = "11111111-1111-1111-1111-111111111111",
        systemShortcutName: String = "copy",
        extraField: String? = nil
    ) -> String {
        var fields = """
        "id": "\(id)",
        "triggerEvent": {
            "type": "mouse",
            "code": 3,
            "modifiers": 0,
            "displayComponents": ["🖱4"],
            "deviceFilter": null
        },
        "systemShortcutName": "\(systemShortcutName)",
        "isEnabled": true,
        "createdAt": 0
        """
        if let extra = extraField {
            fields += ",\n\(extra)"
        }
        return "{\(fields)}"
    }

    func testDecode_emptyArray_returnsEmpty() {
        let data = "[]".data(using: .utf8)!
        XCTAssertEqual(Options.decodeButtonBindings(from: data).count, 0)
    }

    func testDecode_singleValidBinding_decodesIt() {
        let json = "[\(makeBindingJSON())]"
        let data = json.data(using: .utf8)!
        let bindings = Options.decodeButtonBindings(from: data)
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings.first?.systemShortcutName, "copy")
    }

    func testDecode_legacyDisplayComponentsUseCurrentPresentation() {
        let json = "[\(makeBindingJSON())]"
        let data = json.data(using: .utf8)!
        let bindings = Options.decodeButtonBindings(from: data)

        XCTAssertEqual(bindings.first?.triggerEvent.displayComponents, ["🖱️ Back Button"])
    }

    func testDecode_corruptOuterArray_returnsEmpty() {
        // Not a JSON array at all
        let data = "{\"not\":\"array\"}".data(using: .utf8)!
        XCTAssertEqual(Options.decodeButtonBindings(from: data).count, 0)
    }

    func testDecode_oneValidOneCorrupt_keepsValid() {
        let valid = makeBindingJSON(id: "11111111-1111-1111-1111-111111111111")
        let corrupt = """
        {"id": "22222222-2222-2222-2222-222222222222", "missing_required_fields": true}
        """
        let json = "[\(valid),\(corrupt)]"
        let data = json.data(using: .utf8)!
        let bindings = Options.decodeButtonBindings(from: data)
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings.first?.id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    }

    func testDecode_unknownExtraField_stillDecodesAndIgnores() {
        // Future Mos version added a new field; current Mos must ignore it.
        let json = "[\(makeBindingJSON(extraField: "\"futurePayloadKind\": {\"type\":\"runCommand\"}"))]"
        let data = json.data(using: .utf8)!
        let bindings = Options.decodeButtonBindings(from: data)
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings.first?.systemShortcutName, "copy")
    }

    func testDecode_multipleCorruptInArray_keepsAllValid() {
        let valid1 = makeBindingJSON(id: "11111111-1111-1111-1111-111111111111", systemShortcutName: "copy")
        let valid2 = makeBindingJSON(id: "33333333-3333-3333-3333-333333333333", systemShortcutName: "paste")
        let corrupt1 = "{\"garbage\": true}"
        let corrupt2 = "null"
        let json = "[\(corrupt1),\(valid1),\(corrupt2),\(valid2)]"
        let data = json.data(using: .utf8)!
        let bindings = Options.decodeButtonBindings(from: data)
        XCTAssertEqual(bindings.count, 2)
        XCTAssertEqual(bindings.map { $0.systemShortcutName }.sorted(), ["copy", "paste"])
    }

    // MARK: - Unknown preservation

    func testDecodeWithUnknowns_preservesFutureFormatBindings() {
        // 模拟未来版本写入了一种当前 Mos 不认识的 binding (e.g. systemShortcutName 是
        // 某个新的 sentinel, 字段集与当前不兼容). 当前 Mos 应当保留原 JSON 在 unknownElements
        // 里, 不丢失.
        let valid = makeBindingJSON()
        let futureFormat = """
        {"id": "44444444-4444-4444-4444-444444444444",
         "futurePayload": {"type": "runShellCommand", "command": "echo hi"},
         "isEnabled": true}
        """
        let data = "[\(valid),\(futureFormat)]".data(using: .utf8)!
        let result = Options.decodeButtonBindingsWithUnknowns(from: data)
        XCTAssertEqual(result.bindings.count, 1)
        XCTAssertEqual(result.unknownElements.count, 1)
    }

    func testDecodeWithUnknowns_emptyArray_returnsBothEmpty() {
        let result = Options.decodeButtonBindingsWithUnknowns(from: "[]".data(using: .utf8)!)
        XCTAssertTrue(result.bindings.isEmpty)
        XCTAssertTrue(result.unknownElements.isEmpty)
    }

    /// Round-trip 验证: decode 之后再 encode + decode, unknown 元素必须保持完整 + 顺序在末尾.
    /// 这是 fix 3 的核心承诺 (用户升级到未来版本写入新 binding, 然后降级到当前版本,
    /// 当前版本不删除/不损坏新数据), 必须有直接覆盖.
    func testDecodeWithUnknowns_roundTripPreservesUnknowns() {
        let knownValid = makeBindingJSON(id: "11111111-1111-1111-1111-111111111111", systemShortcutName: "copy")
        let futureUnknown = """
        {"id":"99999999-9999-9999-9999-999999999999",
         "triggerEvent":{"type":"mouse","code":7,"modifiers":0,"displayComponents":["🖱8"],"deviceFilter":null},
         "systemShortcutName":"runShellCommand",
         "isEnabled":true,
         "createdAt":"2030-01-01T00:00:00Z",
         "shellPayload":{"command":"echo hi"}}
        """
        let originalJSON = "[\(knownValid),\(futureUnknown)]"
        let originalData = originalJSON.data(using: .utf8)!

        // 解 + 收 unknown
        let result1 = Options.decodeButtonBindingsWithUnknowns(from: originalData)
        XCTAssertEqual(result1.bindings.count, 1)
        XCTAssertEqual(result1.unknownElements.count, 1)

        // 重新拼回 (模拟 saveButtonBindingsData 的合并逻辑)
        let knownData = try! JSONEncoder().encode(result1.bindings)
        var merged = try! JSONSerialization.jsonObject(with: knownData) as! [Any]
        merged.append(contentsOf: result1.unknownElements)
        let mergedData = try! JSONSerialization.data(withJSONObject: merged)

        // 再解一次, unknown 还在
        let result2 = Options.decodeButtonBindingsWithUnknowns(from: mergedData)
        XCTAssertEqual(result2.bindings.count, 1)
        XCTAssertEqual(result2.bindings.first?.systemShortcutName, "copy")
        XCTAssertEqual(result2.unknownElements.count, 1, "未来版本 binding 必须 round-trip 保持")
    }

    // MARK: - Test isolation

    func testSaveOptionsDoesNotPersistButtonBindingsWhileRunningTests() {
        let defaults = UserDefaults.standard
        let key = OptionItem.Button.Bindings
        let originalValue = defaults.object(forKey: key)
        let sentinel = "test-sentinel".data(using: .utf8)!
        let originalBindings = Options.shared.buttons

        defaults.set(sentinel, forKey: key)
        defer {
            Options.shared.buttons = originalBindings
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        Options.shared.buttons.binding = [makeBinding()]

        XCTAssertEqual(defaults.data(forKey: key), sentinel)
    }

    func testAppRuntimeDetectsXCTestEnvironment() {
        XCTAssertTrue(AppRuntime.isRunningXCTest(environment: [
            "XCTestConfigurationFilePath": "/tmp/MosTests.xctestconfiguration"
        ]))
        XCTAssertTrue(AppRuntime.isRunningXCTest(environment: [
            "XCTestBundlePath": "/tmp/MosTests.xctest"
        ]))
        XCTAssertFalse(AppRuntime.isRunningXCTest(environment: [:]))
    }

    func testAppRuntimeSkipsStartupSideEffectsDuringTestsUnlessExplicitlyEnabled() {
        let testEnvironment = [
            "XCTestConfigurationFilePath": "/tmp/MosTests.xctestconfiguration"
        ]
        XCTAssertFalse(AppRuntime.shouldRunAppStartupSideEffects(environment: testEnvironment))
        XCTAssertTrue(AppRuntime.shouldRunAppStartupSideEffects(environment: [
            "XCTestConfigurationFilePath": "/tmp/MosTests.xctestconfiguration",
            "MOS_TEST_ENABLE_APP_STARTUP": "1"
        ]))
        XCTAssertTrue(AppRuntime.shouldRunAppStartupSideEffects(environment: [:]))
    }
}
