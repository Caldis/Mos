//
//  GlowEffectCatalog.swift
//  Mos
//  光晕效果目录: 全部效果的名称、私有参数元数据与美学预设, 以及可选调色板
//  效果实现在 GlowMetalView 的 uber-shader 中按 effectId 分发
//  Created by Caldis on 2026/7/17. Copyright © 2026 Caldis. All rights reserved.
//

import Foundation

// 效果私有参数的元数据 (映射到 GlowParams.slots 的对应下标)
struct GlowSlotSpec {
    let name: String
    let min: Float
    let max: Float
    let isInteger: Bool

    init(_ name: String, _ min: Float, _ max: Float, isInteger: Bool = false) {
        self.name = name
        self.min = min
        self.max = max
        self.isInteger = isInteger
    }
}

// 一个效果 = 名称 + 私有参数元数据 + 完整美学预设
struct GlowEffectSpec {
    let name: String
    let slots: [GlowSlotSpec]
    let preset: GlowParams
}

// 余弦调色板 (via https://iquilezles.org/articles/palettes/): color = a + b * cos(TAU * (c * t + d))
struct GlowPalette {
    let name: String
    let a: SIMD3<Float>
    let b: SIMD3<Float>
    let c: SIMD3<Float>
    let d: SIMD3<Float>
}

enum GlowEffectCatalog {

    // MARK: - 调色板

    static let palettes: [GlowPalette] = [
        GlowPalette(name: "虹彩", a: [0.52, 0.52, 0.52], b: [0.46, 0.46, 0.46], c: [1, 1, 1], d: [0.00, 0.33, 0.67]),
        GlowPalette(name: "暖焰", a: [0.56, 0.30, 0.12], b: [0.50, 0.36, 0.20], c: [1, 1, 1], d: [0.00, 0.08, 0.18]),
        GlowPalette(name: "寒霜", a: [0.45, 0.58, 0.70], b: [0.25, 0.30, 0.32], c: [1, 1, 1], d: [0.55, 0.62, 0.72]),
        GlowPalette(name: "翡翠", a: [0.22, 0.46, 0.30], b: [0.26, 0.40, 0.26], c: [1, 1, 1], d: [0.30, 0.40, 0.46]),
        GlowPalette(name: "血月", a: [0.46, 0.10, 0.12], b: [0.42, 0.18, 0.15], c: [1, 1, 1], d: [0.00, 0.05, 0.09]),
        GlowPalette(name: "鎏金", a: [0.58, 0.45, 0.20], b: [0.42, 0.36, 0.22], c: [1, 1, 1], d: [0.02, 0.10, 0.22]),
        GlowPalette(name: "紫夜", a: [0.40, 0.25, 0.55], b: [0.36, 0.28, 0.40], c: [1, 1, 1], d: [0.72, 0.80, 0.92]),
        GlowPalette(name: "碧海", a: [0.16, 0.40, 0.50], b: [0.20, 0.38, 0.42], c: [1, 1, 1], d: [0.45, 0.55, 0.66]),
        GlowPalette(name: "樱粉", a: [0.62, 0.44, 0.52], b: [0.36, 0.26, 0.30], c: [1, 1, 1], d: [0.94, 0.00, 0.06]),
    ]

    // MARK: - 效果目录 (下标即 effectId, 与 shader 中的分发顺序严格一致)

    static let all: [GlowEffectSpec] = [
        // 0
        GlowEffectSpec(
            name: "极光流转",
            slots: [
                GlowSlotSpec("波瓣数量", 1, 8, isInteger: true),
                GlowSlotSpec("波动速度", 0, 4),
                GlowSlotSpec("波动对比", 0, 0.6),
                GlowSlotSpec("扭曲强度", 0, 2),
                GlowSlotSpec("色相转速", 0, 0.5),
            ],
            preset: preset(0, palette: 0, intensity: 1.3, falloff: 0.28, rim: 0.55,
                           slots: [3, 1.2, 0.35, 0.8, 0.08])
        ),
        // 1
        GlowEffectSpec(
            name: "烛焰摇曳",
            slots: [
                GlowSlotSpec("上升速度", 0.1, 3),
                GlowSlotSpec("闪烁频率", 1, 12),
                GlowSlotSpec("闪烁幅度", 0, 0.5),
            ],
            preset: preset(1, palette: 1, intensity: 1.45, falloff: 0.30, rim: 0.40,
                           slots: [0.8, 5, 0.25])
        ),
        // 2
        GlowEffectSpec(
            name: "魔法余烬",
            slots: [
                GlowSlotSpec("颗粒密度", 0.005, 0.05),
                GlowSlotSpec("上升速度", 0.1, 2),
                GlowSlotSpec("颗粒大小", 0.05, 0.35),
                GlowSlotSpec("生成概率", 0.05, 0.5),
            ],
            preset: preset(2, palette: 1, intensity: 1.6, falloff: 0.34, rim: 0.30,
                           slots: [0.02, 0.6, 0.16, 0.28])
        ),
        // 3
        GlowEffectSpec(
            name: "符文脉冲",
            slots: [
                GlowSlotSpec("脉冲频率", 0.1, 2),
                GlowSlotSpec("光环宽度", 0.02, 0.25),
                GlowSlotSpec("底光强度", 0, 1),
            ],
            preset: preset(3, palette: 6, intensity: 1.5, falloff: 0.30, rim: 0.60,
                           slots: [0.5, 0.08, 0.3])
        ),
        // 4
        GlowEffectSpec(
            name: "奥术电弧",
            slots: [
                GlowSlotSpec("折线频率", 1, 10),
                GlowSlotSpec("抖动速度", 0.5, 8),
                GlowSlotSpec("电弧宽度", 1, 8),
                GlowSlotSpec("底光强度", 0, 1),
            ],
            preset: preset(4, palette: 6, intensity: 1.8, falloff: 0.26, rim: 0.35,
                           slots: [4, 3, 3, 0.25])
        ),
        // 5
        GlowEffectSpec(
            name: "星尘环绕",
            slots: [
                GlowSlotSpec("彗星数量", 1, 8, isInteger: true),
                GlowSlotSpec("环绕速度", 0.02, 0.5),
                GlowSlotSpec("轨道宽度", 0.1, 0.8),
                GlowSlotSpec("尾迹长度", 2, 20),
            ],
            preset: preset(5, palette: 0, intensity: 1.7, falloff: 0.30, rim: 0.30,
                           slots: [3, 0.15, 0.35, 6])
        ),
        // 6
        GlowEffectSpec(
            name: "深海呼吸",
            slots: [
                GlowSlotSpec("呼吸频率", 0.1, 2),
                GlowSlotSpec("纹理强度", 0, 1),
            ],
            preset: preset(6, palette: 7, intensity: 1.25, falloff: 0.34, rim: 0.35,
                           slots: [0.5, 0.55])
        ),
        // 7
        GlowEffectSpec(
            name: "冰晶辉光",
            slots: [
                GlowSlotSpec("星点密度", 0, 1),
                GlowSlotSpec("闪烁速率", 1, 10),
                GlowSlotSpec("微光幅度", 0, 0.4),
            ],
            preset: preset(7, palette: 2, intensity: 1.3, falloff: 0.30, rim: 0.50,
                           slots: [0.4, 4, 0.15])
        ),
        // 8
        GlowEffectSpec(
            name: "翡翠毒雾",
            slots: [
                GlowSlotSpec("涡旋强度", 0, 3),
                GlowSlotSpec("流动速度", 0.05, 2),
            ],
            preset: preset(8, palette: 3, intensity: 1.35, falloff: 0.36, rim: 0.30,
                           slots: [1.4, 0.5])
        ),
        // 9
        GlowEffectSpec(
            name: "落日熔金",
            slots: [
                GlowSlotSpec("流动速度", 0.05, 2),
                GlowSlotSpec("重力偏置", 0, 1),
            ],
            preset: preset(9, palette: 5, intensity: 1.5, falloff: 0.32, rim: 0.45,
                           slots: [0.5, 0.8])
        ),
        // 10
        GlowEffectSpec(
            name: "虹彩涟漪",
            slots: [
                GlowSlotSpec("波纹密度", 0.01, 0.15),
                GlowSlotSpec("扩散速度", 0.5, 6),
                GlowSlotSpec("色散幅度", 0, 1),
            ],
            preset: preset(10, palette: 0, intensity: 1.3, falloff: 0.32, rim: 0.40,
                           slots: [0.06, 2.4, 0.35])
        ),
        // 11
        GlowEffectSpec(
            name: "暗影吞噬",
            slots: [
                GlowSlotSpec("卷须扭曲", 0, 3),
                GlowSlotSpec("吞噬浓度", 0, 1),
                GlowSlotSpec("蠕动速度", 0.05, 2),
            ],
            preset: preset(11, palette: 6, intensity: 0.9, falloff: 0.38, rim: 0.20,
                           slots: [1.2, 0.75, 0.5])
        ),
        // 12
        GlowEffectSpec(
            name: "圣光守护",
            slots: [
                GlowSlotSpec("光芒数量", 4, 24, isInteger: true),
                GlowSlotSpec("摇曳速度", 0.05, 2),
                GlowSlotSpec("光芒锐度", 1, 8),
            ],
            preset: preset(12, palette: 5, intensity: 1.5, falloff: 0.30, rim: 0.50,
                           slots: [12, 0.5, 3])
        ),
        // 13
        GlowEffectSpec(
            name: "血月光环",
            slots: [
                GlowSlotSpec("呼吸频率", 0.1, 2),
                GlowSlotSpec("涌动频率", 0.1, 3),
                GlowSlotSpec("涌动强度", 0, 3),
            ],
            preset: preset(13, palette: 4, intensity: 1.4, falloff: 0.32, rim: 0.45,
                           slots: [0.6, 0.9, 1.2])
        ),
        // 14
        GlowEffectSpec(
            name: "量子噪点",
            slots: [
                GlowSlotSpec("块宽", 4, 40),
                GlowSlotSpec("块高", 2, 20),
                GlowSlotSpec("刷新速率", 1, 24),
                GlowSlotSpec("块密度", 0.05, 0.6),
            ],
            preset: preset(14, palette: 6, intensity: 1.5, falloff: 0.26, rim: 0.25,
                           slots: [14, 4, 8, 0.25])
        ),
        // 15
        GlowEffectSpec(
            name: "凤凰尾焰",
            slots: [
                GlowSlotSpec("环绕速度", 0.02, 0.5),
                GlowSlotSpec("尾迹长度", 1, 12),
                GlowSlotSpec("焰体宽度", 0.1, 0.8),
            ],
            preset: preset(15, palette: 1, intensity: 1.9, falloff: 0.30, rim: 0.30,
                           slots: [0.12, 4, 0.3])
        ),
        // 16
        GlowEffectSpec(
            name: "极地磁暴",
            slots: [
                GlowSlotSpec("帘幕密度", 0.004, 0.03),
                GlowSlotSpec("摆动速度", 0.05, 2),
                GlowSlotSpec("起伏对比", 0, 1),
            ],
            preset: preset(16, palette: 3, intensity: 1.35, falloff: 0.34, rim: 0.35,
                           slots: [0.012, 0.7, 0.7])
        ),
        // 17
        GlowEffectSpec(
            name: "樱瓣飘落",
            slots: [
                GlowSlotSpec("花瓣密度", 0.005, 0.04),
                GlowSlotSpec("下落速度", 0.05, 1.5),
                GlowSlotSpec("花瓣大小", 0.05, 0.4),
                GlowSlotSpec("摇曳幅度", 0, 1),
            ],
            preset: preset(17, palette: 8, intensity: 1.4, falloff: 0.34, rim: 0.35,
                           slots: [0.015, 0.35, 0.22, 0.5])
        ),
        // 18
        GlowEffectSpec(
            name: "雷云蓄能",
            slots: [
                GlowSlotSpec("闪电频率", 0.5, 6),
                GlowSlotSpec("云层流速", 0.05, 2),
                GlowSlotSpec("闪光强度", 0.5, 4),
            ],
            preset: preset(18, palette: 7, intensity: 1.2, falloff: 0.34, rim: 0.25,
                           slots: [2.2, 0.4, 2])
        ),
        // 19
        GlowEffectSpec(
            name: "彩虹扫掠",
            slots: [
                GlowSlotSpec("扫掠速度", 0.05, 1),
                GlowSlotSpec("高光锐度", 2, 24),
                GlowSlotSpec("底光强度", 0, 0.6),
            ],
            preset: preset(19, palette: 0, intensity: 1.6, falloff: 0.28, rim: 0.45,
                           slots: [0.35, 9, 0.15])
        ),
        // 20
        GlowEffectSpec(
            name: "心跳脉冲",
            slots: [
                GlowSlotSpec("心率", 0.4, 2.5),
                GlowSlotSpec("收缩锐度", 3, 20),
                GlowSlotSpec("脉冲强度", 0.5, 3),
            ],
            preset: preset(20, palette: 4, intensity: 1.3, falloff: 0.32, rim: 0.40,
                           slots: [1, 9, 1.6])
        ),
        // 21
        GlowEffectSpec(
            name: "烟花绽放",
            slots: [
                GlowSlotSpec("发射频率", 0.2, 2),
                GlowSlotSpec("扩散范围", 0.3, 1.5),
                GlowSlotSpec("火花密度", 6, 40),
                GlowSlotSpec("底光强度", 0, 0.6),
            ],
            preset: preset(21, palette: 0, intensity: 1.7, falloff: 0.30, rim: 0.30,
                           slots: [0.8, 0.9, 18, 0.2])
        ),
    ]

    // MARK: - 预设构造

    private static func preset(
        _ effectId: Int, palette: Int, intensity: Float, falloff: Float, rim: Float,
        speed: Float = 1.0, slots: [Float]
    ) -> GlowParams {
        var params = GlowParams()
        params.effectId = effectId
        params.paletteId = palette
        params.intensity = intensity
        params.speed = speed
        params.falloffScale = falloff
        params.rimStrength = rim
        params.hueOffset = 0
        params.satScale = 1
        params.baseScale = 1
        params.slots = slots + [Float](repeating: 0, count: max(0, 8 - slots.count))
        return params
    }

}
