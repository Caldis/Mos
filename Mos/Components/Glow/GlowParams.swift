//
//  GlowParams.swift
//  Mos
//  光晕效果参数中心: 所有渲染参数的唯一来源, GlowMetalView 每帧读取, GlowDebugPanel 实时改写
//  Created by Caldis on 2026/7/17. Copyright © 2026 Caldis. All rights reserved.
//

import Foundation

struct GlowParams {

    /// 效果编号 (对应 GlowEffectCatalog.all 下标)
    var effectId: Int = 0
    /// 调色板编号 (对应 GlowEffectCatalog.palettes 下标)
    var paletteId: Int = 0
    /// 整体亮度
    var intensity: Float = 1.3
    /// 全局速度倍率 (缩放所有效果的时间流逝)
    var speed: Float = 1.0
    /// 光晕外扩距离 (pt)
    var margin: Float = 150
    /// 宿主窗口圆角 (pt), 应与实际窗口圆角接近
    var cornerRadius: Float = 14
    /// 色相偏移 (0-1 对应一整圈)
    var hueOffset: Float = 0
    /// 饱和度倍率 (缩放调色板振幅)
    var satScale: Float = 1
    /// 亮度倍率 (缩放调色板基准)
    var baseScale: Float = 1
    /// 衰减长度 (相对 margin 的比例)
    var falloffScale: Float = 0.28
    /// 贴边亮线强度
    var rimStrength: Float = 0.55
    /// 效果私有参数槽 (语义由 GlowEffectCatalog 中各效果的 slot 元数据定义)
    var slots: [Float] = [3, 1.2, 0.35, 0.8, 0.08, 0, 0, 0]

    /// 当前生效参数 (仅主线程读写)
    static var shared = GlowEffectCatalog.all[0].preset

    /// 生成可直接粘贴回代码的 Swift 字面量 (调参后固化用)
    var swiftLiteral: String {
        let slotList = slots.map { String(format: "%.3g", $0) }.joined(separator: ", ")
        return String(
            format: "GlowParams(effectId: %d, paletteId: %d, intensity: %.2f, speed: %.2f, "
                + "margin: %.0f, cornerRadius: %.0f, hueOffset: %.2f, satScale: %.2f, "
                + "baseScale: %.2f, falloffScale: %.2f, rimStrength: %.2f, slots: [%@])",
            effectId, paletteId, intensity, speed,
            margin, cornerRadius, hueOffset, satScale,
            baseScale, falloffScale, rimStrength, slotList
        )
    }

}
