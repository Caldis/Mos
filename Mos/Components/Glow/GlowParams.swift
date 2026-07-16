//
//  GlowParams.swift
//  Mos
//  光晕效果参数中心: 所有渲染参数的唯一来源, GlowMetalView 每帧读取, GlowDebugPanel 实时改写
//  Created by Caldis on 2026/7/17. Copyright © 2026 Caldis. All rights reserved.
//

import Foundation

struct GlowParams {

    /// 整体亮度
    var intensity: Float = 1.3
    /// 光晕外扩距离 (pt)
    var margin: Float = 150
    /// 宿主窗口圆角 (pt), 应与实际窗口圆角接近
    var cornerRadius: Float = 14
    /// 色相旋转速度 (圈/秒)
    var hueSpeed: Float = 0.1
    /// 色相全局偏移 (0-1 对应一整圈)
    var palettePhase: Float = 0
    /// 饱和度 (余弦调色板振幅)
    var saturation: Float = 0.46
    /// 基础亮度 (余弦调色板基准)
    var paletteBase: Float = 0.52
    /// 沿边缘的亮度波瓣数量
    var bandCount: Float = 3
    /// 波瓣流动速度 (rad/秒)
    var bandSpeed: Float = 1.2
    /// 波瓣明暗对比 (0 = 无波动)
    var bandContrast: Float = 0.35
    /// 衰减长度 (相对 margin 的比例)
    var falloffScale: Float = 0.28
    /// 贴边亮线强度
    var rimStrength: Float = 0.55

    /// 当前生效参数 (仅主线程读写)
    static var shared = GlowParams()
    /// 出厂默认值
    static let defaults = GlowParams()

    /// 生成可直接粘贴回代码的 Swift 字面量 (调参后固化用)
    var swiftLiteral: String {
        String(
            format: "GlowParams(intensity: %.2f, margin: %.0f, cornerRadius: %.0f, hueSpeed: %.2f, "
                + "palettePhase: %.2f, saturation: %.2f, paletteBase: %.2f, bandCount: %.0f, "
                + "bandSpeed: %.2f, bandContrast: %.2f, falloffScale: %.2f, rimStrength: %.2f)",
            intensity, margin, cornerRadius, hueSpeed,
            palettePhase, saturation, paletteBase, bandCount,
            bandSpeed, bandContrast, falloffScale, rimStrength
        )
    }

}
