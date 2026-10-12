// 字段级记录器: 把捕获到的输入事件与本工具发出的每个事件按 JSON 行写入当轮证据目录
//
// 记录内容是 CGEvent 上的原始字段值, 不做单位换算也不做方向判定; 标定与结论留给离线分析
// (tools/analyze-round.py)。记录关闭时 record* 直接返回, 热路径没有额外开销
//
// 线程模型: 字段读取与 JSON 编码在调用线程完成 (事件返回给系统后字段可能变化), 写盘交给串行队列。
// 生命周期锁串行保护开始、停止和各路记录; 写盘队列不获取该锁。输出帧号来自
// ScrollEngine.frameSnapshot

import AppKit
import CoreGraphics
import Foundation

struct RecordState {
    var recording = false
    var label = ""
    var dir: URL?
    var lines = 0
    var captured = 0
    var emitted = 0
    var startedAt: Double = 0
    var problem: String?
}

private func r6(_ v: Double) -> Double {
    v.isFinite ? (v * 1e6).rounded() / 1e6 : 0
}

/// 一次取出记录所需的全部 CGEvent 字段。
/// 编号含义与取值域见 docs/research/iphone-mirroring-scroll/evidence/2026-10-09/
enum EventFields {
    static func scroll(_ e: CGEvent, ns: Bool) -> [String: Any] {
        let i = { (f: CGEventField) in e.getIntegerValueField(f) }
        let d = { (f: CGEventField) in r6(e.getDoubleValueField(f)) }
        var f: [String: Any] = [
            "sender": i(Field.sender),
            "is_continuous": i(.scrollWheelEventIsContinuous),
            "line_y": i(.scrollWheelEventDeltaAxis1),
            "line_x": i(.scrollWheelEventDeltaAxis2),
            "fixed_y": d(.scrollWheelEventFixedPtDeltaAxis1),
            "fixed_x": d(.scrollWheelEventFixedPtDeltaAxis2),
            "point_y": i(.scrollWheelEventPointDeltaAxis1),
            "point_x": i(.scrollWheelEventPointDeltaAxis2),
            "phase": i(.scrollWheelEventScrollPhase),
            "momentum": i(.scrollWheelEventMomentumPhase),
            "inverted": i(Field.inverted),
            "option": i(Field.momentumOption),
            "accel_y": d(Field.accelY),
            "accel_x": d(Field.accelX),
            "raw_y": d(Field.rawY),
            "raw_x": d(Field.rawX),
            "user_data": i(.eventSourceUserData),
            "cg_ts": e.timestamp,
            "loc": [r6(e.location.x), r6(e.location.y)],
        ]
        // 与公开位移的比值供离线标定: Raw / Accelerated 的单位与倍率无法从字段名推出
        var ratio: [String: Double] = [:]
        let pty = Double(f["point_y"] as? Int64 ?? 0), ptx = Double(f["point_x"] as? Int64 ?? 0)
        let acy = f["accel_y"] as? Double ?? 0, acx = f["accel_x"] as? Double ?? 0
        let rwy = f["raw_y"] as? Double ?? 0, rwx = f["raw_x"] as? Double ?? 0
        if pty != 0 { ratio["raw_pt_y"] = r6(rwy / pty); ratio["acc_pt_y"] = r6(acy / pty) }
        if ptx != 0 { ratio["raw_pt_x"] = r6(rwx / ptx); ratio["acc_pt_x"] = r6(acx / ptx) }
        if acy != 0 { ratio["raw_acc_y"] = r6(rwy / acy) }
        if acx != 0 { ratio["raw_acc_x"] = r6(rwx / acx) }
        if !ratio.isEmpty { f["ratio"] = ratio }
        if ns, e.type == .scrollWheel, let n = NSEvent(cgEvent: e) {
            f["ns_ts"] = n.timestamp
            f["ns_phase"] = n.phase.rawValue
            f["ns_momentum"] = n.momentumPhase.rawValue
            f["ns_precise"] = n.hasPreciseScrollingDeltas
            f["ns_delta_y"] = r6(Double(n.deltaY))
            f["ns_delta_x"] = r6(Double(n.deltaX))
            f["ns_scroll_y"] = r6(n.scrollingDeltaY)
            f["ns_scroll_x"] = r6(n.scrollingDeltaX)
        }
        return f
    }
}

final class Recorder {
    static let shared = Recorder()
    let state = Locked(RecordState())
    /// 由生命周期锁保护, 防止停止后继续向已关闭的文件写入。
    private var active = false

    private let lifecycleLock = NSRecursiveLock()
    private let queue = DispatchQueue(label: "lab.recorder", qos: .utility)
    private var handle: FileHandle?
    /// 捕获侧按输入间隔划分会话: 相邻事件间隔超过该值视为新手势
    private static let inputGap: Double = 0.25
    private var capture = (seq: 0, session: 0, last: 0.0)

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let stampFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HHmmss"; return f
    }()
    private static let isoFormat: ISO8601DateFormatter = ISO8601DateFormatter()

    /// 证据目录: 从 app 所在位置向上找到仓库内的 evidence 目录, 便于每轮记录与文档放在一起
    static func defaultEvidenceRoot() -> URL {
        var url = URL(fileURLWithPath: Bundle.main.bundlePath)
        for _ in 0..<12 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("docs/research/iphone-mirroring-scroll/evidence")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            if url.path == "/" { break }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mirroring-scroll-lab/evidence")
    }

    func evidenceRoot(_ cfg: LabConfig) -> URL {
        let path = cfg.evidenceRoot.trimmingCharacters(in: .whitespaces)
        return path.isEmpty ? Self.defaultEvidenceRoot() : URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    // MARK: - 轮次

    @discardableResult
    func start(label: String, cfg: LabConfig, root: URL? = nil) -> URL? {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        stop()
        let name = label.isEmpty ? "round" : Self.sanitize(label)
        let dir = (root ?? evidenceRoot(cfg))
            .appendingPathComponent(Self.dayFormat.string(from: Date()))
            .appendingPathComponent("lab")
            .appendingPathComponent("\(Self.stampFormat.string(from: Date()))-\(name)-\(UUID().uuidString.prefix(8))")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("frames.jsonl")
            guard FileManager.default.createFile(atPath: file.path, contents: nil),
                  let h = try? FileHandle(forWritingTo: file) else {
                throw NSError(domain: "lab.recorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法写入 \(file.path)"])
            }
            handle = h
            capture = (0, 0, 0)
            state.set(RecordState(recording: true, label: name, dir: dir, startedAt: CACurrentMediaTime()))
            active = true
            writeMeta(cfg, to: dir)
            writeFile(ServiceMap.snapshot(), named: "services.json", in: dir)
            write(["kind": "round_start", "t": r6(CACurrentMediaTime()), "label": name,
                   "app": Self.appVersion, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                   "source": ServiceMap.source])
            note("轮次 \(name) 开始; 配置见 config.json, 服务快照见 services.json")
            return dir
        } catch {
            state.mutate { $0.problem = error.localizedDescription }
            return nil
        }
    }

    func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard active else { return }
        active = false
        let s = state.get()
        write(["kind": "round_end", "t": r6(CACurrentMediaTime()), "label": s.label,
               "captured": s.captured, "emitted": s.emitted, "lines": s.lines + 1])
        queue.sync {}
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        state.mutate { $0.recording = false }
        Lab.log("记录停止: \(s.label), 输入 \(s.captured) 输出 \(s.emitted)")
    }

    // MARK: - 记录

    /// decision 说明 tap 对该事件做了什么: own_observed / pass_disabled / pass_continuous / pass_out_of_scope /
    /// pass_empty / rewrite / repost / repost_keep_original
    func recordCaptured(_ e: CGEvent, decision: String, cfg: LabConfig) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard active else { return }
        let t = CACurrentMediaTime()
        if t - capture.last > Self.inputGap { capture.session += 1 }
        capture.last = t
        capture.seq += 1
        var row = EventFields.scroll(e, ns: cfg.recordNSEvent)
        row["kind"] = "captured"
        row["t"] = r6(t)
        row["in_seq"] = capture.seq
        row["in_session"] = capture.session
        row["decision"] = decision
        row["scope"] = cfg.scope.rawValue
        row["mode"] = cfg.mode.rawValue
        row["diag"] = Lab.diagnosticsEnabled
        write(row)
        state.mutate { $0.captured += 1 }
    }

    /// kind 说明事件的产生者: post_line / post_pixel / post_phased / post_companion / post_reset / rewrite
    func recordEmitted(_ e: CGEvent, kind: String, target: PostTarget?, cfg: LabConfig, outcome: String = "posted") {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard active else { return }
        let post = CACurrentMediaTime()
        let frame = ScrollEngine.frameSnapshot.get()
        var row = EventFields.scroll(e, ns: cfg.recordNSEvent)
        row["kind"] = "emitted"
        row["t"] = r6(post)
        row["event"] = kind
        row["target"] = target?.rawValue ?? "in_place"
        row["outcome"] = outcome
        if target == .mirroringPid, let pid = MirroringLocator.shared.state.get().pid { row["pid"] = pid }
        row["gesture"] = frame.gesture
        row["frame"] = frame.frame
        // 每帧的信号发出在微秒级完成; 远晚于 tick 的事件 (复位序列, 配置变化触发的输出) 不属于该帧
        if frame.tickTime > 0 {
            let age = post - frame.tickTime
            // tick_t 是本帧的信号时刻, t 是实际投递时刻; frame_age 为两者之差
            row["tick_t"] = r6(frame.tickTime)
            row["frame_age"] = r6(age)
            row["in_frame"] = age < 0.05
        }
        row["mode"] = cfg.mode.rawValue
        write(row)
        state.mutate { $0.emitted += 1 }
    }

    /// 引擎每帧计算出的输出距离。虚拟设备输出没有 CGEvent, 只有这一条记录留下帧号与距离
    func recordFrame(dx: Double, dy: Double, cfg: LabConfig) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard active else { return }
        let frame = ScrollEngine.frameSnapshot.get()
        write(["kind": "frame", "t": r6(CACurrentMediaTime()), "gesture": frame.gesture, "frame": frame.frame,
               "tick_t": r6(frame.tickTime), "dx": r6(dx), "dy": r6(dy), "mode": cfg.mode.rawValue])
    }

    func configChanged(_ cfg: LabConfig) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard active else { return }
        write(["kind": "config", "t": r6(CACurrentMediaTime()), "config": cfg.jsonObject])
    }

    func snapshotServices() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard let dir = state.get().dir else { return }
        writeFile(ServiceMap.snapshot(), named: "services.json", in: dir)
        Lab.log("已更新服务映射快照")
    }

    func note(_ text: String) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard let dir = state.get().dir else { return }
        let line = "\(Self.isoFormat.string(from: Date())) \(text)\n"
        queue.async {
            let file = dir.appendingPathComponent("notes.txt")
            if let h = try? FileHandle(forWritingTo: file) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: file)
            }
        }
    }

    func openRound() {
        guard let dir = state.get().dir else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }

    // MARK: - 写盘

    private func write(_ object: [String: Any]) {
        guard let h = handle, JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        queue.async { try? h.write(contentsOf: data) }
        state.mutate { $0.lines += 1 }
    }

    private func writeFile(_ object: [String: Any], named name: String, in dir: URL) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: dir.appendingPathComponent(name))
    }

    private func writeMeta(_ cfg: LabConfig, to dir: URL) {
        var meta: [String: Any] = [
            "label": state.get().label,
            "started": Self.isoFormat.string(from: Date()),
            "app": Self.appVersion,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "bundle": Bundle.main.bundlePath,
            "evidence_root": evidenceRoot(cfg).path,
        ]
        meta["config"] = cfg.jsonObject
        meta["source"] = ServiceMap.source
        writeFile(meta, named: "round.json", in: dir)
        writeFile(cfg.jsonObject, named: "config.json", in: dir)
    }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private static func sanitize(_ label: String) -> String {
        let allowed = label.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        let s = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? "round" : String(s.prefix(40))
    }
}

extension LabConfig {
    /// 配置对象转 JSON 字典, 用于记录当轮生效的全部参数
    var jsonObject: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }
}
