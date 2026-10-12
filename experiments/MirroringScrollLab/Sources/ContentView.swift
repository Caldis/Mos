// 设置窗口。每个控件直接绑定 ConfigStore.config, 修改在下一个事件立即生效

import SwiftUI
import ApplicationServices

struct ContentView: View {
    @EnvironmentObject private var store: ConfigStore

    /// 左栏为配置, 右栏为实时诊断和工具, 修改配置时可以同时看到效果
    var body: some View {
        HSplitView {
            Form {
                StatusSection()
                ExperimentSection()
                presetSection
                captureSection
                outputSection
                if store.config.mode.usesEngine { smoothingSection }
                modeSpecificSection
            }
            .formStyle(.grouped)
            .frame(minWidth: 460, idealWidth: 560)

            Form {
                RecordingSection()
                diagnosticsSection
                if store.config.diagnostics {
                    ChartSection()
                    GestureSection()
                    MonitorSection(enabled: $store.config.monitor)
                }
                toolsSection
            }
            .formStyle(.grouped)
            .frame(minWidth: 520, idealWidth: 680)
        }
    }

    private var presetSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(Preset.all) { preset in
                    VStack(alignment: .leading, spacing: 2) {
                        Button(preset.id) { store.apply(preset); ExperimentState.shared.active = nil }
                        Text(preset.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } header: {
            header("预设", "一键套用一组完整配置。套用时其余选项恢复默认, 只保留生效范围和监视开关")
        }
    }

    private var captureSection: some View {
        Section {
            Toggle("启用处理 (⌃⌥⌘M)", isOn: $store.config.enabled)
                .desc("总开关。关闭后 tap 仍在, 但所有滚动原样放行, 用来对比同一手势处理前后的手感")
            picker("Tap 位置", $store.config.tapLocation)
                .desc("拦截滚动的层级。HID 最靠近硬件, 位于所有其他 tap 之前; Annotated Session 是 Mos 现在使用的层级, 位于最后")
            picker("Tap 插入点", $store.config.tapPlacement)
                .desc("同一层级内与其他 tap 的先后顺序。头部最先收到事件, 尾部在其他应用的 tap 之后收到")
            picker("生效范围", $store.config.scope)
                .desc("只在范围内处理滚动, 范围外原样放行。选全局可以在普通 App 中对照同一设置")
            Toggle("吞掉原始事件", isOn: $store.config.consumeOriginal)
                .desc("开启时原始滚轮事件被丢弃, 只保留本工具的输出; 关闭后原始事件与输出同时到达, 用来检查双份输入")
            Toggle("也处理连续输入 (触控板 / 平滑滚轮)", isOn: $store.config.includeContinuous)
                .desc("默认只处理普通滚轮。开启后真实触控板的滚动也会被处理, 用于验证触控板方向能否翻转")
            Toggle("翻转垂直方向", isOn: $store.config.invertVertical)
                .desc("对应 Mos 的反转方向。原地改写模式下决定是否翻转原事件, 其他模式下翻转输出")
            Toggle("翻转水平方向", isOn: $store.config.invertHorizontal)
                .desc("同上, 作用于横向滚动")
            picker("滚动量来源", $store.config.deltaSource)
                .desc("指数逼近插值读取的位移: 每格固定像素, 或系统加速后的像素。Mos 插值固定使用系统加速后的像素")
            if store.config.deltaSource == .notch {
                SliderRow(title: "每格像素", value: $store.config.stepPx, range: 5...200, unit: "px")
                    .desc("每格滚轮换算成多少像素, 仅用于指数逼近插值")
            }
        } header: {
            header("捕获", "决定在哪一层拦截滚轮, 拦截哪些事件, 以及是否丢弃原始事件")
        }
    }

    private var outputSection: some View {
        Section {
            picker("输出方式", $store.config.mode)
                .desc(modeDescription(store.config.mode))
            if store.config.mode.postsCGEvents {
                picker("投递位置", $store.config.postTarget)
                    .desc("合成事件从哪里进入事件管线。HID tap 位于最底层, iPhone 镜像能收到; postToPid 直投目标进程, 是 Mos 现在的做法")
            }
        } header: {
            header("输出", "把捕获到的滚动转换成什么形式发出")
        }
    }

    private func modeDescription(_ mode: OutputMode) -> String {
        switch mode {
        case .passthrough: return "不做任何处理, 只计数和记录, 作为原始手感的基线"
        case .rewriteInPlace: return "不吞掉也不重投, 直接修改原事件的方向字段后放行。可选择修改哪几组字段, 见下方原地改写设置"
        case .wheelRepost: return "吞掉原始事件, 按插值逐帧发出像素滚动事件, 与 Mos 的平滑滚动方式相同"
        case .phasedScroll: return "逐帧发出带触控板阶段标记 (开始 / 持续 / 结束) 的连续滚动事件, 可借用设备身份并补齐镜像读取的 175-178 字段"
        case .virtualMouse: return "通过 CoreHID 虚拟鼠标发送滚轮报文。系统会对报文再做一次滚轮加速, 不适合比较平滑手感"
        case .magicTrackpad: return "通过伪装成 Magic Trackpad 2 的虚拟设备发送双指滑动, 由系统原生触控板栈生成滚动和惯性"
        case .virtualTouchpad: return "通用数字化仪触控板。系统不把它识别为触控板, 只作为对照保留"
        }
    }

    private var smoothingSection: some View {
        Section {
            Toggle("平滑", isOn: $store.config.smooth)
                .desc("开启时按插值把每格滚动拆成多帧输出; 关闭时每格立即输出一次")
            if store.config.smooth {
                picker("插值模型", $store.config.smoothing)
                    .desc("Mos 插值逐项复刻 Mos 的平滑算法; 指数逼近按给定时长让剩余距离指数衰减")
                if store.config.smoothing == .mos {
                    SliderRow(title: "步长", value: $store.config.mosStep, range: 1...100, step: 0.1, format: "%.1f")
                        .desc("单次输入的最小位移。小于步长的输入会被补足到步长, 对应 Mos 的滚动步长")
                    SliderRow(title: "速度", value: $store.config.mosSpeed, range: 1...10, step: 0.05, format: "%.2f")
                        .desc("位移倍率, 输入位移乘以速度后加入待滚动距离, 对应 Mos 的速度")
                    SliderRow(title: "过渡", value: $store.config.mosDuration, range: 0...5, step: 0.05, format: "%.2f")
                        .desc("数值越大每帧移动的比例越小, 滚动越拖长。每帧比例 = 1 - sqrt(过渡 / 5.2)")
                    SliderRow(title: "死区", value: $store.config.mosDeadZone, range: 0...5, step: 0.1, format: "%.1f")
                        .desc("单帧位移不超过死区时不输出; 剩余距离进入死区后结束本次滚动")
                    HStack {
                        Text("Mos 默认: 步长 33.6, 速度 2.70, 过渡 4.35, 死区 1.0").foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复 Mos 默认") {
                            store.config.mosStep = 33.6; store.config.mosSpeed = 2.7
                            store.config.mosDuration = 4.35; store.config.mosDeadZone = 1
                        }
                    }
                } else {
                    SliderRow(title: "平滑时长", value: $store.config.durationMs, range: 20...800, step: 10, unit: "ms")
                        .desc("一次输入的位移约在该时长内输出 95%")
                }
            }
            Toggle("按时间归一化 (基准 \(Int(store.config.referenceHz)) Hz)", isOn: $store.config.timeNormalize)
                .desc("Mos 的插值比例、平滑滤波、死区和合成惯性衰减都按帧定义, 帧率越高滚动越短越急。开启后按实际帧间隔换算到基准帧率, 不同刷新率的屏幕得到相同的时间曲线; 关闭时与 Mos 现状一致")
            if store.config.timeNormalize {
                SliderRow(title: "基准帧率", value: $store.config.referenceHz, range: 30...240, step: 10, unit: "Hz")
                    .desc("该帧率下的手感与未归一化时完全相同; 默认 60 Hz, 对应 Mos 参数调校时的常见刷新率")
            }
            picker("帧时钟", $store.config.frameClock)
                .desc("驱动每帧输出的时钟。CVDisplayLink 与 Mos 实现相同, 回调与屏幕刷新同步; NSScreen.displayLink 是苹果推荐的替代方案, 绑定镜像窗口所在屏幕; DispatchSourceTimer 按固定间隔自走, 不与刷新对齐")
            if store.config.frameClock == .dispatchTimer {
                Toggle("帧率跟随显示器 (\(Int(maxDisplayHz())) Hz)", isOn: $store.config.followDisplayHz)
                    .desc("DispatchSourceTimer 的间隔取最高显示器刷新率; 关闭后使用下方固定帧率")
            }
            if store.config.frameClock == .dispatchTimer && !store.config.followDisplayHz {
                SliderRow(title: "帧率", value: $store.config.frameHz, range: 30...240, step: 10, unit: "Hz")
                    .desc("每秒输出的帧数")
            }
            SliderRow(title: "手势结束等待", value: $store.config.endGraceMs, range: 0...400, step: 10, unit: "ms")
                .desc("输出结束后再等待多久才发送手势结束或抬起手指。连续快速滚动时, 等待期内的新输入会并入同一个手势")
        } header: {
            header("平滑", "把离散的滚轮格转换成逐帧位移")
        }
    }

    @ViewBuilder
    private var modeSpecificSection: some View {
        switch store.config.mode {
        case .rewriteInPlace:
            Section {
                Toggle("改写公开位移 (11 / 93 / 96)", isOn: $store.config.rewritePublic)
                    .desc("普通 App 读取的行位移、定点位移和像素位移。Mos 的反转方向只改写这一组")
                Toggle("改写原始与加速位移 (175-178)", isOn: $store.config.rewriteRaw)
                    .desc("事件带非零 sender 时, iPhone 镜像只读取这四个字段。用来验证 #762 是否只是字段遗漏")
                Toggle("翻转方向标记 (137)", isOn: $store.config.rewriteFlag137)
                    .desc("系统在自然滚动翻转设备位移时置 1, 镜像据此对 175-178 取反。与上一项二选一, 两者同时开启会互相抵消")
            } header: {
                header("原地改写", "选择翻转原事件时修改哪几组字段, 只在翻转方向开启时生效")
            }
        case .wheelRepost:
            Section {
                Toggle("标记为连续滚动 (IsContinuous, Mos 始终开启)", isOn: $store.config.repostContinuous)
                    .desc("开启时系统按像素平滑滚动处理每一帧; 关闭后每一帧被当作一格滚轮, 平滑失效")
            } header: {
                header("滚轮重投", "吞掉后重投模式的事件字段")
            }
        case .phasedScroll:
            Section {
                picker("距离表达", $store.config.distance)
                    .desc("增量大小: 每帧位移写进事件。事件个数: 每满一段距离发一个固定增量的事件, 对应 phone-harness 的结论")
                if store.config.distance == .count {
                    SliderRow(title: "每个事件代表", value: $store.config.ptPerEvent, range: 1...30, unit: "pt")
                        .desc("事件个数模式下, 累积多少像素发一个持续事件")
                }
                Toggle("手势开始前发送预备事件 (MayBegin, 128)", isOn: $store.config.mayBegin)
                    .desc("每次手势的 Began 之前先发一个零位移的预备事件, 模仿手指刚放上触控板")
                Toggle("新手势前发送打断信号 (惯性结束 + 预备 + 取消)", isOn: $store.config.resetBeforeGesture)
                    .desc("每次手势开始前先发惯性结束、预备、取消三个事件, 停止接收方的惯性滑行并清除卡住的手势状态。与上一项同时开启时, 打断信号在前, 预备事件在后。虚拟妙控板模式共用同一个开关")
                picker("惯性", $store.config.momentum)
                    .desc("不发: 手势结束后由接收方自行决定是否惯性滚动。合成: 按衰减系数补发惯性事件")
                if store.config.momentum == .synthetic {
                    SliderRow(title: "每帧衰减", value: $store.config.momentumDecay, range: 0.80...0.99, step: 0.005, format: "%.3f")
                        .desc("惯性速度每帧乘以该系数, 越接近 1 滑行越远")
                    SliderRow(title: "停止阈值", value: $store.config.momentumMinPx, range: 0.1...5, step: 0.1, format: "%.1f", unit: "px")
                        .desc("惯性单帧位移低于该值时结束")
                    SliderRow(title: "惯性交接阈值", value: $store.config.momentumHandoffPx, range: 0...10, step: 0.5, format: "%.1f", unit: "px")
                        .desc("插值末段的单帧位移开始下降且低于该值时, 立即发送 Ended 并以这一帧的速度起步惯性, 跳过插值收尾和手势结束等待, 衔接处速度连续。0 表示关闭: 插值结束并经过手势结束等待后, 以最后一帧速度起步惯性")
                }
                picker("Sender (字段 87)", $store.config.sender)
                    .desc("事件声明的来源设备。镜像按它查找设备属性, 为 0 时读取 NSEvent 位移并按普通鼠标处理。必须是系统中真实存在的服务, 否则事件会被丢弃")
                Toggle("补齐原始与加速位移 (175-178)", isOn: $store.config.fillRawFields)
                    .desc("sender 非零时镜像只读取这四个字段。开启后每帧按下面两个倍率写入")
                if store.config.fillRawFields {
                    SliderRow(title: "加速位移倍率", value: $store.config.accelScale, range: -4...4, step: 0.05, format: "%.2f")
                        .desc("176 / 175 = 每帧位移 × 倍率。可在监视区对照真实触控板的 accY176 与 pt 标定")
                    SliderRow(title: "原始位移倍率", value: $store.config.rawScale, range: -4...4, step: 0.05, format: "%.2f")
                        .desc("178 / 177 = 每帧位移 × 倍率。镜像把它四舍五入成 -128...127 的整数, 过小的值会变成 0")
                }
                Toggle("附带横轴 -1 抖动 (仿真实触控板)", isOn: $store.config.crossAxisJitter)
                    .desc("真实双指滚动总带一点横向分量, phone-harness 为保真加入; 对结果的影响未知")
                Toggle("附带手势伴随事件 (type 29)", isOn: $store.config.gestureCompanion)
                    .desc("真实触控板每个滚动事件都伴随一个手势事件, Mac Mouse Fix 也这样合成")
                Toggle("标记自身事件 (UserData)", isOn: $store.config.markOwnEvents)
                    .desc("在事件上写标记, 让本工具的 tap 识别并跳过自己的输出。关闭可能造成自我循环")
            } header: {
                header("触控板式 phased 参数", "合成触控板事件的字段与时序")
            }
        case .virtualMouse:
            Section {
                SliderRow(title: "每个滚轮单位", value: $store.config.pxPerWheelUnit, range: 1...60, unit: "px")
                    .desc("每帧位移累积到多少像素发一个滚轮单位。系统随后会再加速, 实际位移远大于该值")
                Toggle("手势开始前发送指针微动", isOn: $store.config.pointerNudge)
                    .desc("先让虚拟鼠标左右移动 1 像素, 让光标下的窗口收到指针进入事件")
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    LabeledContent("设备状态", value: VirtualMouse.shared.status)
                }
            } header: {
                header("虚拟 HID 鼠标", "CoreHID 虚拟鼠标的输出参数")
            }
        case .magicTrackpad:
            Section {
                SliderRow(title: "手指位移倍率", value: $store.config.magicScale, range: 0.5...20, step: 0.5, format: "%.1f")
                    .desc("每像素滚动量对应的手指位移, 单位是触控板坐标 (纵向满行程 5206)。系统还会对手指位移加速")
                SliderRow(title: "落指静止帧", value: $store.config.magicSettleFrames, range: 0...12)
                    .desc("手指落下后先静止的帧数, 期间的位移延后补上。用于排查驱动把快速落指识别为取消的问题")
                Toggle("翻转横向手指方向", isOn: $store.config.magicFlipHorizontal)
                    .desc("横向滚动 (如 MX Master 拇指轮) 会转换为手指左右移动。若镜像内横向方向与预期相反, 打开此项")
                Toggle("触摸期间每帧上报 (静止时重复当前位置)", isOn: $store.config.magicKeepAlive)
                    .desc("真实触控板在手指接触期间持续上报。关闭后只在有位移的帧上报")
                Toggle("新手势前发送打断信号 (惯性结束 + 预备 + 取消)", isOn: $store.config.resetBeforeGesture)
                    .desc("每次落指前先以虚拟妙控板的 sender 发送惯性结束、预备、取消三个 CGEvent, 用于打断 iPhone 端仍在进行的惯性滑行。与 phased 模式共用同一个开关")
                SliderRow(title: "提前抬指阈值", value: $store.config.magicLiftPx, range: 0...10, step: 0.5, format: "%.1f", unit: "px")
                    .desc("插值末段的单帧位移开始下降且低于该值时立即抬指, 系统按手指当前速度生成惯性, 曲线上可以看到系统惯性帧。0 表示关闭: 插值全部输出并经过手势结束等待后再抬指, 此时手指已静止, 系统通常不生成惯性")
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    LabeledContent("设备状态", value: VirtualMagicTrackpad.shared.status)
                }
            } header: {
                header("虚拟妙控板", "伪装 Magic Trackpad 2 的手指动作参数。抬指后的惯性由系统按抬指时的手指速度生成")
            }
        case .virtualTouchpad:
            Section {
                SliderRow(title: "手指位移倍率", value: $store.config.touchpadScale, range: 0.5...20, step: 0.5, format: "%.1f")
                    .desc("每像素滚动量对应的手指位移, 单位是数字化仪坐标 (满行程 4095)")
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    LabeledContent("设备状态", value: VirtualTouchpad.shared.status)
                }
            } header: {
                header("虚拟 HID 触控板", "通用数字化仪触控板的参数")
            }
        case .passthrough:
            EmptyView()
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Toggle("诊断 (曲线 / 会话 / 日志 / 状态刷新)", isOn: $store.config.diagnostics)
                .desc("关闭后不再记录采样、会话和事件日志, 曲线与列表停止重绘, 状态区停止刷新。用于测试滚动在没有诊断开销时的最高性能")
        } header: {
            Text("诊断")
        }
    }

    private var toolsSection: some View {
        Section {
            HStack {
                Button("复位手势状态 (⌃⌥⌘R)") { ScrollEngine.shared.resetGestureState() }
                Button("重建 Tap") { TapController.shared.reinstall() }
                Button("清零计数") { Lab.stats.set(LabStats()); Trace.gestures.set([]) }
                Button("重建虚拟妙控板") { VirtualMagicTrackpad.shared.recreate() }
            }
            .desc("复位: 结束进行中的手势和惯性。重建 Tap: 授权后或 tap 异常时重新挂载。清零: 清空计数和会话列表。重建妙控板: 销毁并重新创建虚拟设备, 驱动会重新握手")
            HStack {
                Button("退出 Mos") { MosApp.running.forEach { $0.terminate() } }
                Button("打开辅助功能设置") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("恢复默认") { store.config = LabConfig() }
            }
            .desc("退出 Mos: 避免 Mos 与本工具叠加处理。辅助功能: 创建 tap 需要该权限。恢复默认: 所有选项回到初始值")
        } header: {
            header("工具", "常用操作")
        }
    }

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary).textCase(nil)
        }
    }

    private func picker<T: CaseIterable & Identifiable & Hashable & LabeledOption>(_ title: String, _ binding: Binding<T>) -> some View
    where T.AllCases: RandomAccessCollection {
        Picker(title, selection: binding) {
            ForEach(T.allCases) { Text($0.label).tag($0) }
        }
    }
}

extension View {
    /// 在控件下方显示一行说明
    func desc(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            self
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

protocol LabeledOption { var label: String { get } }
extension TapLocation: LabeledOption {}
extension TapPlacement: LabeledOption {}
extension Scope: LabeledOption {}
extension OutputMode: LabeledOption {}
extension PostTarget: LabeledOption {}
extension DeltaSource: LabeledOption {}
extension DistanceEncoding: LabeledOption {}
extension SmoothingModel: LabeledOption {}
extension FrameClockKind: LabeledOption {}
extension MomentumMode: LabeledOption {}
extension SenderMode: LabeledOption {}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format = "%.0f"
    var unit = ""

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range, step: step)
            Text(String(format: format, value) + unit)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
    }
}

struct StatusSection: View {
    @EnvironmentObject private var store: ConfigStore

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: store.config.diagnostics ? 0.3 : 3600)) { _ in
                let m = MirroringLocator.shared.state.get()
                let s = Lab.stats.get()
                let mos = MosApp.running
                VStack(alignment: .leading, spacing: 4) {
                    row("辅助功能", AXIsProcessTrusted() ? "已授权" : "未授权 (Tap 无法创建)", ok: AXIsProcessTrusted())
                    row("Event Tap", TapController.shared.statusText.get(), ok: TapController.shared.active.get())
                    row("iPhone 镜像", m.rect.map { "窗口 \(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))\(m.frontmost ? ", 前台" : "")" } ?? "未找到窗口", ok: m.rect != nil)
                    row("帧时钟", Lab.clockSummary.get(), ok: true)
                    row("Mos", mos.isEmpty ? "未运行" : "运行中, 会与本工具叠加处理滚动", ok: mos.isEmpty)
                    row("计数", "捕获 \(s.captured)  吞掉 \(s.consumed)  输出 \(s.emitted)  自身 \(s.ignoredOwn)  范围外 \(s.outOfScope)  Tap 被禁用 \(s.tapReenabled)  报文失败 \(s.dispatchErrors)  丢弃帧 \(s.droppedTicks)", ok: true)
                    row("Sender", "最近触控板 \(Lab.lastTrackpadSender.get())  Multitouch \(MultitouchSender.id.map(String.init) ?? "无")  自身设备 \(Lab.ownSenders.get().sorted())", ok: true)
                }
                .font(.callout)
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("状态")
                Text("权限、tap、镜像窗口与计数。计数含义: 捕获=进入处理的滚动, 吞掉=被丢弃的原始事件, 输出=本工具发出的事件, 自身=tap 看到的本工具输出, 范围外=未在生效范围内").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title).frame(width: 80, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
    }
}

struct MonitorSection: View {
    @Binding var enabled: Bool

    var body: some View {
        Section {
            HStack {
                Toggle("记录", isOn: $enabled)
                Spacer()
                Button("清空") { Lab.monitor.set([]) }
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Lab.monitor.get().joined(separator: "\n"), forType: .string)
                }
            }
            TimelineView(.periodic(from: .now, by: 0.3)) { _ in
                ScrollView {
                    Text(Lab.monitor.get().suffix(60).reversed().joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 260)
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("滚动事件监视")
                Text("tap 看到的全部滚动事件, 最新在上。输入=外部事件, 自身=本工具输出。字段: opt173 惯性选项, inv137 方向翻转标记, accY176 / rawY178 镜像读取的纵向加速与原始位移").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}


private struct RecordingSection: View {
    @EnvironmentObject private var store: ConfigStore
    @State private var label = "M0"
    @State private var note = ""

    var body: some View {
        Section("字段记录") {
            TextField("轮次名称", text: $label)
            TextField("证据根目录（留空使用研究目录）", text: $store.config.evidenceRoot)
            Toggle("同时记录 NSEvent 字段", isOn: $store.config.recordNSEvent)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let state = Recorder.shared.state.get()
                HStack {
                    Button(state.recording ? "停止记录" : "开始记录") {
                        if state.recording { Recorder.shared.stop() }
                        else { Recorder.shared.start(label: label, cfg: store.config) }
                    }
                    Button("打开轮次目录") { Recorder.shared.openRound() }.disabled(state.dir == nil)
                    Text("输入 \(state.captured) · 输出 \(state.emitted)")
                }
                if let problem = state.problem { Text(problem).foregroundStyle(.red) }
            }
            HStack {
                TextField("本轮观察", text: $note)
                Button("添加观察") { Recorder.shared.note(note); note = "" }
                    .disabled(note.isEmpty)
            }
            Text("记录会增加回调开销。Tap 被禁用次数上升时先停止记录；输出计数不代表镜像已接收。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
