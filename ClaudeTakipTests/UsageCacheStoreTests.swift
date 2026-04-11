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
