import XCTest
@testable import Mos_Debug

/// 验证 Logi divert 决策纯函数: 只触碰 Mos 自己关心的 CID (已绑定 或 曾 divert 但解绑),
/// 不碰 Options+ 等第三方可能 divert 的其它 CID.
final class LogiDivertPlannerTests: XCTestCase {

    // MARK: - Fixture CIDs (来自 LogiCIDDirectory)
    // 固定 MosCode: Left=0x0050→1003, Back=0x0053→1006, Forward=0x0056→1007, SmartShift=0x00C4→1001
    // 非固定 MosCode: G1=0x1001→3001 (2000+cid), 但 Logi 码 ≥1000 都视为 Logitech
    private let cidLeft: UInt16 = 0x0050
    private let codeLeft: UInt16 = 1003
    private let cidBack: UInt16 = 0x0053
    private let codeBack: UInt16 = 1006
    private let cidForward: UInt16 = 0x0056
    private let codeForward: UInt16 = 1007
    private let cidSmartShift: UInt16 = 0x00C4
    private let codeSmartShift: UInt16 = 1001
    private let cidG1: UInt16 = 0x1001
    private let codeG1: UInt16 = 0x1001 + 2000

    // MARK: - 基本契约

    func testPlan_emptyInput_returnsEmpty() {
        let plan = LogiDivertPlanner.plan(
            boundMosCodes: [],
            alreadyDiverted: [],
            divertableCIDs: []
        )
        XCTAssertTrue(plan.toDivert.isEmpty)
        XCTAssertTrue(plan.toUndivert.isEmpty)
    }

    func testPlan_newBinding_emitsDivert() {
        let plan = LogiDivertPlanner.plan(
            boundMosCodes: [codeBack],
            alreadyDiverted: [],
            divertableCIDs: [cidBack, cidForward, cidSmartShift]
        )
        XCTAssertEqual(plan.toDivert, [cidBack])
        XCTAssertTrue(plan.toUndivert.isEmpty)
    }

    func testPlan_boundAndAlreadyDiverted_isIdempotent() {
        let plan = LogiDivertPlanner.plan(
            boundMosCodes: [codeBack],
            alreadyDiverted: [cidBack],
            divertableCIDs: [cidBack, cidForward]
        )
        XCTAssertTrue(plan.toDivert.isEmpty)
        XCTAssertTrue(plan.toUndivert.isEmpty)
    }

    func testPlan_bindingRemoved_emitsUndivert() {
        let plan = LogiDivertPlanner.plan(
            boundMosCodes: [],
            alreadyDiverted: [cidBack],
            divertableCIDs: [cidBack, cidForward]
        )
        XCTAssertTrue(plan.toDivert.isEmpty)
        XCTAssertEqual(plan.toUndivert, [cidBack])
    }

    // MARK: - 核心: 与 Logitech Options+ 兼容

    /// 设备有很多可 divert 控件, 其中可能有些被 Options+ 设置为 divert,
    /// plan 应该只触碰 boundMosCodes 对应的 CID + alreadyDiverted 里不再 bound 的 CID,
    /// 绝不触碰其他 divertable CID (例如 Options+ 管理的按键).
    func testPlan_doesNotTouchThirdPartyDivertableCIDs() {
        let optionsPlusCIDs: Set<UInt16> = [cidLeft, cidSmartShift, cidG1] // 假设 Options+ 控制的按键
        let mosBound: Set<UInt16> = [codeBack]                              // Mos 只绑定 Back
        let mosPreviouslyDiverted: Set<UInt16> = [cidBack]

        let plan = LogiDivertPlanner.plan(
            boundMosCodes: mosBound,
            alreadyDiverted: mosPreviouslyDiverted,
            divertableCIDs: optionsPlusCIDs.union([cidBack, cidForward])
        )

        // 结果 CID 必须都在 Mos 关心的范围内 (bound CID 或 Mos 曾 divert 过的)
        let mosOwnedCIDs: Set<UInt16> = mosPreviouslyDiverted.union([cidBack]) // Back 同时 bound & 已 divert
        for cid in plan.toDivert {
            XCTAssertTrue(mosOwnedCIDs.contains(cid), "toDivert 触碰了非 Mos 关心的 CID 0x\(String(format: "%04X", cid))")
        }
        for cid in plan.toUndivert {
            XCTAssertTrue(mosOwnedCIDs.contains(cid), "toUndivert 触碰了非 Mos 关心的 CID 0x\(String(format: "%04X", cid))")
        }
        // 绝不触碰 Options+ 的按键
        for cid in optionsPlusCIDs {
            XCTAssertFalse(plan.toDivert.contains(cid))
            XCTAssertFalse(plan.toUndivert.contains(cid))
        }
    }

    // MARK: - 边界

    func testPlan_boundButNotDivertable_ignored() {
        // 设备不支持该按键的 divert (Back 不在 divertableCIDs 里)
        let plan = LogiDivertPlanner.plan(
            boundMosCodes: [codeBack],
            alreadyDiverted: [],
            divertableCIDs: [cidForward]
        )
        XCTAssertTrue(plan.toDivert.isEmpty)
        XCTAssertTrue(plan.toUndivert.isEmpty)
    }

    func testPlan_nonLogitechBoundCode_ignored() {
        // 绑定集合里包含普通鼠标 code (如 3 = 标准 Button 3), 不是 Logi CID, 应被忽略
        let plan = LogiDivertPlanner.plan(
            boundMosCodes: [3, 4],
            alreadyDiverted: [],
            divertableCIDs: [cidBack]
        )
        XCTAssertTrue(plan.toDivert.isEmpty)
        XCTAssertTrue(plan.toUndivert.isEmpty)
    }

    func testPlan_mixedAddAndRemove() {
        // 曾经绑过 Back (已 divert), 现在改绑 Forward
        let plan = LogiDivertPlanner.plan(
            boundMosCodes: [codeForward],
            alreadyDiverted: [cidBack],
            divertableCIDs: [cidBack, cidForward, cidSmartShift]
        )
        XCTAssertEqual(plan.toDivert, [cidForward])
        XCTAssertEqual(plan.toUndivert, [cidBack])
    }

    func testPlan_genericCIDViaFormulaMapping() {
        // G1 (0x1001) 走公式映射 (2000 + cid), 确认 toCID 反向映射走通
        let plan = LogiDivertPlanner.plan(
            boundMosCodes: [codeG1],
            alreadyDiverted: [],
            divertableCIDs: [cidG1]
        )
        XCTAssertEqual(plan.toDivert, [cidG1])
    }
}
