//
//  GlowMetalView.swift
//  Mos
//  窗口背景光晕的 Metal 渲染视图
//  Created by Caldis on 2026/7/11. Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import MetalKit

// 与 GlowShader.metal 中的 GlowUniforms 保持内存布局一致
private struct GlowUniforms {
    var time: Float = 0
    var intensity: Float = 0
    var margin: Float = 0
    var cornerRadius: Float = 0
    var rectHalf = SIMD2<Float>(0, 0)
    var center = SIMD2<Float>(0, 0)
}

class GlowMetalView: MTKView, MTKViewDelegate {

    // 光晕 shader (参考 ChatGPT Atlas onboarding 的 BackgroundShimmer 实现)
    // 运行时编译, 避免构建依赖 Xcode 的 Metal Toolchain 组件
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // 与 GlowUniforms 保持内存布局一致
    struct Uniforms {
        float time;         // 秒
        float intensity;    // 整体亮度
        float margin;       // 光晕窗口相对宿主窗口的外扩距离 (设备像素)
        float cornerRadius; // 宿主窗口圆角 (设备像素)
        float2 rectHalf;    // 宿主窗口半宽高 (设备像素)
        float2 center;      // 宿主窗口中心 (设备像素, 光晕窗口坐标系)
    };

    constant float TAU = 6.28318530718;

    // 圆角矩形有向距离场 (via https://iquilezles.org/articles/distfunctions2d/)
    static float sdRoundBox(float2 p, float2 b, float r) {
        float2 q = abs(p) - b + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    // 余弦调色板 (via https://iquilezles.org/articles/palettes/)
    static float3 palette(float t) {
        return 0.52 + 0.46 * cos(TAU * (t + float3(0.0, 0.33, 0.67)));
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
        float t = u.time;

        // 极角驱动调色板缓慢旋转, 沿边缘叠加波动 —— Atlas 配方
        float ang = atan2(p.y, p.x);
        float3 col = palette(ang / TAU + t * 0.03);
        float bands = 0.78 + 0.22 * sin(ang * 3.0 + t * 0.7);

        // 距离衰减, 并在到达光晕窗口边界前平滑归零, 避免出现方形截断
        float falloff = exp(-dd / (u.margin * 0.28));
        float edgeFade = 1.0 - smoothstep(u.margin * 0.7, u.margin * 0.98, dd);
        float rim = smoothstep(2.5, 0.0, abs(d)) * 0.55;

        float glow = falloff * bands * u.intensity;
        float3 c = (col * glow + col * rim) * edgeFade;

        // 宿主窗口覆盖区域内不发光, 省得透过潜在的半透明内容泛色
        float inside = 1.0 - smoothstep(-1.5, 1.5, d);
        c *= mix(1.0, 0.1, inside);

        // 软 tonemap 压高光, 输出 premultiplied alpha
        c = 1.0 - exp(-c * 1.15);
        float a = max(c.r, max(c.g, c.b));
        return float4(c, a);
    }
    """

    // 外观参数
    private let margin: CGFloat
    private let cornerRadius: CGFloat
    private let intensity: CGFloat
    // 渲染资源
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private let startTime = CACurrentMediaTime()

    init?(device: MTLDevice, margin: CGFloat, cornerRadius: CGFloat = 14, intensity: CGFloat = 1.15) {
        self.margin = margin
        self.cornerRadius = cornerRadius
        self.intensity = intensity
        super.init(frame: .zero, device: device)
        // 编译渲染管线
        guard let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
              let vertexFunction = library.makeFunction(name: "glow_vertex"),
              let fragmentFunction = library.makeFunction(name: "glow_fragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        commandQueue = queue
        pipelineState = pipeline
        // 透明背景配置
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        layer?.isOpaque = false
        preferredFramesPerSecond = 60
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        // 计算 uniforms: 宿主窗口矩形 = 视图 bounds 向内收缩 margin
        let scale = window?.backingScaleFactor ?? 2
        var uniforms = GlowUniforms()
        uniforms.time = Float(CACurrentMediaTime() - startTime)
        uniforms.intensity = Float(intensity)
        uniforms.margin = Float(margin * scale)
        uniforms.cornerRadius = Float(cornerRadius * scale)
        uniforms.center = SIMD2(Float(drawableSize.width / 2), Float(drawableSize.height / 2))
        uniforms.rectHalf = SIMD2(
            Float(drawableSize.width / 2 - margin * scale),
            Float(drawableSize.height / 2 - margin * scale)
        )
        // 绘制全屏三角形
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlowUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        // 系统开启了「减弱动态效果」时只渲染静态首帧
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            isPaused = true
        }
    }

}
