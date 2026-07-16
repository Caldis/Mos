//
//  GlowEffectCatalog.swift
//  Mos
//  光晕效果目录: 全部效果的名称、私有参数元数据与美学预设, 以及可选调色板
//  设计哲学: 桌面是室内场景, 特效是为窗口做的"灯光设计" (藏光/洗墙/焦散/天光/材质光泽),
//  优雅柔和优先, 避免刺眼的粒子与闪烁; 参考词汇来自建筑照明与摄影布光
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
        // 0-8: 高饱和系 (法术系效果使用)
        GlowPalette(name: "虹彩", a: [0.52, 0.52, 0.52], b: [0.46, 0.46, 0.46], c: [1, 1, 1], d: [0.00, 0.33, 0.67]),
        GlowPalette(name: "暖焰", a: [0.56, 0.30, 0.12], b: [0.50, 0.36, 0.20], c: [1, 1, 1], d: [0.00, 0.08, 0.18]),
        GlowPalette(name: "寒霜", a: [0.45, 0.58, 0.70], b: [0.25, 0.30, 0.32], c: [1, 1, 1], d: [0.55, 0.62, 0.72]),
        GlowPalette(name: "翡翠", a: [0.22, 0.46, 0.30], b: [0.26, 0.40, 0.26], c: [1, 1, 1], d: [0.30, 0.40, 0.46]),
        GlowPalette(name: "血月", a: [0.46, 0.10, 0.12], b: [0.42, 0.18, 0.15], c: [1, 1, 1], d: [0.00, 0.05, 0.09]),
        GlowPalette(name: "鎏金", a: [0.58, 0.45, 0.20], b: [0.42, 0.36, 0.22], c: [1, 1, 1], d: [0.02, 0.10, 0.22]),
        GlowPalette(name: "紫夜", a: [0.40, 0.25, 0.55], b: [0.36, 0.28, 0.40], c: [1, 1, 1], d: [0.72, 0.80, 0.92]),
        GlowPalette(name: "碧海", a: [0.16, 0.40, 0.50], b: [0.20, 0.38, 0.42], c: [1, 1, 1], d: [0.45, 0.55, 0.66]),
        GlowPalette(name: "樱粉", a: [0.62, 0.44, 0.52], b: [0.36, 0.26, 0.30], c: [1, 1, 1], d: [0.94, 0.00, 0.06]),
        // 9-13: 低饱和灯光系 (振幅小, 接近真实室内光源的色温感)
        GlowPalette(name: "暖白", a: [0.58, 0.50, 0.40], b: [0.18, 0.16, 0.12], c: [1, 1, 1], d: [0.00, 0.05, 0.12]),
        GlowPalette(name: "月银", a: [0.48, 0.53, 0.62], b: [0.10, 0.12, 0.16], c: [1, 1, 1], d: [0.55, 0.60, 0.68]),
        GlowPalette(name: "晨雾", a: [0.55, 0.56, 0.58], b: [0.12, 0.12, 0.14], c: [1, 1, 1], d: [0.50, 0.55, 0.60]),
        GlowPalette(name: "琥珀", a: [0.60, 0.44, 0.24], b: [0.25, 0.20, 0.12], c: [1, 1, 1], d: [0.00, 0.06, 0.14]),
        GlowPalette(name: "珍珠", a: [0.58, 0.57, 0.58], b: [0.13, 0.12, 0.15], c: [1, 1, 1], d: [0.00, 0.33, 0.67]),
    ]

    // MARK: - 效果目录 (下标即 effectId, 与 shader 中的分发顺序严格一致)
    // 0-13 灯光设计系: 柔和连续, 低对比, 慢速 —— 室内氛围光
    // 14-19 法术系: 保留的高表现力效果

    static let all: [GlowEffectSpec] = [
        // 0 — 原味 Atlas 复刻 (预设零扭曲, 滑杆保留)
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
                           slots: [3, 1.2, 0.35, 0, 0.08])
        ),
        // 1 — 藏光灯带: 建筑照明的 cove lighting, 均匀暖光 + 极缓漂移
        GlowEffectSpec(
            name: "暖廊灯带",
            slots: [
                GlowSlotSpec("漂移速度", 0.02, 0.5),
                GlowSlotSpec("漂移幅度", 0, 0.4),
                GlowSlotSpec("色温变化", 0, 0.3),
            ],
            preset: preset(1, palette: 9, intensity: 1.2, falloff: 0.32, rim: 0.35,
                           slots: [0.12, 0.15, 0.08])
        ),
        // 2 — 月光: 冷银色, 上方偏置, 近乎静止的微光
        GlowEffectSpec(
            name: "月光浸润",
            slots: [
                GlowSlotSpec("微光幅度", 0, 0.4),
                GlowSlotSpec("微光速度", 0.05, 1),
                GlowSlotSpec("月照偏置", 0, 1),
            ],
            preset: preset(2, palette: 10, intensity: 1.1, falloff: 0.34, rim: 0.40,
                           slots: [0.12, 0.3, 0.6])
        ),
        // 3 — 天光: 色温在冷暖间极缓往复, 底部带地平线暖意
        GlowEffectSpec(
            name: "晨昏天光",
            slots: [
                GlowSlotSpec("昼夜速度", 0.01, 0.3),
                GlowSlotSpec("冷暖跨度", 0, 0.6),
                GlowSlotSpec("地平线暖意", 0, 0.4),
            ],
            preset: preset(3, palette: 0, intensity: 1.15, falloff: 0.32, rim: 0.35,
                           sat: 0.6, hue: 0.5, slots: [0.05, 0.42, 0.15])
        ),
        // 4 — 台灯: 光汇聚于一个方位, 像窗边真的放了一盏灯
        GlowEffectSpec(
            name: "台灯侧光",
            slots: [
                GlowSlotSpec("光源方位", 0, 1),
                GlowSlotSpec("光束集中", 2, 20),
                GlowSlotSpec("呼吸速度", 0.05, 1),
            ],
            preset: preset(4, palette: 12, intensity: 1.3, falloff: 0.32, rim: 0.35,
                           slots: [0.62, 6, 0.25])
        ),
        // 5 — 壁炉: 底部偏置暖光 + 用时间噪声过滤后的平滑火光起伏 (无跳闪)
        GlowEffectSpec(
            name: "壁炉余温",
            slots: [
                GlowSlotSpec("火光起伏", 0, 0.8),
                GlowSlotSpec("起伏速度", 0.1, 2),
                GlowSlotSpec("底部偏置", 0, 1),
            ],
            preset: preset(5, palette: 1, intensity: 1.25, falloff: 0.32, rim: 0.35,
                           sat: 0.8, slots: [0.35, 0.6, 0.7])
        ),
        // 6 — 纱帘: 光透过薄纱的柔和纵向明暗, 随风缓摆
        GlowEffectSpec(
            name: "纱帘光影",
            slots: [
                GlowSlotSpec("帘幕密度", 0.003, 0.02),
                GlowSlotSpec("摆动速度", 0.05, 1.5),
                GlowSlotSpec("明暗对比", 0, 0.8),
            ],
            preset: preset(6, palette: 11, intensity: 1.15, falloff: 0.32, rim: 0.35,
                           slots: [0.008, 0.4, 0.4])
        ),
        // 7 — 百叶: 斜向软条纹极缓漂移, 晨光穿过百叶窗
        GlowEffectSpec(
            name: "百叶晨光",
            slots: [
                GlowSlotSpec("条纹密度", 0.01, 0.1),
                GlowSlotSpec("条纹角度", 0, 0.5),
                GlowSlotSpec("漂移速度", 0.05, 1),
            ],
            preset: preset(7, palette: 9, intensity: 1.25, falloff: 0.30, rim: 0.35,
                           slots: [0.035, 0.08, 0.2])
        ),
        // 8 — 波光: 水面反射到天花板的焦散光带, 上方偏置
        GlowEffectSpec(
            name: "水面波光",
            slots: [
                GlowSlotSpec("波光密度", 0.01, 0.12),
                GlowSlotSpec("扭曲幅度", 0, 2),
                GlowSlotSpec("荡漾速度", 0.1, 2),
            ],
            preset: preset(8, palette: 7, intensity: 1.25, falloff: 0.32, rim: 0.35,
                           sat: 0.8, slots: [0.045, 0.9, 0.5])
        ),
        // 9 — 雨窗: 街灯透过带雨的玻璃, 柔焦光斑缓缓下移
        GlowEffectSpec(
            name: "雨窗漫光",
            slots: [
                GlowSlotSpec("光斑尺度", 0.002, 0.02),
                GlowSlotSpec("下移速度", 0.02, 0.6),
                GlowSlotSpec("斑驳对比", 0, 1.2),
            ],
            preset: preset(9, palette: 10, intensity: 1.15, falloff: 0.34, rim: 0.30,
                           slots: [0.006, 0.12, 0.7])
        ),
        // 10 — 丝绸: 各向异性材质高光沿边缘极缓扫过, 对侧带弱副高光
        GlowEffectSpec(
            name: "丝绸光泽",
            slots: [
                GlowSlotSpec("扫掠速度", 0.01, 0.3),
                GlowSlotSpec("高光收窄", 2, 14),
                GlowSlotSpec("副高光", 0, 1),
            ],
            preset: preset(10, palette: 13, intensity: 1.3, falloff: 0.30, rim: 0.45,
                           slots: [0.06, 6, 0.35])
        ),
        // 11 — 珍珠: 母贝的位置性虹彩, 低饱和, 几乎不动
        GlowEffectSpec(
            name: "珍珠虹彩",
            slots: [
                GlowSlotSpec("流转速度", 0.05, 1),
                GlowSlotSpec("虹彩幅度", 0.1, 1),
            ],
            preset: preset(11, palette: 13, intensity: 1.2, falloff: 0.32, rim: 0.40,
                           slots: [0.3, 0.45])
        ),
        // 12 — 呼吸: 单色亮度的睡眠指示灯式起伏 (Apple 呼吸灯节律)
        GlowEffectSpec(
            name: "呼吸辉光",
            slots: [
                GlowSlotSpec("呼吸频率", 0.05, 0.6),
                GlowSlotSpec("波形柔度", 1, 4),
                GlowSlotSpec("呼吸深度", 0.2, 1.2),
            ],
            preset: preset(12, palette: 7, intensity: 1.15, falloff: 0.32, rim: 0.35,
                           sat: 0.7, slots: [0.16, 1.8, 0.7])
        ),
        // 13 — 雪夜: 冷色底光 + 稀疏柔焦光点极缓飘落 (虚焦雪, 无闪烁)
        GlowEffectSpec(
            name: "雪夜静谧",
            slots: [
                GlowSlotSpec("雪点密度", 0.005, 0.03),
                GlowSlotSpec("飘落速度", 0.02, 0.4),
                GlowSlotSpec("柔焦程度", 0.1, 0.4),
            ],
            preset: preset(13, palette: 10, intensity: 1.15, falloff: 0.32, rim: 0.30,
                           slots: [0.012, 0.1, 0.25])
        ),
        // 14 — 保留: 两道错相扩散光环
        GlowEffectSpec(
            name: "符文脉冲",
            slots: [
                GlowSlotSpec("脉冲频率", 0.1, 2),
                GlowSlotSpec("光环宽度", 0.02, 0.25),
                GlowSlotSpec("底光强度", 0, 1),
            ],
            preset: preset(14, palette: 6, intensity: 1.5, falloff: 0.30, rim: 0.60,
                           slots: [0.5, 0.08, 0.3])
        ),
        // 15 — 保留: 沿边缘游走的电丝
        GlowEffectSpec(
            name: "奥术电弧",
            slots: [
                GlowSlotSpec("折线频率", 1, 10),
                GlowSlotSpec("抖动速度", 0.5, 8),
                GlowSlotSpec("电弧宽度", 1, 8),
                GlowSlotSpec("底光强度", 0, 1),
            ],
            preset: preset(15, palette: 6, intensity: 1.8, falloff: 0.26, rim: 0.35,
                           slots: [4, 3, 3, 0.25])
        ),
        // 16 — 保留: 双层域扭曲涡旋雾
        GlowEffectSpec(
            name: "翡翠毒雾",
            slots: [
                GlowSlotSpec("涡旋强度", 0, 3),
                GlowSlotSpec("流动速度", 0.05, 2),
            ],
            preset: preset(16, palette: 3, intensity: 1.35, falloff: 0.36, rim: 0.30,
                           slots: [1.4, 0.5])
        ),
        // 17 — 保留: 底部偏置的熔融流动
        GlowEffectSpec(
            name: "落日熔金",
            slots: [
                GlowSlotSpec("流动速度", 0.05, 2),
                GlowSlotSpec("重力偏置", 0, 1),
            ],
            preset: preset(17, palette: 5, intensity: 1.5, falloff: 0.32, rim: 0.45,
                           slots: [0.5, 0.8])
        ),
        // 18 — 保留: 深色卷须以 alpha 遮罩吞噬背景
        GlowEffectSpec(
            name: "暗影吞噬",
            slots: [
                GlowSlotSpec("卷须扭曲", 0, 3),
                GlowSlotSpec("吞噬浓度", 0, 1),
                GlowSlotSpec("蠕动速度", 0.05, 2),
            ],
            preset: preset(18, palette: 6, intensity: 0.9, falloff: 0.38, rim: 0.20,
                           slots: [1.2, 0.75, 0.5])
        ),
        // 19 — 保留: 缓慢摇曳的放射状光芒
        GlowEffectSpec(
            name: "圣光守护",
            slots: [
                GlowSlotSpec("光芒数量", 4, 24, isInteger: true),
                GlowSlotSpec("摇曳速度", 0.05, 2),
                GlowSlotSpec("光芒锐度", 1, 8),
            ],
            preset: preset(19, palette: 5, intensity: 1.5, falloff: 0.30, rim: 0.50,
                           slots: [12, 0.5, 3])
        ),
    ]

    // MARK: - 预设构造

    private static func preset(
        _ effectId: Int, palette: Int, intensity: Float, falloff: Float, rim: Float,
        speed: Float = 1.0, sat: Float = 1.0, hue: Float = 0, slots: [Float]
    ) -> GlowParams {
        var params = GlowParams()
        params.effectId = effectId
        params.paletteId = palette
        params.intensity = intensity
        params.speed = speed
        params.falloffScale = falloff
        params.rimStrength = rim
        params.hueOffset = hue
        params.satScale = sat
        params.baseScale = 1
        params.slots = slots + [Float](repeating: 0, count: max(0, 8 - slots.count))
        return params
    }

}
