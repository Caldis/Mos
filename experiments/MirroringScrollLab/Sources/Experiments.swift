// 引导式实验: 每个实验由一组只差一个变量的变体组成。
// 套用变体时以已知可用的 phased 配置为基线, 只改变该变体声明的选项, 并按需创建或销毁虚拟妙控板;
// 开启自动记录时, 每次切换变体都会开始一个以变体编号命名的新轮次

import SwiftUI

struct ExperimentVariant: Identifiable {
    let id: String
    let title: String
    let note: String
    /// 变体是否需要虚拟妙控板存在。为 false 时套用变体会销毁设备, 保证结果不依赖它
    let needsVirtualTrackpad: Bool
    let apply: (inout LabConfig) -> Void
}

struct Experiment: Identifiable {
    let id: String
    let title: String
    let question: String
    let procedure: String
    let reading: String
    let variants: [ExperimentVariant]
    /// 盲测: 变体按钮只显示 X / Y, 对应关系在启动时随机分配, 揭晓前不显示
    var blind = false

    /// 基线: 已验证在 iPhone 镜像内顺滑的 phased 配置 (2026-10-09 用户实测)
    static func baseline(_ c: inout LabConfig) {
        c.tapLocation = .hid
        c.tapPlacement = .head
        c.consumeOriginal = true
        c.mode = .phasedScroll
        c.postTarget = .hid
        c.smooth = true
        c.smoothing = .mos
        c.timeNormalize = true
        c.referenceHz = 60
        c.frameClock = .screenDisplayLink
        c.endGraceMs = 20
        c.distance = .delta
        c.mayBegin = true
        c.resetBeforeGesture = true
        c.gestureCompanion = true
        c.markOwnEvents = true
        c.momentum = .none
        c.sender = .virtualMagicTrackpad
        c.fillRawFields = true
        c.accelScale = 1
        c.rawScale = 1
    }

    static let all: [Experiment] = [
        Experiment(
            id: "E1",
            title: "惯性归属",
            question: "镜像内的滑行跟随 Mac 发出的惯性事件, 还是由 iOS 按手势结束时的速度自行减速",
            procedure: "在同一个长列表的同一位置, 以相同力度快速拨动滚轮 3 格后松开, 每个变体重复至少 5 次, 观察滚轮停止后列表继续滑行的距离",
            reading: "E1-L 的滑行距离明显长于 E1-S: 镜像跟随 Mac 的惯性事件, 惯性应由 Mos 负责。三者距离相近: iOS 忽略 Mac 的惯性事件, 使用自身减速。E1-S 与 E1-L 都不滑行而 E1-N 滑行: Mac 的惯性事件会抑制 iOS 的减速",
            variants: [
                ExperimentVariant(id: "E1-N", title: "不发惯性 (对照)", note: "手势结束后不发送任何惯性事件", needsVirtualTrackpad: true) { _ in },
                ExperimentVariant(id: "E1-S", title: "合成惯性 衰减 0.80", note: "惯性约 10 帧内衰减完毕, 滑行很短", needsVirtualTrackpad: true) {
                    $0.momentum = .synthetic; $0.momentumDecay = 0.80; $0.momentumHandoffPx = 3
                },
                ExperimentVariant(id: "E1-L", title: "合成惯性 衰减 0.99", note: "惯性持续数百帧, 滑行很长", needsVirtualTrackpad: true) {
                    $0.momentum = .synthetic; $0.momentumDecay = 0.99; $0.momentumHandoffPx = 3
                },
            ]),
        Experiment(
            id: "E2",
            title: "Sender 独立性",
            question: "phased 输出能否不借用虚拟妙控板的 sender, 只用物理鼠标自己的 sender 加补齐的 175-178 得到同样的顺滑度",
            procedure: "先在镜像窗口外用物理鼠标滚动一次, 确认下方的物理鼠标 sender 不为 0。每个变体分别做慢速滚动、快速连续滚动、单格滚动, 与 E2-V 对比顺滑度和速度",
            reading: "E2-M1 与 E2-V 手感一致: 修复镜像不需要虚拟设备, 适用于所有 macOS 15 机器。E2-M1 可用但速度不同: 调整加速位移倍率后再比较, 镜像可能按鼠标的设备属性处理加速。E2-M1 卡顿而 E2-T 顺滑: 镜像要求 sender 指向触控板类设备",
            variants: [
                ExperimentVariant(id: "E2-V", title: "虚拟妙控板 sender + 补齐 (对照)", note: "当前已知可用的配置", needsVirtualTrackpad: true) { _ in },
                ExperimentVariant(id: "E2-M1", title: "物理鼠标 sender + 补齐", note: "销毁虚拟妙控板, sender 取最近一次物理鼠标事件", needsVirtualTrackpad: false) {
                    $0.sender = .realMouse
                },
                ExperimentVariant(id: "E2-M0", title: "物理鼠标 sender, 不补齐", note: "与 Mos 现状的字段组合最接近: 175-178 保持为空", needsVirtualTrackpad: false) {
                    $0.sender = .realMouse; $0.fillRawFields = false
                },
                ExperimentVariant(id: "E2-Z", title: "sender 为 0", note: "镜像按普通鼠标读取 NSEvent 位移", needsVirtualTrackpad: false) {
                    $0.sender = .zero
                },
                ExperimentVariant(id: "E2-T", title: "内置触控板 sender + 补齐", note: "借用实体触控板的身份, 仅在有内置或实体触控板时有效", needsVirtualTrackpad: false) {
                    $0.sender = .builtinTrackpad
                },
            ]),
        Experiment(
            id: "E3",
            title: "触控板类 sender 盲测",
            question: "虚拟妙控板 sender 与内置触控板 sender 的手感差异是否真实存在。E1-N 与 E2-V 配置完全相同, 但 2026-10-12 的评价不同, 说明单次评价含有较大的偶然差异",
            procedure: "X 与 Y 交替各试 3 次以上, 每次都做单格、慢速、快速往复三种滚动, 记录哪一个更跟手、哪一个出现跳变, 全部记录完成后再点揭晓",
            reading: "多次交替后仍能稳定区分: 差异来自 sender 指向的设备。无法稳定区分: 两者等价, 2a 按设备可用性选择 sender",
            variants: [
                ExperimentVariant(id: "E3-V", title: "虚拟妙控板 sender + 补齐", note: "", needsVirtualTrackpad: true) { _ in },
                // 两个变体都保留虚拟妙控板, 只有 sender 不同; 切换时不经历设备重建, 避免重建期间 sender 为 0 的帧混入
                ExperimentVariant(id: "E3-T", title: "内置触控板 sender + 补齐", note: "", needsVirtualTrackpad: true) {
                    $0.sender = .builtinTrackpad
                },
            ],
            blind: true),
    ]
}

final class ExperimentState: ObservableObject {
    static let shared = ExperimentState()
    @Published var active: String?
    @Published var autoRecord = true
    @Published var results: [String] = []
    @Published var revealed = false
    /// 盲测变体编号到显示名 (X / Y) 的随机对应
    let blindNames: [String: String] = {
        var names: [String: String] = [:]
        for experiment in Experiment.all where experiment.blind {
            for (variant, name) in zip(experiment.variants.shuffled(), ["X", "Y", "Z"]) { names[variant.id] = "\(experiment.id)-\(name)" }
        }
        return names
    }()

    func displayName(_ id: String) -> String { revealed ? id : (blindNames[id] ?? id) }

    func reveal() {
        revealed = true
        let mapping = blindNames.sorted { $0.value < $1.value }.map { "\($0.value) = \($0.key)" }.joined(separator: ", ")
        results.append("[揭晓] \(mapping)")
        Recorder.shared.note("[揭晓] \(mapping)")
    }

    func apply(_ variant: ExperimentVariant, store: ConfigStore) {
        var next = LabConfig()
        let current = store.config
        next.scope = current.scope
        next.monitor = current.monitor
        next.diagnostics = current.diagnostics
        next.evidenceRoot = current.evidenceRoot
        next.recordNSEvent = current.recordNSEvent
        Experiment.baseline(&next)
        variant.apply(&next)
        if !variant.needsVirtualTrackpad { VirtualMagicTrackpad.shared.destroy() }
        ScrollEngine.shared.resetGestureState()
        store.config = next
        active = variant.id
        if autoRecord {
            Recorder.shared.start(label: blindNames[variant.id] ?? variant.id, cfg: next)
            // 虚拟设备在报文流结束后异步释放, 延迟重拍服务快照, 让 services.json 反映设备是否已消失
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Recorder.shared.snapshotServices() }
        }
    }

    func addResult(_ text: String) {
        guard let id = active, !text.isEmpty else { return }
        let line = "[\(displayName(id))] \(text)"
        results.append(line)
        Recorder.shared.note(line)
    }
}

struct ExperimentSection: View {
    @EnvironmentObject private var store: ConfigStore
    @ObservedObject private var state = ExperimentState.shared
    @State private var observation = ""

    var body: some View {
        Section {
            Toggle("切换变体时自动开始新记录轮次", isOn: $state.autoRecord)
                .desc("开启后每次套用变体都会结束当前轮次, 以变体编号开始新轮次, 证据写入研究目录的 evidence/<日期>/lab/")
            ForEach(Experiment.all) { experiment in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(experiment.id) \(experiment.title)").font(.headline)
                    Text("问题: \(experiment.question)").font(.caption)
                    Text("步骤: \(experiment.procedure)").font(.caption).foregroundStyle(.secondary)
                    Text("判读: \(experiment.reading)").font(.caption).foregroundStyle(.secondary)
                    ForEach(experiment.variants.sorted { state.displayName($0.id) < state.displayName($1.id) }) { variant in
                        let hidden = experiment.blind && !state.revealed
                        HStack(alignment: .firstTextBaseline) {
                            Button(state.displayName(variant.id)) { state.apply(variant, store: store) }
                                .buttonStyle(.borderedProminent)
                                .tint(state.active == variant.id ? .accentColor : .gray)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(hidden ? "盲测变体, 揭晓后显示内容" : variant.title)
                                if !variant.note.isEmpty { Text(variant.note).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if experiment.blind {
                        Button(state.revealed ? "已揭晓" : "揭晓对应关系") { state.reveal() }.disabled(state.revealed)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前变体: \(state.active.map(state.displayName) ?? "未选择")  记录: \(Recorder.shared.state.get().recording ? Recorder.shared.state.get().label : "未记录")")
                    if state.revealed || !(state.active.map { state.blindNames[$0] != nil } ?? false) {
                        Text("虚拟妙控板: \(VirtualMagicTrackpad.shared.status)  sender \(VirtualMagicTrackpad.serviceIDs.get().sorted())")
                    }
                    Text("物理鼠标 sender: \(Lab.lastMouseSender.get())  内置触控板 sender: \(MultitouchSender.id.map(String.init) ?? "无")")
                }
                .font(.caption).monospacedDigit()
            }
            HStack {
                TextField("本变体的观察 (例如: 滑行约半屏, 与 E1-N 相同)", text: $observation)
                Button("记录观察") { state.addResult(observation); observation = "" }
                    .disabled(observation.isEmpty || state.active == nil)
            }
            if !state.results.isEmpty {
                Text(state.results.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button("复制全部观察") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.results.joined(separator: "\n"), forType: .string)
                    }
                    Button("清空观察") { state.results = [] }
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("实验")
                Text("每个变体以已知可用的 phased 配置为基线, 只改变一个变量。观察同时写入当前轮次的 notes.txt").font(.caption).foregroundStyle(.secondary).textCase(nil)
            }
        }
    }
}
