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
    
    private(set) var phase: Phase = .Idle
    
    // 下一帧发送完毕后自动切换到的阶段
    private var pendingPhaseAfterDelivery: Phase? = nil
    
    // 记录在开始新的 Tracking 前是否需要补发额外阶段 (比如在惯性中断时时补发 MomentumEnd)
    struct TransitionPlan {
        let queue: [(Phase, Phase?)]
        let target: (Phase, Phase?)?
    }
    
    // MARK: - 工具方法
    private func transition(to next: Phase, autoAdvance: Phase? = nil) {
        phase = next
        pendingPhaseAfterDelivery = autoAdvance
    }
    
    private func plan(extra queue: [(Phase, Phase?)] = [], target: (Phase, Phase?)? = nil) -> TransitionPlan {
        return TransitionPlan(queue: queue, target: target)
    }
    
    // MARK: - 对外接口
    func reset() {
        phase = .Idle
        pendingPhaseAfterDelivery = nil
    }
    
    /// 每次检测到鼠标滚轮输入时调用, 根据是否被视为独立滚动返回阶段序列
    func onManualInputDetected(isSeparated: Bool) -> TransitionPlan {
        if phase == .MomentumBegin || phase == .MomentumOngoing {
            return plan(
                extra: [(Phase.MomentumEnd, Phase.Idle)],
                target: (.TrackingBegin, .TrackingOngoing)
            )
        }
        if !isSeparated && (phase == .TrackingBegin || phase == .TrackingOngoing) {
            return plan(target: (.TrackingOngoing, nil))
        }
        return plan(target: (.TrackingBegin, .TrackingOngoing))
    }
    
    /// 在滚轮输入停止后调用, 将阶段切到 TrackingEnd
    func onManualInputEnded() -> TransitionPlan {
        switch phase {
        case .TrackingBegin, .TrackingOngoing:
            return plan(target: (.TrackingEnd, nil))
        default:
            return plan()
        }
    }
    
    /// 在检测到需要进入惯性滚动时调用
    func onMomentumStart() -> TransitionPlan {
        switch phase {
        case .TrackingEnd, .MomentumEnd:
            return plan(target: (.MomentumBegin, .MomentumOngoing))
        case .MomentumBegin:
            return plan(target: (.MomentumOngoing, nil))
        default:
            return plan()
        }
    }
    
    /// 惯性滚动中持续调用, 保持阶段为 MomentumOngoing
    func onMomentumOngoing() -> TransitionPlan {
        switch phase {
        case .MomentumBegin:
            return plan(target: (.MomentumOngoing, nil))
        default:
            return plan()
        }
    }
    
    /// 惯性或滚动停止时调用
    func onMomentumFinish() -> TransitionPlan {
        switch phase {
        case .MomentumBegin, .MomentumOngoing:
            return plan(target: (.MomentumEnd, .Idle))
        case .TrackingBegin, .TrackingOngoing, .TrackingEnd:
            return plan(target: (.TrackingEnd, .Idle))
        default:
            return plan()
        }
    }
    
    /// 在滚动帧发送后调用, 处理自动阶段切换
    func didDeliverFrame() {
        if let nextPhase = pendingPhaseAfterDelivery {
            phase = nextPhase
            pendingPhaseAfterDelivery = nil
        }
    }
    
    /// 直接设置阶段 (用于补发额外帧)
    func apply(phase next: Phase, autoAdvance: Phase? = nil) {
        transition(to: next, autoAdvance: autoAdvance)
    }
}
