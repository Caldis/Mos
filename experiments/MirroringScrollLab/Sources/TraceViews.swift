import SwiftUI

/// 最近几秒内的三条泳道: 捕获到的输入, 引擎每帧输出, 在 tap 观测到的自身输出事件
struct ChartSection: View {
    @State private var window: Double = 4
    @State private var paused = false
    @State private var frozen: [Sample] = []

    var body: some View {
        Section {
            HStack {
                Toggle("暂停", isOn: $paused)
                    .onChange(of: paused) { _, on in if on { frozen = Trace.samples.get() } }
                SliderRow(title: "时间窗", value: $window, range: 1...10, step: 0.5, format: "%.1f", unit: "s")
                Button("清空") { Trace.samples.set([]); frozen = [] }
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
                let samples = paused ? frozen : Trace.samples.get()
                let end = paused ? (frozen.last?.t ?? Trace.now()) : Trace.now()
                Canvas { ctx, size in draw(ctx: ctx, size: size, samples: samples, end: end) }
                    .frame(height: 240)
                    .background(Color(nsColor: .textBackgroundColor))
            }
            HStack(spacing: 14) {
                legend(.gray, "输入 (像素)")
                legend(.pink, "横向 (虚线)")
                legend(.blue, "引擎每帧输出")
                legend(.green, "输出事件 pt")
                legend(.orange, "惯性帧")
                legend(.red, "手势开始")
                legend(.purple, "手势结束")
            }
            .font(.caption)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("曲线")
                Text("三条泳道: 输入=捕获到的滚轮位移, 引擎=每帧计算出的输出, 输出事件=系统实际产生的滚动事件。实线为纵向, 粉色虚线为横向。引擎有输出而输出事件为空, 说明输出没有生效").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 8, height: 8); Text(text) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize, samples: [Sample], end: Double) {
        let lanes: [(SampleKind, String)] = [(.input, "输入"), (.engine, "引擎"), (.system, "输出事件")]
        let laneH = size.height / CGFloat(lanes.count)
        let start = end - window
        let visible = samples.filter { $0.t >= start && $0.t <= end }
        func x(_ t: Double) -> CGFloat { CGFloat((t - start) / window) * size.width }

        for (i, lane) in lanes.enumerated() {
            let top = CGFloat(i) * laneH
            let mid = top + laneH / 2
            let points = visible.filter { $0.kind == lane.0 }
            let peak = max(1, points.map { max(abs($0.value), abs($0.x)) }.max() ?? 1)
            var axis = Path(); axis.move(to: CGPoint(x: 0, y: mid)); axis.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(axis, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
            if i > 0 {
                var sep = Path(); sep.move(to: CGPoint(x: 0, y: top)); sep.addLine(to: CGPoint(x: size.width, y: top))
                ctx.stroke(sep, with: .color(.secondary.opacity(0.6)), lineWidth: 0.5)
            }
            ctx.draw(Text("\(lane.1)  峰值 \(Int(peak))  事件 \(points.count)").font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: 6, y: top + 8), anchor: .leading)

            for p in points {
                let px = x(p.t)
                if lane.0 == .system && (p.phase == 1 || p.phase == 4) {
                    var marker = Path(); marker.move(to: CGPoint(x: px, y: top + 2)); marker.addLine(to: CGPoint(x: px, y: top + laneH - 2))
                    ctx.stroke(marker, with: .color(p.phase == 1 ? .red : .purple), lineWidth: 1)
                }
                let scale = laneH / 2 - 14
                // 纵向: 实线, 泳道颜色
                if p.value != 0 {
                    var bar = Path(); bar.move(to: CGPoint(x: px, y: mid)); bar.addLine(to: CGPoint(x: px, y: mid - CGFloat(p.value / peak) * scale))
                    let color: Color = lane.0 == .input ? .gray : lane.0 == .engine ? .blue : (p.momentum != 0 ? .orange : .green)
                    ctx.stroke(bar, with: .color(color), lineWidth: 2)
                }
                // 横向: 虚线, 粉色 (惯性帧为深粉色), 右移 2 像素避免与纵向重叠
                if p.x != 0 {
                    var bar = Path(); bar.move(to: CGPoint(x: px + 2, y: mid)); bar.addLine(to: CGPoint(x: px + 2, y: mid - CGFloat(p.x / peak) * scale))
                    let color: Color = p.momentum != 0 ? Color(red: 0.75, green: 0.1, blue: 0.45) : .pink
                    ctx.stroke(bar, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                }
            }
        }
    }
}

/// 按会话统计的计数; 引擎有输出帧而没有输出事件的会话即为失效
struct GestureSection: View {
    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 0.3)) { _ in
                let records = Array(Trace.gestures.get().suffix(10).reversed())
                VStack(alignment: .leading, spacing: 3) {
                    if records.isEmpty { Text("暂无").foregroundStyle(.secondary) }
                    ForEach(records) { r in
                        HStack {
                            Image(systemName: verdict(r).icon).foregroundStyle(verdict(r).color)
                            Text("#\(r.id)").monospacedDigit().frame(width: 40, alignment: .leading)
                            Text("输入 \(r.inputEvents)  引擎帧 \(r.framesSent)  输出事件 \(r.systemScroll)  惯性 \(r.systemMomentum)  错误 \(r.dispatchErrors)  时长 \(duration(r))")
                                .monospacedDigit()
                            Spacer()
                            Text(verdict(r).text).foregroundStyle(verdict(r).color)
                        }
                        .font(.system(size: 11))
                    }
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("最近会话")
                Text("一次连续滚动记为一个会话。输入=滚轮事件数, 引擎帧=计算出的帧数, 输出事件=系统产生的滚动事件, 惯性=其中的惯性帧, 错误=虚拟设备报文发送失败").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func duration(_ r: GestureRecord) -> String {
        String(format: "%.2fs", (r.end ?? Trace.now()) - r.start)
    }

    private func verdict(_ r: GestureRecord) -> (text: String, icon: String, color: Color) {
        if r.dispatchErrors > 0 { return ("报文发送失败", "xmark.octagon.fill", .red) }
        if r.framesSent == 0 { return ("引擎未输出", "minus.circle", .secondary) }
        if r.systemScroll + r.systemMomentum == 0 {
            return r.end == nil ? ("进行中", "clock", .secondary) : ("无输出事件", "exclamationmark.triangle.fill", .orange)
        }
        return ("正常", "checkmark.circle.fill", .green)
    }
}
