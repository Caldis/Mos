// Lab 配置: 界面上的全部选项, 预设, 以及持久化存储
// LabConfig 是普通值类型; ConfigStore 把它发布给 SwiftUI, 同时同步到一个加锁的快照
// (`live`), 供 event tap 线程读取, 不经过主线程

import Foundation
import CoreGraphics

enum TapLocation: String, CaseIterable, Codable, Identifiable {
    case hid, session, annotatedSession
    var id: Self { self }
    var label: String {
        switch self {
        case .hid: return "HID (kCGHIDEventTap)"
        case .session: return "Session (kCGSessionEventTap)"
        case .annotatedSession: return "Annotated Session (Mos 现状)"
        }
    }
    var cg: CGEventTapLocation {
        switch self {
        case .hid: return .cghidEventTap
        case .session: return .cgSessionEventTap
        case .annotatedSession: return .cgAnnotatedSessionEventTap
        }
    }
}

enum TapPlacement: String, CaseIterable, Codable, Identifiable {
    case head, tail
    var id: Self { self }
    var label: String { self == .head ? "头部 (最先收到)" : "尾部 (最后收到)" }
    var cg: CGEventTapPlacement { self == .head ? .headInsertEventTap : .tailAppendEventTap }
}

enum Scope: String, CaseIterable, Codable, Identifiable {
    case mirroringWindow, mirroringFrontmost, global
    var id: Self { self }
    var label: String {
        switch self {
        case .mirroringWindow: return "光标在 iPhone 镜像窗口内"
        case .mirroringFrontmost: return "iPhone 镜像在前台"
        case .global: return "全局"
        }
    }
}

enum OutputMode: String, CaseIterable, Codable, Identifiable {
    case passthrough, rewriteInPlace, wheelRepost, phasedScroll, virtualMouse, magicTrackpad, virtualTouchpad
    var id: Self { self }
    var label: String {
        switch self {
        case .passthrough: return "直通 (不处理)"
        case .rewriteInPlace: return "原地改写 (只做翻转)"
        case .wheelRepost: return "吞掉后重投滚轮 (Mos 式)"
        case .phasedScroll: return "触控板式 phased 滚动"
        case .virtualMouse: return "虚拟 HID 鼠标滚轮 (系统会再加速)"
        case .magicTrackpad: return "虚拟妙控板 (原生触控板栈)"
        case .virtualTouchpad: return "虚拟 HID 触控板 (已知无效)"
        }
    }
    var postsCGEvents: Bool { self == .wheelRepost || self == .phasedScroll }
    var usesEngine: Bool { self != .passthrough && self != .rewriteInPlace }
}

enum PostTarget: String, CaseIterable, Codable, Identifiable {
    case hid, session, annotatedSession, mirroringPid
    var id: Self { self }
    var label: String {
        switch self {
        case .hid: return "HID tap"
        case .session: return "Session tap"
        case .annotatedSession: return "Annotated Session tap"
        case .mirroringPid: return "postToPid (iPhone 镜像)"
        }
    }
}

enum DeltaSource: String, CaseIterable, Codable, Identifiable {
    case notch, systemPoint
    var id: Self { self }
    var label: String { self == .notch ? "每格固定像素" : "系统加速后的像素" }
}

enum SmoothingModel: String, CaseIterable, Codable, Identifiable {
    case mos, exponential
    var id: Self { self }
    var label: String { self == .mos ? "Mos 插值 (与 Mos 一致)" : "指数逼近 (按时长)" }
}

enum DistanceEncoding: String, CaseIterable, Codable, Identifiable {
    case delta, count
    var id: Self { self }
    var label: String { self == .delta ? "增量大小" : "事件个数 (phone-harness)" }
}

enum MomentumMode: String, CaseIterable, Codable, Identifiable {
    case none, synthetic
    var id: Self { self }
    var label: String { self == .none ? "不发 (交给 iOS)" : "合成惯性尾巴" }
}

enum SenderMode: String, CaseIterable, Codable, Identifiable {
    case zero, learnedTrackpad, builtinTrackpad, virtualMagicTrackpad, realMouse
    var id: Self { self }
    var label: String {
        switch self {
        case .zero: return "0 (不设置)"
        case .learnedTrackpad: return "最近一次真实触控板事件的 sender"
        case .builtinTrackpad: return "内置/实体触控板服务"
        case .virtualMagicTrackpad: return "虚拟妙控板服务"
        case .realMouse: return "最近一次物理鼠标事件的 sender"
        }
    }
}

struct LabConfig: Codable, Equatable {
    var enabled = true

    // 捕获
    var tapLocation: TapLocation = .hid
    var tapPlacement: TapPlacement = .head
    var scope: Scope = .mirroringWindow
    var consumeOriginal = true
    var includeContinuous = false
    var invertVertical = false
    var invertHorizontal = false
    var deltaSource: DeltaSource = .notch
    var stepPx: Double = 60

    // 输出
    var mode: OutputMode = .phasedScroll
    var postTarget: PostTarget = .hid

    // 平滑
    var smooth = true
    var smoothing: SmoothingModel = .mos
    var mosStep: Double = 33.6
    var mosSpeed: Double = 2.7
    var mosDuration: Double = 4.35
    var mosDeadZone: Double = 1
    var durationMs: Double = 200
    var frameClock: FrameClockKind = .cvDisplayLink
    /// 按实际帧间隔把按帧定义的插值常数换算到基准帧率, 使不同刷新率下的时间曲线一致
    var timeNormalize = false
    var referenceHz: Double = 60
    var followDisplayHz = true
    var frameHz: Double = 120
    var endGraceMs: Double = 80

    // 滚轮重投
    var repostContinuous = true

    // phased 滚动
    var distance: DistanceEncoding = .delta
    var ptPerEvent: Double = 7
    var mayBegin = true
    var momentum: MomentumMode = .none
    var momentumDecay: Double = 0.94
    var momentumMinPx: Double = 0.5
    /// 插值末段单帧位移降到该值以下时直接切入合成惯性 (0 = 关闭, 等插值结束并经过结束等待后再开始惯性)
    var momentumHandoffPx: Double = 3
    var crossAxisJitter = false
    var sender: SenderMode = .zero
    var gestureCompanion = false
    var resetBeforeGesture = false
    var markOwnEvents = true
    var fillRawFields = false
    var accelScale: Double = 1
    var rawScale: Double = 1

    // 原地改写
    var rewritePublic = true
    var rewriteRaw = true
    var rewriteFlag137 = false

    // 虚拟设备
    var pxPerWheelUnit: Double = 10
    var pointerNudge = true
    var touchpadScale: Double = 4
    var magicScale: Double = 4
    var magicSettleFrames: Double = 3
    var magicKeepAlive = true
    var magicFlipHorizontal = false
    /// 插值末段单帧位移降到该值以下时提前抬指, 让系统按抬指速度生成惯性 (0 = 关闭)
    var magicLiftPx: Double = 0

    var evidenceRoot = ""
    var recordNSEvent = true

    var monitor = true
    /// 全部诊断功能的总开关: 曲线, 会话记录, 事件日志和状态区的定时刷新
    var diagnostics = true
}

struct Preset: Identifiable {
    let id: String
    let note: String
    let apply: (inout LabConfig) -> Void

    static let all: [Preset] = [
        Preset(id: "直通基线", note: "不处理任何事件, 感受原始滚轮") { $0.mode = .passthrough },
        Preset(id: "Mos 现状 (对照)", note: "Annotated Session tap + 平滑重投 + postToPid, 预期镜像内无效") {
            $0.tapLocation = .annotatedSession; $0.mode = .wheelRepost; $0.postTarget = .mirroringPid
            $0.smooth = true; $0.invertVertical = true
        },
        Preset(id: "翻转: HID 原地改写", note: "在 HID tap 翻转原事件的公开位移与 175-178, 不吞不重投") {
            $0.mode = .rewriteInPlace; $0.invertVertical = true
        },
        Preset(id: "翻转: Mos 层原地改写", note: "在 Mos 所用的 Annotated Session tap 翻转公开位移与 175-178, 验证 #762 是否只是字段问题") {
            $0.tapLocation = .annotatedSession; $0.mode = .rewriteInPlace; $0.invertVertical = true
        },
        Preset(id: "翻转: HID 吞掉 + 重投", note: "路线 C: 吞掉原始滚轮, 从 HID tap 重投翻转后的格滚动") {
            $0.mode = .wheelRepost; $0.smooth = false; $0.invertVertical = true
        },
        Preset(id: "触控板拖动 (无惯性)", note: "滚轮转为 phased 连续滚动, 结束后由 iOS 自行处理") {
            $0.mode = .phasedScroll; $0.momentum = .none
        },
        Preset(id: "触控板 + 合成惯性", note: "phased 滚动 + mirroir-mcp 式衰减惯性尾巴") {
            $0.mode = .phasedScroll; $0.momentum = .synthetic
        },
        Preset(id: "身份借用: 触控板 sender", note: "phased CGEvent 带实体触控板服务的 sender, 并补齐 175-178") {
            $0.mode = .phasedScroll; $0.sender = .builtinTrackpad; $0.fillRawFields = true
        },
        Preset(id: "身份借用: 虚拟妙控板 sender", note: "phased CGEvent 带虚拟妙控板服务的 sender, 虚拟设备只提供身份, 不发触摸") {
            $0.mode = .phasedScroll; $0.sender = .virtualMagicTrackpad; $0.fillRawFields = true
        },
        Preset(id: "phone-harness 计数编码", note: "距离用 Changed 事件个数表达, 每个事件固定增量 9") {
            $0.mode = .phasedScroll; $0.distance = .count; $0.followDisplayHz = false; $0.frameHz = 60
        },
        Preset(id: "虚拟 HID 滚轮平滑", note: "CoreHID 虚拟鼠标按帧发细分滚轮") {
            $0.mode = .virtualMouse
        },
        Preset(id: "虚拟妙控板", note: "滚轮转为伪装 Magic Trackpad 2 的双指滑动, 由系统生成触控板滚动与惯性") {
            $0.mode = .magicTrackpad
        },
    ]
}

final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()
    private static let key = "labConfig"

    /// event tap 线程读取的快照
    let live: Locked<LabConfig>
    var onChange: ((LabConfig, LabConfig) -> Void)?

    @Published var config: LabConfig {
        didSet {
            guard config != oldValue else { return }
            live.set(config)
            if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: Self.key) }
            onChange?(oldValue, config)
        }
    }

    private init() {
        var initial = LabConfig()
        // 保存的配置叠加到默认值上再解码: 新增选项缺失时取默认值, 旧配置不会因为结构变化整体失效
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let defaultsData = try? JSONEncoder().encode(LabConfig()),
           var merged = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any] {
            merged.merge(saved) { _, new in new }
            if let mergedData = try? JSONSerialization.data(withJSONObject: merged),
               let decoded = try? JSONDecoder().decode(LabConfig.self, from: mergedData) {
                initial = decoded
            }
        }
        live = Locked(initial)
        config = initial
    }

    func apply(_ preset: Preset) {
        var next = LabConfig()
        next.scope = config.scope
        next.monitor = config.monitor
        next.evidenceRoot = config.evidenceRoot
        next.recordNSEvent = config.recordNSEvent
        preset.apply(&next)
        config = next
    }
}
