import Testing
import Foundation
@testable import ClaudeTakip

@MainActor
@Suite struct UsageCacheStoreCapGuardTests {
    @Test func sessionSnapshotStopsRecordingOnceCapReached() {
        let store = UsageCacheStore(persistToDisk: false)

        // Pre-cap snapshots are recorded
        store.recordSessionSnapshot(usage: 0.5)
        store.recordSessionSnapshot(usage: 0.9)
        store.recordSessionSnapshot(usage: 1.0)  // cap boundary — still recorded
        #expect(store.cache.sessionHistory.count == 3)

        // Post-cap snapshots must be dropped
        store.recordSessionSnapshot(usage: 1.0)
        store.recordSessionSnapshot(usage: 1.0)
        #expect(store.cache.sessionHistory.count == 3, "post-cap snapshots should be dropped")

        // Guard survives value spikes above 1.0 (API occasionally returns >100%)
        store.recordSessionSnapshot(usage: 1.15)
        #expect(store.cache.sessionHistory.count == 3)

        // clearSessionHistory resets the gate — new session starts fresh
        store.clearSessionHistory()
        store.recordSessionSnapshot(usage: 0.1)
        #expect(store.cache.sessionHistory.count == 1)
    }

    @Test func weeklySnapshotStopsRecordingOnceCapReached() {
        let store = UsageCacheStore(persistToDisk: false)

        store.recordWeeklySnapshot(usage: 0.8)
        store.recordWeeklySnapshot(usage: 1.0)
        #expect(store.cache.weeklyHistory.count == 2)

        store.recordWeeklySnapshot(usage: 1.0)
        store.recordWeeklySnapshot(usage: 1.0)
        #expect(store.cache.weeklyHistory.count == 2, "post-cap weekly snapshots should be dropped")
    }

    @Test func sonnetSnapshotStopsRecordingOnceCapReached() {
        let store = UsageCacheStore(persistToDisk: false)

        store.recordSonnetSnapshot(usage: 0.8)
        store.recordSonnetSnapshot(usage: 1.0)
        #expect(store.cache.sonnetHistory.count == 2)

        store.recordSonnetSnapshot(usage: 1.0)
        store.recordSonnetSnapshot(usage: 1.0)
        #expect(store.cache.sonnetHistory.count == 2, "post-cap sonnet snapshots should be dropped")
    }
}

@MainActor
@Suite struct UsageCacheStorePruneTests {
    @Test func pruneDropsSnapshotsOlderThanCutoff() {
        let store = UsageCacheStore(persistToDisk: false)
        store.recordWeeklySnapshot(usage: 0.3)
        store.recordWeeklySnapshot(usage: 0.5)
        #expect(store.cache.weeklyHistory.count == 2)

        // Cutoff in the future → every just-recorded snapshot is older → all dropped
        store.pruneWeeklyHistory(before: Date().addingTimeInterval(3600))
        #expect(store.cache.weeklyHistory.isEmpty)
    }

    @Test func pruneKeepsInWindowSnapshots() {
        let store = UsageCacheStore(persistToDisk: false)
        store.recordWeeklySnapshot(usage: 0.3)
        store.recordWeeklySnapshot(usage: 0.5)

        // Cutoff in the past → nothing is older → all kept (in-window data, including
        // a legitimately capped tail within the active window, must survive)
        store.pruneWeeklyHistory(before: Date().addingTimeInterval(-3600))
        #expect(store.cache.weeklyHistory.count == 2)
    }

    /// Regression for the empty-weekly-chart bug: a capped tail freezes recording,
    /// and when the app is closed across a reset that frozen, out-of-window entry
    /// survives — so the chart stays permanently empty. Pruning the stale cap at
    /// the next poll must lift the freeze and let recording resume.
    @Test func pruningStaleCappedTailUnfreezesRecording() {
        let store = UsageCacheStore(persistToDisk: false)

        // Hit the cap in the previous window — recording freezes
        store.recordWeeklySnapshot(usage: 1.0)
        store.recordWeeklySnapshot(usage: 0.4)  // dropped by cap guard
        #expect(store.cache.weeklyHistory.count == 1)

        // New window starts: the stale capped entry falls outside it and is pruned
        store.pruneWeeklyHistory(before: Date().addingTimeInterval(3600))
        #expect(store.cache.weeklyHistory.isEmpty)

        // Recording must resume now that the frozen tail is gone
        store.recordWeeklySnapshot(usage: 0.2)
        #expect(store.cache.weeklyHistory.count == 1, "recording should resume after stale cap is pruned")
    }

    @Test func pruneSessionHistoryDropsStaleEntries() {
        let store = UsageCacheStore(persistToDisk: false)
        store.recordSessionSnapshot(usage: 0.2)
        store.pruneSessionHistory(before: Date().addingTimeInterval(3600))
        #expect(store.cache.sessionHistory.isEmpty)
    }
}
