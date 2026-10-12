//
//  ScrollDispatchContext.swift
//  Mos
//
//  Created by Codex on 2026/3/5.
//

import Cocoa
import os

final class ScrollDispatchContext {

    static let shared = ScrollDispatchContext()

    /// 平滑帧的投递方式
    enum Route {
        /// 改写原始事件副本, CGEventPostToPid 投递到目标进程
        case process
        /// 交给应用适配器的输出端
        case adapter(ScrollOutputSink)

        var sink: ScrollOutputSink? {
            if case .adapter(let sink) = self { return sink }
            return nil
        }
    }

    struct PostingSnapshot {
        let event: CGEvent
        let targetPID: pid_t
        let generation: UInt64
        let capturedAt: CFTimeInterval
        let route: Route
    }

    private struct SnapshotState {
        var eventTemplate: CGEvent?
        var targetPID: pid_t = 0
        var generation: UInt64 = 0
        var updatedAt: CFTimeInterval = 0.0
        var route: Route = .process
        /// 最近一次适配器会话的输出端, 会话上下文清理后仍保留, 用于结束其进行中的手势
        var lastSink: ScrollOutputSink?
    }

    private var state = SnapshotState()
    private var lock = os_unfair_lock_s()
    private let postQueue = DispatchQueue(label: "me.caldis.mos.scrollposter.post", qos: .userInteractive)
    // TTL 仅作为 enqueue 投递时的兜底安全网, 不用于快照创建门控
    // 需覆盖最长惯性减速阶段 (通常 1-3s, 极端 ~5s)
#if DEBUG
    var eventTTL: CFTimeInterval = 5.0
#else
    private let eventTTL: CFTimeInterval = 5.0
#endif

#if DEBUG
    private var postedFrames: UInt64 = 0
    private var droppedFramesByGeneration: UInt64 = 0
    private var droppedFramesByTTL: UInt64 = 0
    private var skippedSyntheticEvents: UInt64 = 0
    private var updateSnapshotFailures: UInt64 = 0
#endif

#if DEBUG
    init() {}
#else
    private init() {}
#endif

    @discardableResult
    func capture(event: CGEvent, route: Route = .process, targetPID: pid_t? = nil) -> Bool {
        guard let template = event.copy() else {
#if DEBUG
            os_unfair_lock_lock(&lock)
            updateSnapshotFailures &+= 1
            os_unfair_lock_unlock(&lock)
#endif
            return false
        }
        // HID 层事件不带目标 pid, 适配器路由由调用方传入
        let pid = targetPID ?? pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        os_unfair_lock_lock(&lock)
        state.eventTemplate = template
        state.targetPID = pid
        state.updatedAt = CFAbsoluteTimeGetCurrent()
        state.route = route
        if let sink = route.sink { state.lastSink = sink }
        os_unfair_lock_unlock(&lock)
        return true
    }

    func advanceGeneration() {
        os_unfair_lock_lock(&lock)
        state.generation &+= 1
        os_unfair_lock_unlock(&lock)
    }

    func clearContext() {
        os_unfair_lock_lock(&lock)
        state.eventTemplate = nil
        state.targetPID = 0
        state.updatedAt = 0.0
        os_unfair_lock_unlock(&lock)
    }

    func invalidateAll() {
        os_unfair_lock_lock(&lock)
        state.generation &+= 1
        state.eventTemplate = nil
        state.targetPID = 0
        state.updatedAt = 0.0
        os_unfair_lock_unlock(&lock)
    }

    func preparePostingSnapshot() -> PostingSnapshot? {
        os_unfair_lock_lock(&lock)
        guard state.targetPID != 0,
              let eventClone = state.eventTemplate?.copy() else {
            os_unfair_lock_unlock(&lock)
            return nil
        }
        let snapshot = PostingSnapshot(event: eventClone, targetPID: state.targetPID, generation: state.generation, capturedAt: state.updatedAt, route: state.route)
        os_unfair_lock_unlock(&lock)
        return snapshot
    }

    func enqueue(_ snapshot: PostingSnapshot) {
        postQueue.async { [self] in
            guard self.isDeliverable(snapshot) else { return }
            // 使用 CGEventPostToPid 直接投递到目标进程:
            // 1. 不依赖 proxy → 无生命周期崩溃 (issue #868)
            // 2. 不经过 session event tap 链路重新路由 → 动量阶段光标移动不会
            //    将滚动事件"带到"其他应用, 始终送达原始滚动目标进程
            // 3. 进程内通过 event.location 做窗口级 hit-testing, 路由到正确窗口
            // 合成事件标记 (eventSourceUserData) 作为防御性旁路保留
            snapshot.event.postToPid(snapshot.targetPID)
            self.recordPostedFrame()
        }
    }

    /// 适配器路由的一帧位移。与 enqueue 使用同一队列与同一套代次/TTL 校验, 保证帧顺序
    func enqueueAdapterFrame(_ snapshot: PostingSnapshot, sink: ScrollOutputSink, y: Double, x: Double) {
        postQueue.async { [self] in
            guard self.isDeliverable(snapshot) else { return }
            sink.frame(y: y, x: x, at: snapshot.event.location)
            self.recordPostedFrame()
        }
    }

    /// 结束最近一次适配器会话的进行中手势。会话结束时代次已经推进, 因此不做代次校验;
    /// 从未使用适配器路由时不入队。
    /// 当前会话为适配器路由时再推进一次代次: 显示链路停止时仍在执行的回调可能已用推进后的代次准备了帧,
    /// 这类帧排在结束请求之后, 会重新打开手势。当前会话已是进程路由时不改代次 (保留其收尾帧), 并释放 lastSink
    func enqueueAdapterEnd() {
        os_unfair_lock_lock(&lock)
        let sink = state.lastSink
        let location = state.eventTemplate?.location
        if state.route.sink != nil {
            state.generation &+= 1
        } else {
            state.lastSink = nil
        }
        os_unfair_lock_unlock(&lock)
        guard let sink = sink else { return }
        postQueue.async {
            sink.end(at: location ?? CGEvent(source: nil)?.location ?? .zero)
        }
    }

    /// 代次与 TTL 校验, 进程路由与适配器路由共用
    private func isDeliverable(_ snapshot: PostingSnapshot) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let validGeneration = snapshot.generation == state.generation
        let validTTL = CFAbsoluteTimeGetCurrent() - snapshot.capturedAt <= eventTTL
#if DEBUG
        if !validGeneration {
            droppedFramesByGeneration &+= 1
        } else if !validTTL {
            droppedFramesByTTL &+= 1
        }
#endif
        return validGeneration && validTTL
    }

    private func recordPostedFrame() {
#if DEBUG
        os_unfair_lock_lock(&lock)
        postedFrames &+= 1
        os_unfair_lock_unlock(&lock)
#endif
    }

#if DEBUG
    func recordSkippedSyntheticEvent() {
        os_unfair_lock_lock(&lock)
        skippedSyntheticEvents &+= 1
        os_unfair_lock_unlock(&lock)
    }

    func diagnosticsSnapshot() -> (postedFrames: UInt64, droppedFramesByGeneration: UInt64, droppedFramesByTTL: UInt64, skippedSyntheticEvents: UInt64, updateSnapshotFailures: UInt64) {
        os_unfair_lock_lock(&lock)
        let snapshot = (
            postedFrames: postedFrames,
            droppedFramesByGeneration: droppedFramesByGeneration,
            droppedFramesByTTL: droppedFramesByTTL,
            skippedSyntheticEvents: skippedSyntheticEvents,
            updateSnapshotFailures: updateSnapshotFailures
        )
        os_unfair_lock_unlock(&lock)
        return snapshot
    }

    func resetDiagnostics() {
        os_unfair_lock_lock(&lock)
        postedFrames = 0
        droppedFramesByGeneration = 0
        droppedFramesByTTL = 0
        skippedSyntheticEvents = 0
        updateSnapshotFailures = 0
        os_unfair_lock_unlock(&lock)
    }
#endif
}
