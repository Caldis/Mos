import XCTest
@testable import Mos_Debug

/// P5-6 — LogiSessionEnvironment 组装与路由.
/// Session 的全部上行能力经协议注入; 此处验证生产 adapter 的每条路由
/// 与原单例调用逐一等价, 以及组合根 (LogiCenter) 的接线时序.
final class LogiSessionEnvironmentTests: XCTestCase {

    private func makeHarness(
        bridge: LogiExternalBridge = FakeLogiExternalBridge()
    ) -> (center: LogiCenter, manager: LogiSessionManager, registry: UsageRegistry) {
        let manager = LogiSessionManager()
        let registry = UsageRegistry(sessionProvider: { [] })
        let center = LogiCenter(manager: manager, registry: registry, bridge: bridge)
        return (center, manager, registry)
    }

    private var sampleKey: LogiOwnershipKey {
        LogiOwnershipKey(
            vendorId: 0x046D, productId: 0xB034, name: "MX Master 4",
            transport: .bleDirect, cid: 0x00C3
        )
    }

    // MARK: - 接线

    func test_harnessInit_wiresEnvironmentOntoManager() {
        let (center, manager, _) = makeHarness()
        XCTAssertNotNil(manager.sessionEnvironment)
        _ = center  // keep alive
    }

    func test_sharedCenter_wiresSharedManager() {
        _ = LogiCenter.shared
        XCTAssertNotNil(LogiSessionManager.shared.sessionEnvironment)
    }

    // MARK: - Registry 路由

    func test_bindingsExist_tracksRegistryAggregate() throws {
        let (center, manager, registry) = makeHarness()
        let environment = try XCTUnwrap(manager.sessionEnvironment)

        XCTAssertFalse(environment.bindingsExist)
        registry.setUsage(source: .buttonBinding, codes: [1006])
        XCTAssertTrue(environment.bindingsExist)
        registry.setUsage(source: .buttonBinding, codes: [])
        XCTAssertFalse(environment.bindingsExist)
        _ = center
    }

    // MARK: - Bridge 路由 (必须读现值: installBridge 可热替换)

    func test_bridgeCalls_routeToCurrentlyInstalledBridge() throws {
        let initialBridge = FakeLogiExternalBridge()
        let (center, manager, _) = makeHarness(bridge: initialBridge)
        let environment = try XCTUnwrap(manager.sessionEnvironment)

        environment.showToast("hello", severity: .warning)
        XCTAssertEqual(initialBridge.calls.count, 1)

        // 热替换后, 后续调用必须落到新 bridge 而非 init 时的快照
        let replacedBridge = FakeLogiExternalBridge()
        center.installBridge(replacedBridge)

        let event = InputEvent(
            type: .mouse, code: 1006, modifiers: [],
            phase: .down, source: .hidPP, device: nil
        )
        _ = environment.dispatchButtonEvent(event)
        environment.handleScrollHotkey(code: 1006, phase: .up)

        XCTAssertEqual(initialBridge.calls.count, 1, "替换后不得再落到旧 bridge")
        XCTAssertEqual(replacedBridge.calls.count, 2)
        if case .dispatch(let recorded) = replacedBridge.calls[0] {
            XCTAssertEqual(recorded.code, 1006)
        } else {
            XCTFail("first call should be dispatch, got \(replacedBridge.calls[0])")
        }
        if case .scrollHotkey(let code, let phase) = replacedBridge.calls[1] {
            XCTAssertEqual(code, 1006)
            XCTAssertEqual(phase, .up)
        } else {
            XCTFail("second call should be scrollHotkey, got \(replacedBridge.calls[1])")
        }
    }

    // MARK: - Manager 路由

    func test_isRecording_followsManagerRecordingState() throws {
        let (center, manager, _) = makeHarness()
        let environment = try XCTUnwrap(manager.sessionEnvironment)

        XCTAssertFalse(environment.isRecording)
        manager.temporarilyDivertAll()
        XCTAssertTrue(environment.isRecording)
        manager.restoreDivertToBindings()
        XCTAssertFalse(environment.isRecording)
        _ = center
    }

    func test_deliveryMode_andRecordExternalClear_routeToManagerStore() throws {
        let (center, manager, _) = makeHarness()
        let environment = try XCTUnwrap(manager.sessionEnvironment)
        let key = sampleKey

        XCTAssertEqual(environment.deliveryMode(for: key), manager.deliveryMode(for: key))

        let evolved = environment.recordExternalClear(for: key)
        XCTAssertEqual(evolved, manager.deliveryMode(for: key),
                       "adapter 返回值必须与 manager store 演进后的状态一致")
        XCTAssertEqual(environment.deliveryMode(for: key), manager.deliveryMode(for: key))
        _ = center
    }
}
