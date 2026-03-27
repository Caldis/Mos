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

    struct PostingSnapshot {
        let event: CGEvent
        let generation: UInt64
    }

    private struct SnapshotState {
        var eventTemplate: CGEvent?
        var generation: UInt64 = 0
    }

    private var state = SnapshotState()
    private var lock = os_unfair_lock_s()

#if DEBUG
    private var postedFrames: UInt64 = 0
    private var droppedFramesByGeneration: UInt64 = 0
    private var skippedSyntheticEvents: UInt64 = 0
    private var updateSnapshotFailures: UInt64 = 0
#endif

    private init() {}

    @discardableResult
    func capture(event: CGEvent) -> Bool {
        guard let template = event.copy() else {
#if DEBUG
            os_unfair_lock_lock(&lock)
            updateSnapshotFailures &+= 1
            os_unfair_lock_unlock(&lock)
#endif
            return false
        }
        os_unfair_lock_lock(&lock)
        state.eventTemplate = template
        state.generation &+= 1
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
        os_unfair_lock_unlock(&lock)
    }

    func invalidateAll() {
        os_unfair_lock_lock(&lock)
        state.generation &+= 1
        state.eventTemplate = nil
        os_unfair_lock_unlock(&lock)
    }

    func preparePostingSnapshot() -> PostingSnapshot? {
        os_unfair_lock_lock(&lock)
        guard let eventClone = state.eventTemplate?.copy() else {
            os_unfair_lock_unlock(&lock)
            return nil
        }
        let generation = state.generation
        os_unfair_lock_unlock(&lock)
        return PostingSnapshot(event: eventClone, generation: generation)
    }

    func enqueue(_ snapshot: PostingSnapshot) {
        os_unfair_lock_lock(&lock)
        let validGeneration = snapshot.generation == state.generation
        if !validGeneration {
#if DEBUG
            droppedFramesByGeneration &+= 1
#endif
        }
        os_unfair_lock_unlock(&lock)
        guard validGeneration else { return }
        snapshot.event.post(tap: CGEventTapLocation(rawValue: 0)!)
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

    func diagnosticsSnapshot() -> (postedFrames: UInt64, droppedFramesByGeneration: UInt64, skippedSyntheticEvents: UInt64, updateSnapshotFailures: UInt64) {
        os_unfair_lock_lock(&lock)
        let snapshot = (
            postedFrames: postedFrames,
            droppedFramesByGeneration: droppedFramesByGeneration,
            skippedSyntheticEvents: skippedSyntheticEvents,
            updateSnapshotFailures: updateSnapshotFailures
        )
        os_unfair_lock_unlock(&lock)
        return snapshot
    }
#endif
}