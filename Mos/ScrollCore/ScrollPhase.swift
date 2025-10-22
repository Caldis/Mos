//
//  ScrollPhase.swift
//  Mos
//
//  Created by Caldis on 2020/12/19.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Cocoa

/**
 * Phase 状态机说明 - 基于触控板事件序列
 *
 * 惯性滚动 (快速滑动一次, 离开):
 *  - Hold (Optional, 如果开始移动较慢)
 *  - TrackingBegin
 *  - TrackingOngoing (持续追踪滚动
 *  - TrackingEnd
 *  - MomentumBegin
 *  - MomentumOngoing
 *  - MomentumEnd
 *
 * 惯性连续滚动 (快速滑动连续多次):
 *  - Hold (Optional, 如果开始移动较慢)
 *  - TrackingBegin
 *  - TrackingOngoing (持续追踪滚动
 *  - TrackingEnd
 *  - MomentumBegin
 *  - MomentumOngoing
 *  - MomentumEnd  (第二次滑动开始就会无视惯量立即触发一帧, 然后继续下面
 *  - TrackingBegin
 *  - TrackingOngoing (持续追踪滚动
 *  - TrackingEnd
 *  - MomentumBegin
 *  - MomentumOngoing
 *  - MomentumEnd
 *
 * 惯性滚动煞停 (手指离开后, 在惯性未结束前再次点按):
 *  - Hold (Optional, 如果开始移动较慢)
 *  - TrackingBegin
 *  - TrackingOngoing (持续追踪滚动
 *  - TrackingEnd
 *  - MomentumBegin
 *  - MomentumOngoing
 *  - MomentumEnd (会无视已有的惯量, 在 Hold 前立即触发一帧)
 *  - Hold
 *  - Leave
 *
 * 非惯性滚动 (手指持续移动, 但是离开前不带速度):
 *  - Hold (Optional, 如果开始移动较慢)
 *  - TrackingBegin
 *  - TrackingOngoing (持续追踪滚动
 *  - TrackingEnd
 *
 * 非滚动流程 (手指放下 -> 离开)
 *  - Hold
 *  - Leave
 */

enum Phase {
    case Idle
    case Hold
    case TrackingBegin
    case TrackingOngoing
    case TrackingEnd
    case MomentumBegin
    case MomentumOngoing
    case MomentumEnd
    case Leave
}
enum PhaseItem {
    case Scroll
    case Momentum
}

let PhaseValueMapping: [Phase: [PhaseItem: Double]] = [
    // 空
    Phase.Idle: [PhaseItem.Scroll: 0.0, PhaseItem.Momentum: 0.0],
    // 手指保持: 双指放下不滚动 / 缓动中点按停止
    Phase.Hold: [PhaseItem.Scroll: 128.0, PhaseItem.Momentum: 0.0],
    // 跟随: 首帧
    Phase.TrackingBegin: [PhaseItem.Scroll: 1.0, PhaseItem.Momentum: 0.0],
    // 跟随: 移动过程
    Phase.TrackingOngoing: [PhaseItem.Scroll: 2.0, PhaseItem.Momentum: 0.0],
    // 跟随: 末帧 (这一帧似乎不会带任何 Scroll X/Y 数据
    Phase.TrackingEnd: [PhaseItem.Scroll: 4.0, PhaseItem.Momentum: 0.0],
    // 缓动: 首帧
    Phase.MomentumBegin: [PhaseItem.Scroll: 0.0, PhaseItem.Momentum: 1.0],
    // 缓动: 移动过程
    Phase.MomentumOngoing: [PhaseItem.Scroll: 0.0, PhaseItem.Momentum: 2.0],
    // 缓动: 末帧
    Phase.MomentumEnd: [PhaseItem.Scroll: 0.0, PhaseItem.Momentum: 3.0],
    // 手指离开: 末帧
    Phase.Leave: [PhaseItem.Scroll: 8.0, PhaseItem.Momentum: 0.0],
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
    let debouncedApplyMomentumOngoing = Utils.debounce(delay: 100) {
        ScrollPhase.shared.phase = Phase.MomentumOngoing
        ScrollPhase.shared.debounceApplyMomentumCallSamplingCount = ScrollPhase.shared.debounceApplyMomentumCallSamplingRate - 1
    }
    func applyMomentum() {
        debounceApplyMomentumCallSamplingCount += 1
        if debounceApplyMomentumCallSamplingCount % debounceApplyMomentumCallSamplingRate == 0 {
            debouncedApplyMomentumOngoing()
        }
    }
    
    // MARK: - 介入
    let kickInPhaseTransition: [Phase: Phase] = [
        .Idle: .TrackingBegin,
        .Hold: .TrackingBegin,
        .TrackingBegin: .TrackingOngoing,
        .TrackingOngoing: .TrackingEnd,
        .TrackingEnd: .MomentumBegin,
        .MomentumBegin: .MomentumOngoing,
        .MomentumOngoing: .MomentumEnd,
        .MomentumEnd: .TrackingBegin,
        .Leave: .TrackingBegin,
    ]
    func kickIn() {
        // 阶段转换
        if let nextPhase = kickInPhaseTransition[phase] {
            phase = nextPhase
        }
        // 应用惯性
        applyMomentum()
    }
    
    // MARK: - 转阶段
    let transfromPhaseTransition: [Phase: Phase] = [
        .Idle: .TrackingBegin,
        .Hold: .TrackingBegin,
        .TrackingBegin: .TrackingOngoing,
        .TrackingOngoing: .TrackingEnd,
        .TrackingEnd: .MomentumBegin,
        .MomentumBegin: .MomentumOngoing,
        .MomentumOngoing: .MomentumEnd,
        .MomentumEnd: .TrackingBegin,
        .Leave: .TrackingBegin,
    ]
    func transfrom() {
        if let nextPhase = transfromPhaseTransition[phase] {
            phase = nextPhase
        }
    }
    
    // MARK: - 停止
    func stop(_ nextPhase: Phase = Phase.MomentumEnd) {
        phase = nextPhase
    }

}
