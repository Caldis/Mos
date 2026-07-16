//
//  GlowMetalView.swift
//  Mos
//  窗口背景光晕的 Metal 渲染视图: uber-shader 按 GlowParams.effectId 分发 22 种效果
//  Created by Caldis on 2026/7/11. Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import MetalKit

// 与 shader 中的 Uniforms 保持内存布局一致 (12 float + 6 float4 + 2 float2)
private struct GlowUniforms {
    var time: Float = 0
    var intensity: Float = 0
    var margin: Float = 0
    var cornerRadius: Float = 0
    var falloffScale: Float = 0
    var rimStrength: Float = 0
    var hueOffset: Float = 0
    var satScale: Float = 0
    var baseScale: Float = 0
    var effectId: Float = 0
    var preview: Float = 0
    var pad0: Float = 0
    var palA = SIMD4<Float>(0, 0, 0, 0)
    var palB = SIMD4<Float>(0, 0, 0, 0)
    var palC = SIMD4<Float>(0, 0, 0, 0)
    var palD = SIMD4<Float>(0, 0, 0, 0)
    var slotsA = SIMD4<Float>(0, 0, 0, 0)
    var slotsB = SIMD4<Float>(0, 0, 0, 0)
    var rectHalf = SIMD2<Float>(0, 0)
    var center = SIMD2<Float>(0, 0)
}

class GlowMetalView: MTKView, MTKViewDelegate {

    // 光晕效果库 shader (配方源头: ChatGPT Atlas BackgroundShimmer 逆向 + 法术/粒子特效扩展)
    // 运行时编译, 避免构建依赖 Xcode 的 Metal Toolchain 组件
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float time; float intensity; float margin; float cornerRadius;
        float falloffScale; float rimStrength; float hueOffset; float satScale;
        float baseScale; float effectId; float preview; float pad0;
        float4 palA; float4 palB; float4 palC; float4 palD;
        float4 slotsA; float4 slotsB;
        float2 rectHalf; float2 center;
    };

    constant float TAU = 6.28318530718;

    // 圆角矩形有向距离场 (via https://iquilezles.org/articles/distfunctions2d/)
    static float sdRoundBox(float2 p, float2 b, float r) {
        float2 q = abs(p) - b + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }
    static float hash11(float x) {
        return fract(sin(x * 127.1) * 43758.5453);
    }
    static float hash21(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }
    static float vnoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash21(i), hash21(i + float2(1.0, 0.0)), f.x),
                   mix(hash21(i + float2(0.0, 1.0)), hash21(i + float2(1.0, 1.0)), f.x), f.y);
    }
    static float fbm(float2 p) {
        float v = 0.0, a = 0.5;
        for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
        return v;
    }
    // 余弦调色板 (via https://iquilezles.org/articles/palettes/)
    static float3 pal(float x, constant Uniforms& u) {
        return u.palA.xyz * u.baseScale
             + u.palB.xyz * u.satScale * cos(TAU * (u.palC.xyz * (x + u.hueOffset) + u.palD.xyz));
    }

    vertex float4 glow_vertex(uint vid [[vertex_id]]) {
        // 覆盖全屏的单三角形
        const float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        return float4(pos[vid], 0.0, 1.0);
    }

    fragment float4 glow_fragment(float4 pos [[position]],
                                  constant Uniforms& u [[buffer(0)]]) {
        float2 p = pos.xy - u.center;
        float d = sdRoundBox(p, u.rectHalf, u.cornerRadius);
        float dd = max(d, 0.0);
        float ang = atan2(p.y, p.x);
        float t = u.time;
        float m = u.margin;
        float s0 = u.slotsA.x, s1 = u.slotsA.y, s2 = u.slotsA.z, s3 = u.slotsA.w;
        float s4 = u.slotsB.x;

        float fall = exp(-dd / max(m * u.falloffScale, 1.0));
        float edgeFade = 1.0 - smoothstep(m * 0.7, m * 0.98, dd);
        float rim = smoothstep(2.5, 0.0, abs(d)) * u.rimStrength;

        float3 c = float3(0.0);
        float extraA = 0.0; // 暗影类效果的额外遮罩 alpha
        int fx = int(u.effectId + 0.5);

        if (fx == 0) {
            // 极光流转: 极角调色板旋转 + fbm 扭曲 + 波瓣起伏 (Atlas 原配方增强)
            float warp = (fbm(p * 0.004 + float2(t * 0.055, -t * 0.04)) - 0.5) * s3;
            float bands = 1.0 - s2 + s2 * sin(ang * s0 + t * s1);
            c = pal(ang / TAU + t * s4 + warp * 0.4, u) * fall * bands;
        } else if (fx == 1) {
            // 烛焰摇曳: 上升噪声流 + 暖光闪烁
            float n = fbm(float2(p.x * 0.02, p.y * 0.02 + t * s0));
            float flick = 1.0 - s2 + s2 * sin(t * s1 + n * 6.0);
            c = pal(n * 0.35, u) * fall * flick * (0.55 + 0.6 * n);
        } else if (fx == 2) {
            // 魔法余烬: 网格粒子上升 + 明暗闪烁
            float2 gp = p * s0 + float2(0.0, t * s1);
            float2 cell = floor(gp);
            float h = hash21(cell);
            float2 f = fract(gp) - 0.5;
            float2 off = (float2(hash21(cell + 7.3), hash21(cell + 3.1)) - 0.5) * 0.7;
            float spark = smoothstep(s2, 0.0, length(f - off)) * step(1.0 - s3, h);
            float tw = 0.55 + 0.45 * sin(t * 3.0 + h * TAU);
            c = pal(h * 0.25, u) * spark * tw * fall * 2.2 + pal(0.05, u) * fall * 0.22;
        } else if (fx == 3) {
            // 符文脉冲: 两道错相扩散光环 + 底光
            float ph1 = fract(t * s0), ph2 = fract(t * s0 + 0.5);
            float ring1 = exp(-abs(dd - ph1 * m * 0.9) / max(m * s1, 1.0)) * (1.0 - ph1);
            float ring2 = exp(-abs(dd - ph2 * m * 0.9) / max(m * s1, 1.0)) * (1.0 - ph2);
            c = pal(0.75 + 0.06 * sin(ang * 2.0 + t * 0.4), u)
                * ((ring1 + ring2) * 1.5 + s2 * fall * 0.5);
        } else if (fx == 4) {
            // 奥术电弧: 沿边缘游走的折线电丝 + 高频闪烁
            float jag = fbm(float2(ang * s0 + 13.7, t * s1));
            float radius = m * (0.12 + 0.5 * jag);
            float line = exp(-abs(dd - radius) / max(s2 * 2.0, 1.0));
            float flick = 0.6 + 0.4 * sin(t * 17.0 + jag * 9.0);
            c = pal(0.6 + jag * 0.2, u) * (line * flick * 1.8 + s3 * fall * 0.6);
        } else if (fx == 5) {
            // 星尘环绕: N 颗彗星沿边缘轨道环绕, 拖出渐隐尾迹
            float b = fract(ang / TAU * s0 - t * s1 * s0);
            float trail = exp(-b * s3);
            float radial = exp(-abs(dd - m * 0.18) / max(m * s2 * 0.5, 1.0));
            float tw = 0.8 + 0.2 * sin(t * 7.0 + ang * 20.0);
            c = pal(ang / TAU + t * 0.05, u) * trail * radial * tw * 1.8;
        } else if (fx == 6) {
            // 深海呼吸: 慢呼吸 + 焦散状嵌套噪声
            float w = fbm(p * 0.01 + t * 0.05);
            float caustic = fbm(p * 0.008 + w * 1.5);
            float breath = 0.7 + 0.3 * sin(t * s0);
            c = pal(0.5 + caustic * 0.2, u) * fall * breath * (0.5 + s1 * caustic);
        } else if (fx == 7) {
            // 冰晶辉光: 冷色微光 + 随机星点闪烁
            float sp = step(1.0 - s0 * 0.01, hash21(floor(pos.xy / 3.0) + floor(t * s1)));
            float shimmer = 1.0 - s2 + s2 * sin(t * 0.8 + fbm(p * 0.01) * 8.0);
            c = pal(0.55, u) * fall * shimmer + float3(0.9, 0.95, 1.0) * sp * fall * 1.8;
        } else if (fx == 8) {
            // 翡翠毒雾: 双层域扭曲涡旋雾
            float2 q = p * 0.006;
            float w1 = fbm(q + t * s1 * 0.2);
            float w2 = fbm(q + w1 * s0 + t * s1 * 0.1);
            c = pal(w2 * 0.5, u) * fall * (0.35 + 0.85 * w2);
        } else if (fx == 9) {
            // 落日熔金: 底部偏置的熔融流动
            float field = fbm(float2(p.x * 0.008, p.y * 0.008 - t * s0 * 0.3));
            float bias = 0.5 + 0.5 * clamp(p.y / (u.rectHalf.y + m), -1.0, 1.0);
            c = pal(0.08 + field * 0.3, u) * fall
                * (0.25 + 0.9 * mix(1.0, bias, s1) * (0.4 + 0.6 * field));
        } else if (fx == 10) {
            // 虹彩涟漪: 自窗口边缘扩散的干涉波纹, 波峰驱动色散
            float w = 0.5 + 0.5 * sin(dd * s0 - t * s1);
            c = pal(w * s2, u) * fall * (0.35 + 0.65 * w);
        } else if (fx == 11) {
            // 暗影吞噬: 深色卷须蠕动, 以 alpha 遮罩吞噬背景
            float w1 = fbm(p * 0.008 + float2(0.0, t * s2 * 0.3));
            float tend = fbm(p * 0.010 + w1 * s0 + float2(t * s2 * 0.2, 0.0));
            c = pal(0.85, u) * fall * tend * 0.35;
            extraA = tend * fall * s1;
        } else if (fx == 12) {
            // 圣光守护: 缓慢摇曳的放射状光芒
            float rays = pow(max(0.0, 0.5 + 0.5 * sin(ang * s0 + sin(t * s1) * 1.5)), s2);
            c = pal(0.1 + rays * 0.05, u) * fall * (0.3 + 1.2 * rays);
        } else if (fx == 13) {
            // 血月光环: 深红呼吸 + 周期性涌动
            float breath = 0.7 + 0.3 * sin(t * s0);
            float surge = pow(0.5 + 0.5 * sin(t * s1), 6.0) * s2;
            c = pal(0.02 + 0.05 * sin(t * 0.2), u) * fall * (breath + surge);
        } else if (fx == 14) {
            // 量子噪点: 数字块状故障闪烁
            float2 cellpx = floor(pos.xy / float2(max(s0, 1.0), max(s1, 1.0)));
            float rt = floor(t * s2);
            float h = hash21(cellpx + rt * 0.618);
            float mask = step(1.0 - s3, h);
            float hue = step(0.5, hash21(cellpx * 1.7 + rt));
            c = pal(0.15 + hue * 0.5, u) * mask * fall * 1.6;
        } else if (fx == 15) {
            // 凤凰尾焰: 单颗焰体环绕 + 长尾 + 火焰噪声
            float b = fract(ang / TAU - t * s0);
            float trail = exp(-b * s1);
            float flame = 0.5 + 0.5 * fbm(float2(ang * 5.0, dd * 0.03 - t * 1.5));
            float radial = exp(-abs(dd - m * 0.16) / max(m * s2 * 0.5, 1.0));
            c = pal(b * 0.25, u) * trail * flame * radial * 2.4;
        } else if (fx == 16) {
            // 极地磁暴: 垂直光帘摆动起伏
            float cur = fbm(float2(p.x * s0, t * 0.18));
            float sway = sin(p.x * s0 * 3.0 + t * s1);
            c = pal(cur * 0.5 + 0.35, u) * fall * (0.3 + s2 * cur * (0.65 + 0.35 * sway));
        } else if (fx == 17) {
            // 樱瓣飘落: 网格粒子下落 + 逐瓣摇曳
            float2 gp = p * s0 + float2(0.0, -t * s1);
            float2 cell = floor(gp);
            float h = hash21(cell);
            float2 f = fract(gp) - 0.5;
            float sway = sin(t * 0.8 + h * TAU) * s3 * 0.3;
            float2 off = float2((hash21(cell + 7.3) - 0.5) * 0.6 + sway, (hash21(cell + 3.1) - 0.5) * 0.6);
            float petal = smoothstep(s2, 0.0, length(f - off)) * step(0.6, h);
            c = pal(h * 0.15, u) * petal * fall * 1.8 + pal(0.05, u) * fall * 0.25;
        } else if (fx == 18) {
            // 雷云蓄能: 暗涌云层 + 随机闪电照亮
            float cloud = fbm(p * 0.006 + float2(t * s1, 0.0));
            float seed = floor(t * s0);
            float ph = fract(t * s0);
            float gate = step(0.72, hash11(seed));
            float flash = gate * exp(-ph * 9.0) * s2;
            c = pal(0.6 + cloud * 0.15, u) * fall * (0.22 + 0.35 * cloud)
                + float3(1.0) * flash * fall * 0.8;
        } else if (fx == 19) {
            // 彩虹扫掠: 锐利高光沿边缘扫掠 (loading 指示环质感)
            float k = fract(ang / TAU - t * s0);
            float hl = exp(-k * s1);
            c = pal(fract(ang / TAU + t * 0.05), u) * fall * (s2 + hl * 1.6);
        } else if (fx == 20) {
            // 心跳脉冲: lub-dub 双峰节律
            float ph = fract(t * s0);
            float beat = exp(-ph * s1) + 0.55 * exp(-max(ph - 0.18, 0.0) * s1) * step(0.18, ph);
            c = pal(0.02, u) * fall * (0.25 + beat * s2);
        } else if (fx == 21) {
            // 烟花绽放: 随机方位周期性绽放的火花环
            float seed = floor(t * s0);
            float ph = fract(t * s0);
            float a0 = hash11(seed) * TAU;
            float2 q = u.center + float2(cos(a0), sin(a0)) * (u.rectHalf + m * 0.18);
            float r = length(pos.xy - q);
            float br = (0.15 + ph * 0.85) * m * s1;
            float ring = exp(-abs(r - br) / max(m * 0.045, 1.0));
            float sparkleAng = atan2(pos.y - q.y, pos.x - q.x);
            float sp = 0.6 + 0.4 * sin(sparkleAng * s2 + hash11(seed) * 40.0);
            c = pal(hash11(seed + 3.0), u) * ring * sp * pow(1.0 - ph, 1.6) * 2.2
                + pal(0.5, u) * fall * s3;
        }

        // 通用合成: 亮度 → 贴边亮线 → 边界渐隐 → 窗内压暗 → tonemap → premultiplied alpha
        c = c * u.intensity + pal(ang / TAU, u) * rim;
        c *= edgeFade;
        float inside = 1.0 - smoothstep(-1.5, 1.5, d);
        c *= mix(1.0, 0.1, inside);
        c = 1.0 - exp(-c * 1.15);
        float a = max(max(c.r, max(c.g, c.b)), extraA * edgeFade);

        if (u.preview > 0.5) {
            // 预览模式: 合成到不透明深色底
            return float4(float3(0.05, 0.055, 0.075) * (1.0 - a) + c, 1.0);
        }
        return float4(c, a);
    }
    """

    // 每帧绘制前回调, 供控制器校正光晕窗口与宿主窗口的相对位置 (快速拖拽补偿)
    var frameSync: (() -> Void)?
    // 预览模式: 渲染到面板内的不透明视图, 围绕一个虚拟窗口矩形
    private let isPreview: Bool
    // 渲染资源
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    // 时间累积 (受 speed 缩放, 调速时不跳变)
    private var simTime: Float = 0
    private var lastDrawTime: CFTimeInterval = 0

    init?(device: MTLDevice, isPreview: Bool = false) {
        self.isPreview = isPreview
        super.init(frame: .zero, device: device)
        // 编译渲染管线
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            NSLog("GlowMetalView shader compile failed: \\(error)")
            return nil
        }
        guard let queue = device.makeCommandQueue(),
              let vertexFunction = library.makeFunction(name: "glow_vertex"),
              let fragmentFunction = library.makeFunction(name: "glow_fragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        commandQueue = queue
        pipelineState = pipeline
        // 背景配置: 实际光晕透明, 预览不透明
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        layer?.isOpaque = isPreview
        preferredFramesPerSecond = 60
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // 先校正窗口位置再绘制, 保证光晕任何时刻都贴合宿主
        frameSync?()
        guard let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        let params = GlowParams.shared
        // 时间按 speed 累积
        let now = CACurrentMediaTime()
        if lastDrawTime > 0 {
            simTime += Float(min(now - lastDrawTime, 0.1)) * params.speed
        }
        lastDrawTime = now
        // 组装 uniforms
        let scale = Float(window?.backingScaleFactor ?? 2)
        let palette = GlowEffectCatalog.palettes[
            min(max(params.paletteId, 0), GlowEffectCatalog.palettes.count - 1)
        ]
        var uniforms = GlowUniforms()
        uniforms.time = simTime
        uniforms.intensity = params.intensity
        uniforms.cornerRadius = params.cornerRadius * scale
        uniforms.falloffScale = params.falloffScale
        uniforms.rimStrength = params.rimStrength
        uniforms.hueOffset = params.hueOffset
        uniforms.satScale = params.satScale
        uniforms.baseScale = params.baseScale
        uniforms.effectId = Float(params.effectId)
        uniforms.preview = isPreview ? 1 : 0
        uniforms.palA = SIMD4(palette.a, 0)
        uniforms.palB = SIMD4(palette.b, 0)
        uniforms.palC = SIMD4(palette.c, 0)
        uniforms.palD = SIMD4(palette.d, 0)
        uniforms.slotsA = SIMD4(params.slots[0], params.slots[1], params.slots[2], params.slots[3])
        uniforms.slotsB = SIMD4(params.slots[4], params.slots[5], params.slots[6], params.slots[7])
        uniforms.center = SIMD2(Float(drawableSize.width / 2), Float(drawableSize.height / 2))
        if isPreview {
            // 预览: 虚拟窗口矩形 = 视图 bounds 按比例内缩
            let insetPt = Float(min(bounds.width, bounds.height)) * 0.3
            uniforms.margin = insetPt * scale
            uniforms.rectHalf = SIMD2(
                Float(drawableSize.width / 2) - insetPt * scale,
                Float(drawableSize.height / 2) - insetPt * scale
            )
        } else {
            // 实际光晕: 宿主窗口矩形 = 视图 bounds 向内收缩 margin
            uniforms.margin = params.margin * scale
            uniforms.rectHalf = SIMD2(
                Float(drawableSize.width / 2) - params.margin * scale,
                Float(drawableSize.height / 2) - params.margin * scale
            )
        }
        // 绘制全屏三角形
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlowUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        // 系统开启了「减弱动态效果」时, 实际光晕只渲染静态首帧 (预览是显式工具, 不受限)
        if !isPreview && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            isPaused = true
        }
    }

}
