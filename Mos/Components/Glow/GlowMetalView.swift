//
//  GlowMetalView.swift
//  Mos
//  窗口背景光晕的 Metal 渲染视图: uber-shader 按 GlowParams.effectId 分发 20 种效果
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

    // 光晕效果库 shader
    // 0-13 灯光设计系 (桌面视为室内场景, 特效是柔和的"灯光"而非刺眼的激光)
    // 14-19 法术系 (保留的高表现力效果)
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
        float2 dir = float2(cos(ang), sin(ang));
        float t = u.time;
        float m = u.margin;
        float s0 = u.slotsA.x, s1 = u.slotsA.y, s2 = u.slotsA.z, s3 = u.slotsA.w;
        float s4 = u.slotsB.x;

        float fall = exp(-dd / max(m * u.falloffScale, 1.0));
        float edgeFade = 1.0 - smoothstep(m * 0.7, m * 0.98, dd);
        float rim = smoothstep(2.5, 0.0, abs(d)) * u.rimStrength;
        // 垂直位置 0(顶) - 1(底), 供带方向性的灯光效果使用
        float vert = clamp(0.5 + 0.5 * p.y / (u.rectHalf.y + m), 0.0, 1.0);

        float3 c = float3(0.0);
        float extraA = 0.0; // 暗影类效果的额外遮罩 alpha
        int fx = int(u.effectId + 0.5);

        if (fx == 0) {
            // 极光流转: 极角调色板旋转 + 波瓣起伏 (Atlas 原味配方, 扭曲默认为零)
            float warp = (fbm(p * 0.004 + float2(t * 0.055, -t * 0.04)) - 0.5) * s3;
            float bands = 1.0 - s2 + s2 * sin(ang * s0 + t * s1);
            c = pal(ang / TAU + t * s4 + warp * 0.4, u) * fall * bands;
        } else if (fx == 1) {
            // 暖廊灯带: 藏光灯带式的均匀暖光, 空间微不均 + 亮度极缓漂移
            float n = fbm(dir * 1.8 + 3.7);
            float drift = 1.0 - s1 + s1 * (0.5 + 0.5 * sin(t * s0 * TAU + n * 5.0));
            c = pal(0.02 + n * s2, u) * fall * (0.72 + 0.28 * n) * drift;
        } else if (fx == 2) {
            // 月光浸润: 冷银色上方偏置, 近乎静止的微光
            float biasTop = 1.0 - vert;
            float bias = mix(1.0, 0.55 + 0.6 * biasTop, s2);
            float shimmer = 1.0 - s0 + s0 * fbm(p * 0.006 + float2(t * s1 * 0.1, 0.0));
            c = pal(0.6, u) * fall * bias * shimmer;
        } else if (fx == 3) {
            // 晨昏天光: 色温在冷暖间极缓往复, 底部带地平线暖意
            float dayPhase = 0.5 + 0.5 * sin(t * s0 * TAU);
            c = pal(dayPhase * s1 + vert * s2, u) * fall * (0.8 + 0.2 * dayPhase);
        } else if (fx == 4) {
            // 台灯侧光: 光汇聚于一个方位, 带极轻微呼吸
            float a0 = s0 * TAU;
            float da = abs(fract((ang - a0) / TAU + 0.5) - 0.5) * 2.0;
            float pool = exp(-da * da * s1);
            float breathe = 0.94 + 0.06 * sin(t * s2 * TAU);
            c = pal(0.03, u) * fall * (0.18 + 1.1 * pool) * breathe;
        } else if (fx == 5) {
            // 壁炉余温: 底部偏置暖光, 时间噪声过滤出的平滑火光起伏
            float flick = fbm(float2(t * s1, 7.7));
            float bias = mix(1.0, 0.35 + 0.85 * vert, s2);
            c = pal(0.04 + 0.06 * flick, u) * fall * bias * (0.78 + s0 * (flick - 0.5));
        } else if (fx == 6) {
            // 纱帘光影: 薄纱透光的纵向柔和明暗, 随风缓摆
            float sway = sin(t * s1 * 0.5) * 2.0;
            float bands = fbm(float2(p.x * s0 + sway, p.y * 0.0015 + t * 0.02));
            c = pal(0.5 + bands * 0.06, u) * fall * (1.0 - s2 * 0.55 + s2 * bands);
        } else if (fx == 7) {
            // 百叶晨光: 斜向软条纹极缓漂移
            float angBlind = s1 * 3.14159;
            float axis = p.x * cos(angBlind) + p.y * sin(angBlind);
            float stripes = smoothstep(0.2, 0.8, 0.5 + 0.5 * sin(axis * s0 + t * s2));
            c = pal(0.06, u) * fall * (0.42 + 0.58 * mix(0.5, stripes, 0.65));
        } else if (fx == 8) {
            // 水面波光: 水面反射的焦散光带, 上方偏置
            float w = fbm(float2(p.x * 0.008, t * 0.15));
            float lines = pow(0.5 + 0.5 * sin(p.y * s0 + w * s1 * 6.0 + t * s2), 3.0);
            c = pal(0.52 + w * 0.05, u) * fall * (0.32 + 0.85 * lines * mix(0.55, 1.0, 1.0 - vert));
        } else if (fx == 9) {
            // 雨窗漫光: 柔焦光斑缓缓下移
            float blotch = fbm(p * s0 + float2(0.0, -t * s1));
            float soft = smoothstep(0.25, 0.85, blotch);
            c = pal(0.5 + blotch * 0.08, u) * fall * (0.35 + s2 * soft);
        } else if (fx == 10) {
            // 丝绸光泽: 各向异性宽高光极缓扫掠 + 对侧弱副高光
            float k = fract(ang / TAU - t * s0);
            float kd = min(k, 1.0 - k);
            float k2 = fract(k + 0.5);
            float kd2 = min(k2, 1.0 - k2);
            float hl = exp(-pow(kd * s1, 2.0));
            float hl2 = exp(-pow(kd2 * s1, 2.0)) * s2;
            c = pal(0.02, u) * fall * (0.35 + hl + hl2);
        } else if (fx == 11) {
            // 珍珠虹彩: 母贝的位置性虹彩, 几乎不动
            float ir = fbm(dir * 1.4 + p * 0.001 + t * s0 * 0.1);
            c = pal(ir * s1, u) * fall * (0.78 + 0.22 * ir);
        } else if (fx == 12) {
            // 呼吸辉光: 睡眠指示灯式的单色亮度起伏
            float ph = fract(t * s0);
            float breath = pow(0.5 - 0.5 * cos(ph * TAU), s1);
            c = pal(0.55, u) * fall * (0.32 + s2 * breath);
        } else if (fx == 13) {
            // 雪夜静谧: 冷色底光 + 稀疏柔焦光点极缓飘落
            float2 gp = p * s0 + float2(0.0, -t * s1);
            float2 cell = floor(gp);
            float h = hash21(cell);
            float2 f = fract(gp) - 0.5;
            float2 off = (float2(hash21(cell + 7.3), hash21(cell + 3.1)) - 0.5) * 0.6;
            float flake = smoothstep(s2, s2 * 0.2, length(f - off)) * smoothstep(0.72, 0.95, h);
            c = pal(0.58, u) * fall * 0.55 + pal(0.62, u) * flake * fall * 0.9;
        } else if (fx == 14) {
            // 符文脉冲: 两道错相扩散光环 + 底光
            float ph1 = fract(t * s0), ph2 = fract(t * s0 + 0.5);
            float ring1 = exp(-abs(dd - ph1 * m * 0.9) / max(m * s1, 1.0)) * (1.0 - ph1);
            float ring2 = exp(-abs(dd - ph2 * m * 0.9) / max(m * s1, 1.0)) * (1.0 - ph2);
            c = pal(0.75 + 0.06 * sin(ang * 2.0 + t * 0.4), u)
                * ((ring1 + ring2) * 1.5 + s2 * fall * 0.5);
        } else if (fx == 15) {
            // 奥术电弧: 沿边缘游走的折线电丝 + 高频闪烁
            float jag = fbm(float2(ang * s0 + 13.7, t * s1));
            float radius = m * (0.12 + 0.5 * jag);
            float line = exp(-abs(dd - radius) / max(s2 * 2.0, 1.0));
            float flick = 0.6 + 0.4 * sin(t * 17.0 + jag * 9.0);
            c = pal(0.6 + jag * 0.2, u) * (line * flick * 1.8 + s3 * fall * 0.6);
        } else if (fx == 16) {
            // 翡翠毒雾: 双层域扭曲涡旋雾
            float2 q = p * 0.006;
            float w1 = fbm(q + t * s1 * 0.2);
            float w2 = fbm(q + w1 * s0 + t * s1 * 0.1);
            c = pal(w2 * 0.5, u) * fall * (0.35 + 0.85 * w2);
        } else if (fx == 17) {
            // 落日熔金: 底部偏置的熔融流动
            float field = fbm(float2(p.x * 0.008, p.y * 0.008 - t * s0 * 0.3));
            c = pal(0.08 + field * 0.3, u) * fall
                * (0.25 + 0.9 * mix(1.0, vert, s1) * (0.4 + 0.6 * field));
        } else if (fx == 18) {
            // 暗影吞噬: 深色卷须蠕动, 以 alpha 遮罩吞噬背景
            float w1 = fbm(p * 0.008 + float2(0.0, t * s2 * 0.3));
            float tend = fbm(p * 0.010 + w1 * s0 + float2(t * s2 * 0.2, 0.0));
            c = pal(0.85, u) * fall * tend * 0.35;
            extraA = tend * fall * s1;
        } else if (fx == 19) {
            // 圣光守护: 缓慢摇曳的放射状光芒
            float rays = pow(max(0.0, 0.5 + 0.5 * sin(ang * s0 + sin(t * s1) * 1.5)), s2);
            c = pal(0.1 + rays * 0.05, u) * fall * (0.3 + 1.2 * rays);
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
