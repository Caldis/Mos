// 曲线和会话列表背后的诊断缓冲
// 记录三条采样流: 捕获到的输入 (engine.input), 引擎每帧输出 (emitFrame), 以及在 tap 观测到的
// 自身输出事件 (标记为自身的滚动事件)。会话记录对三者计数, 发出了帧却没有产生输出事件的
// 会话会显示为失效

import Foundation
import QuartzCore

enum SampleKind {
    case input      // 捕获到的物理滚轮位移
    case engine     // 引擎计算出的每帧输出
    case system     // 本工具输出产生的滚动事件, 在 tap 处观测到
}

struct Sample {
    let t: Double
    let kind: SampleKind
    /// 纵向位移 (CGEvent 轴 1)
    let value: Double
    /// 横向位移 (CGEvent 轴 2)
    let x: Double
    let phase: Int64
    let momentum: Int64
}

/// 一次输出会话: 从空闲后的第一次输入开始, 到引擎计时器停止为止
struct GestureRecord: Identifiable {
    let id: Int
    let mode: String
    let start: Double
    var end: Double?
    var inputEvents = 0
    var framesSent = 0
    var systemScroll = 0
    var systemMomentum = 0
    var dispatchErrors = 0
}

enum Trace {
    static let samples = Locked<[Sample]>([])
    static let gestures = Locked<[GestureRecord]>([])
    private static let nextID = Locked(1)
    /// 会话结束后这段时间内观测到的输出事件仍归属该会话 (惯性尾巴)
    static let attachWindow = 1.5

    static func now() -> Double { CACurrentMediaTime() }

    /// 最近一次会话的编号; 还没有会话时为 nil
    static var currentGestureID: Int? { gestures.get().last?.id }

    static func add(_ kind: SampleKind, _ value: Double, x: Double = 0, phase: Int64 = 0, momentum: Int64 = 0) {
        guard Lab.diagnosticsEnabled else { return }
        let t = now()
        samples.mutate {
            $0.append(Sample(t: t, kind: kind, value: value, x: x, phase: phase, momentum: momentum))
            if let first = $0.first, t - first.t > 12 { $0.removeAll { t - $0.t > 10 } }
        }
    }

    static func beginGesture(mode: String) {
        guard Lab.diagnosticsEnabled else { return }
        let id = nextID.mutate { v -> Int in defer { v += 1 }; return v }
        gestures.mutate {
            $0.append(GestureRecord(id: id, mode: mode, start: now()))
            if $0.count > 30 { $0.removeFirst($0.count - 30) }
        }
    }

    static func endGesture() {
        gestures.mutate { if let i = $0.indices.last, $0[i].end == nil { $0[i].end = now() } }
    }

    /// 若最新会话仍在进行或刚结束不超过归属窗口, 则对其应用 `body`
    static func updateLatest(_ body: (inout GestureRecord) -> Void) {
        guard Lab.diagnosticsEnabled else { return }
        let t = now()
        gestures.mutate {
            guard let i = $0.indices.last else { return }
            if let end = $0[i].end, t - end > attachWindow { return }
            body(&$0[i])
        }
    }
}
