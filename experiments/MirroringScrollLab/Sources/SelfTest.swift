// 离线自检: 不申请辅助功能权限, 不创建 tap, 也不投递任何事件
//
// 1. 逐项核对记录器依赖的字段语义: 写入后能否读回, 哪些字段互相覆盖, NSEvent 侧读到的是哪一份位移
// 2. 在临时目录跑一次完整记录轮次, 读回 JSONL 校验结构, 确认记录链路在没有设备的情况下可用
//
// 运行: DerivedData/Build/Products/Debug/MirroringScrollLab.app/Contents/MacOS/MirroringScrollLab --selftest

import AppKit
import CoreGraphics
import Foundation

enum SelfTest {
    private static var failures = 0

    static func run() -> Int32 {
        section("1. 字段读写与别名")
        checkPublicFields()
        checkPrivateFields()
        checkAlias()
        checkPointDoesNotFillRaw()
        checkPhasedOutputFields()
        section("2. NSEvent 侧读数")
        checkNSEventSide()
        section("3. 记录器链路")
        checkRecorderRound()
        checkRoundIsolation()
        section("结果")
        print(failures == 0 ? "全部通过" : "\(failures) 项失败")
        return failures == 0 ? 0 : 1
    }

    // MARK: - 字段

    private static func pixelScroll() -> CGEvent {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 2, wheel2: 3, wheel3: 0)!
    }

    private static func checkPublicFields() {
        let e = pixelScroll()
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 7)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -8)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 7.5)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
        equal("point_y 读回", e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 7)
        equal("point_x 读回", e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -8)
        equal("fixed_y 读回 (double)", e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 7.5)
        equal("phase 读回", e.getIntegerValueField(.scrollWheelEventScrollPhase), 2)
        // MomentumPhase 与 173 共享存储: 写 123 会覆盖 173 的整值
        equal("momentum 读回", e.getIntegerValueField(.scrollWheelEventMomentumPhase), 1)
    }

    private static func checkPrivateFields() {
        let e = pixelScroll()
        e.setIntegerValueField(Field.sender, value: 91)
        e.setDoubleValueField(Field.accelY, value: -102.75)
        e.setDoubleValueField(Field.rawY, value: -202.875)
        e.setDoubleValueField(Field.accelX, value: 101.25)
        e.setDoubleValueField(Field.rawX, value: 201.5)
        e.setIntegerValueField(Field.inverted, value: 1)
        equal("sender 87", e.getIntegerValueField(Field.sender), 91)
        equal("accel_y 176", e.getDoubleValueField(Field.accelY), -102.75)
        equal("raw_y 178", e.getDoubleValueField(Field.rawY), -202.875)
        equal("accel_x 175", e.getDoubleValueField(Field.accelX), 101.25)
        equal("raw_x 177", e.getDoubleValueField(Field.rawX), 201.5)
        equal("inverted 137", e.getIntegerValueField(Field.inverted), 1)
        let copy = e.copy()!
        equal("复制后 raw_y 178", copy.getDoubleValueField(Field.rawY), -202.875)
        equal("复制后 sender 87", copy.getIntegerValueField(Field.sender), 91)
    }

    private static func checkAlias() {
        let e = pixelScroll()
        e.setIntegerValueField(Field.momentumOption, value: 50)
        equal("option 173 写入 50", e.getIntegerValueField(Field.momentumOption), 50)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
        equal("写 123 后 173 被覆盖", e.getIntegerValueField(Field.momentumOption), 1)
        print("  说明: 每帧先写 123 再写 173, 顺序颠倒会丢掉惯性打断位 0x10")
    }

    private static func checkPointDoesNotFillRaw() {
        let e = pixelScroll()
        e.setDoubleValueField(Field.rawY, value: 8.5)
        e.setDoubleValueField(Field.rawX, value: 7.625)
        e.setDoubleValueField(Field.accelY, value: 3.25)
        e.setDoubleValueField(Field.accelX, value: 2.75)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -55)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 44)
        equal("改 point 后 raw_y 不变", e.getDoubleValueField(Field.rawY), 8.5)
        equal("改 point 后 accel_y 不变", e.getDoubleValueField(Field.accelY), 3.25)
        print("  说明: 补齐 175-178 必须显式写入, Point 96/97 不会带动它们")
    }

    // MARK: - NSEvent

    /// phased 输出的公开位移必须保持逐帧值; 行位移写入顺序错误时 96 会被重算成 ±8
    private static func checkPhasedOutputFields() {
        var cfg = LabConfig()
        cfg.sender = .zero
        guard let e = CGOutput.makePhased(dx: 0, dy: 3, phase: 2, momentum: 0, at: .zero, cfg: cfg) else { fail("无法构造 phased 事件"); return }
        equal("phased 像素位移 96 保持帧值", e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 3)
        equal("phased 行位移 11 为方向", e.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1)
        equal("phased 定点位移 93 未被行位移覆盖", abs(e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) - 0.3) < 0.001, true)
    }

    private static func checkNSEventSide() {
        let notch = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 2, wheel2: 3, wheel3: 0)!
        if let n = NSEvent(cgEvent: notch) {
            equal("行滚动 deltaY", Double(n.deltaY), 2)
            equal("行滚动 precise", n.hasPreciseScrollingDeltas, false)
        } else {
            fail("行滚动无法构造 NSEvent")
        }
        let pixel = pixelScroll()
        pixel.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        pixel.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 7)
        pixel.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -8)
        if let n = NSEvent(cgEvent: pixel) {
            equal("连续滚动 precise", n.hasPreciseScrollingDeltas, true)
            // 连续滚动时 NSEvent 的位移取 Point, 符号与 CGEvent 约定相反
            equal("连续滚动 scrollingDeltaY", n.scrollingDeltaY, 7)
            equal("连续滚动 scrollingDeltaX", n.scrollingDeltaX, -8)
        } else {
            fail("像素滚动无法构造 NSEvent")
        }
        let phased = pixelScroll()
        phased.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        phased.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 3)
        if let n = NSEvent(cgEvent: phased) {
            // CG 99 的 2/4/8 映射到 NSEvent 的 4/8/16; CG 123 的 1/2/3 映射到 1/4/8
            equal("CG phase 2 到 NSEvent", Int(n.phase.rawValue), 4)
            equal("CG momentum 3 到 NSEvent", Int(n.momentumPhase.rawValue), 8)
        } else {
            fail("带阶段的事件无法构造 NSEvent")
        }
    }

    // MARK: - 记录器

    private static func checkRecorderRound() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mirroring-lab-selftest-\(UUID().uuidString)")
        var cfg = LabConfig()
        cfg.evidenceRoot = root.path
        guard let dir = Recorder.shared.start(label: "selftest", cfg: cfg) else {
            fail("记录轮次未能建立: \(Recorder.shared.state.get().problem ?? "未知")")
            return
        }
        let captured = pixelScroll()
        captured.setIntegerValueField(Field.sender, value: 91)
        captured.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 12)
        captured.setDoubleValueField(Field.rawY, value: -48)
        Recorder.shared.recordCaptured(captured, decision: "repost", cfg: cfg)
        let emitted = pixelScroll()
        emitted.setIntegerValueField(Field.sender, value: 91)
        emitted.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 4)
        emitted.setDoubleValueField(Field.rawY, value: -16)
        Recorder.shared.recordEmitted(emitted, kind: "post_phased", target: .hid, cfg: cfg)
        // 没有帧上下文时 (引擎未 tick) 帧龄不该出现; 造一个帧上下文再记一条, 校验帧内事件的归属
        ScrollEngine.frameSnapshot.set(FrameSnapshot(gesture: 7, frame: 12, tickTime: Trace.now()))
        Recorder.shared.recordEmitted(emitted, kind: "post_phased", target: .hid, cfg: cfg)
        ScrollEngine.frameSnapshot.set(FrameSnapshot())
        Recorder.shared.snapshotServices()
        Recorder.shared.stop()

        let frames = dir.appendingPathComponent("frames.jsonl")
        let text = (try? String(contentsOf: frames, encoding: .utf8)) ?? ""
        let rows = text.split(separator: "\n").compactMap { line -> [String: Any]? in
            guard let data = line.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        let capturedRow = rows.first { $0["kind"] as? String == "captured" }
        let emittedRows = rows.filter { $0["kind"] as? String == "emitted" }
        let emittedRow = emittedRows.first
        let inFrameRow = emittedRows.last
        equal("JSONL 行数 (start + 输入 + 2 输出 + end)", rows.count, 5)
        for key in ["sender", "is_continuous", "line_y", "line_x", "fixed_y", "fixed_x", "point_y", "point_x",
                    "phase", "momentum", "inverted", "option", "accel_y", "accel_x", "raw_y", "raw_x",
                    "user_data", "cg_ts", "loc", "ratio", "t", "in_seq", "in_session", "decision", "scope", "mode"] {
            present("输入记录 \(key)", capturedRow, key)
        }
        for key in ["sender", "is_continuous", "point_y", "accel_y", "raw_y", "raw_x", "phase", "momentum",
                    "inverted", "option", "t", "event", "target", "gesture", "frame", "outcome", "mode"] {
            present("输出记录 \(key)", emittedRow, key)
        }
        absent("无帧上下文时不写帧龄", emittedRow, "frame_age")
        equal("帧内记录的会话号", inFrameRow?["gesture"] as? Int, 7)
        equal("帧内记录的帧号", inFrameRow?["frame"] as? Int, 12)
        equal("帧内记录的 in_frame", inFrameRow?["in_frame"] as? Bool, true)
        present("帧内记录的 tick_t", inFrameRow, "tick_t")
        equal("输入记录 sender", capturedRow?["sender"] as? Int64, 91)
        equal("输出记录 target", emittedRow?["target"] as? String, "hid")
        let ratio = capturedRow?["ratio"] as? [String: Any]
        equal("输入记录 raw/point 比值", ratio?["raw_pt_y"] as? Double, -4)
        for file in ["round.json", "config.json", "services.json", "notes.txt"] {
            let path = dir.appendingPathComponent(file)
            let exists = FileManager.default.fileExists(atPath: path.path)
            exists ? pass("轮次文件 \(file)") : fail("轮次文件 \(file) 缺失")
        }
        let services = (try? Data(contentsOf: dir.appendingPathComponent("services.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let count = (services?["services"] as? [Any])?.count ?? 0
        count > 0 ? pass("服务快照包含 \(count) 个服务") : fail("服务快照没有服务")
        let revision = (services?["source"] as? [String: Any])?["revision"] as? String
        revision != nil && revision != "unknown" ? pass("服务快照带 git 版本 \(revision!)") : fail("服务快照缺少 git 版本")
        // 保留目录供离线分析脚本试跑: LAB_SELFTEST_KEEP=1
        if ProcessInfo.processInfo.environment["LAB_SELFTEST_KEEP"] == nil {
            try? FileManager.default.removeItem(at: root)
        } else {
            print("  保留轮次目录: \(dir.path)")
        }
    }

    private static func checkRoundIsolation() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lab-isolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cfg = LabConfig()
        guard let first = Recorder.shared.start(label: "same", cfg: cfg, root: root) else {
            fail("第一轮无法创建"); return
        }
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            Recorder.shared.recordCaptured(pixelScroll(), decision: "pass_disabled", cfg: cfg)
        }
        Recorder.shared.stop()
        let original = try? Data(contentsOf: first.appendingPathComponent("frames.jsonl"))
        let rows = original.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\n") ?? []
        equal("并发记录保留全部行", rows.count, 22)
        guard let second = Recorder.shared.start(label: "same", cfg: cfg, root: root) else {
            fail("第二轮无法创建"); return
        }
        Recorder.shared.configChanged(cfg)
        Recorder.shared.recordFrame(dx: 1, dy: 4, cfg: cfg)
        Recorder.shared.stop()
        equal("同名轮次使用独立目录", first != second, true)
        equal("后续轮次不覆盖已有记录", try? Data(contentsOf: first.appendingPathComponent("frames.jsonl")), original)
        Recorder.shared.recordCaptured(pixelScroll(), decision: "pass_disabled", cfg: cfg)
        let secondRows = (try? String(contentsOf: second.appendingPathComponent("frames.jsonl"), encoding: .utf8))?.split(separator: "\n") ?? []
        equal("停止后不追加事件", secondRows.count, 4)
    }

    // MARK: - 断言

    private static func section(_ title: String) { print("\n== \(title) ==") }
    private static func pass(_ what: String) { print("  ok   \(what)") }
    private static func fail(_ what: String) { failures += 1; print("  FAIL \(what)") }

    private static func equal<T: Equatable>(_ what: String, _ got: T, _ want: T) {
        got == want ? pass("\(what) = \(got)") : fail("\(what): 期望 \(want), 实测 \(got)")
    }

    private static func absent(_ what: String, _ row: [String: Any]?, _ key: String) {
        guard let row else { fail("\(what): 没有记录"); return }
        row[key] == nil ? pass(what) : fail("\(what): 不该出现 \(key)")
    }

    private static func present(_ what: String, _ row: [String: Any]?, _ key: String) {
        guard let row else { fail("\(what): 没有记录"); return }
        // 转换字段名后按同一套名字校验, 避免大小写或下划线不一致
        row[key] != nil ? pass(what) : fail("\(what) 缺失")
    }
}
