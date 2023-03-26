//
//  ScrollPhase.swift
//  Mos
//
//  Created by Caldis on 2020/12/19.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Cocoa

enum Phase {
    case Idle
    case Contact
    case Tracing
    case Momentum
    case PauseAuto
    case PauseManual
}
enum PhaseItem {
    case Scroll
    case Momentum
}

let PhaseValueMapping: [Phase: [PhaseItem: Double]] = [
    // 空
    Phase.Idle: [PhaseItem.Scroll: 0.0, PhaseItem.Momentum: 0.0],
    // 手指触碰
    Phase.Contact: [PhaseItem.Scroll: 128.0, PhaseItem.Momentum: 0.0],
    // 跟随滚动
    Phase.Tracing: [PhaseItem.Scroll: 2.0, PhaseItem.Momentum: 0.0],
    // 缓动
    Phase.Momentum: [PhaseItem.Scroll: 0.0, PhaseItem.Momentum: 2.0],
    // 缓动停止 (自动, 如缓动到达临界值)
    Phase.PauseAuto: [PhaseItem.Scroll: 0.0, PhaseItem.Momentum: 3.0],
    // 缓动停止 (手动)
    Phase.PauseManual: [PhaseItem.Scroll: 4.0, PhaseItem.Momentum: 0.0],
]

class ScrollPhase {
    
    // 单例
    static let shared = ScrollPhase()
    init() { NSLog("Module initialized: ScrollPhase") }
    
    var phase: Phase = Phase.Idle
    
    // MARK: - 惯性
    // 将状态重设为 Momentun, 通过防抖来延迟其调用, 并向下采样降低防抖开销
    var debounceApplyMomentumCallSamplingRate = 3
    var debounceApplyMomentumCallSamplingCount = 2
    let debouncedApplyMomentum = Utils.debounce(delay: 300) {
        ScrollPhase.shared.phase = Phase.Momentum
        ScrollPhase.shared.debounceApplyMomentumCallSamplingCount = ScrollPhase.shared.debounceApplyMomentumCallSamplingRate - 1
    }
    func applyMomentum() {
        debounceApplyMomentumCallSamplingCount += 1
        if debounceApplyMomentumCallSamplingCount % debounceApplyMomentumCallSamplingRate == 0 {
            debouncedApplyMomentum()
        }
    }
    
    // MARK: - 介入
    // 启动一个新 Phase
    let phaseKickInMapping: [Phase: Phase] = [
        Phase.Idle: Phase.Contact,
        Phase.Momentum: Phase.Contact,
        Phase.PauseAuto: Phase.Contact,
        Phase.PauseManual: Phase.Contact,
        Phase.Tracing: Phase.Tracing
    ]
    func kickIn() {
        // 阶段转换
        if let kickedInPhase = phaseKickInMapping[phase] {
            phase = kickedInPhase
        }
        // 应用惯性
        applyMomentum()
    }
    
    // MARK: - 阶段转换
    // 根据转换表, 将 Phase 扭转为下一个阶段
    let phaseTransfromMapping: [Phase: Phase] = [
        Phase.Contact: Phase.Tracing,
        // Phase.Tracing: Phase.Tracing,
        Phase.PauseAuto: Phase.Idle,
        Phase.PauseManual: Phase.Idle,
    ]
    func transfrom() {
        if let nextPhase = phaseTransfromMapping[phase] {
            phase = nextPhase
        }
    }
    
    // MARK: - 停止
    func stop(_ nextPhase: Phase = Phase.PauseManual) {
        phase = nextPhase
    }

}
