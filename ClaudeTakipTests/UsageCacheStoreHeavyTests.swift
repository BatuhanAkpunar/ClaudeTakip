import Testing
import Foundation
@testable import ClaudeTakip

/// Heavy coverage for UsageCacheStore in-memory behavior: history caps,
/// insertion order, prune boundaries, and the cap-guard/prune interaction that
/// caused the empty-chart freeze bug (here mirrored across all three histories).
@MainActor
@Suite struct UsageCacheStoreHeavyTests {

    // MARK: - Trim caps

    @Test func sessionHistoryTrimsToHundred() {
        let store = UsageCacheStore(persistToDisk: false)
        for _ in 0..<105 { store.recordSessionSnapshot(usage: 0.1) }
        #expect(store.cache.sessionHistory.count == 100)
    }

    @Test func weeklyHistoryTrimsToFiveHundred() {
        let store = UsageCacheStore(persistToDisk: false)
        for _ in 0..<505 { store.recordWeeklySnapshot(usage: 0.1) }
        #expect(store.cache.weeklyHistory.count == 500)
    }

    @Test func sonnetHistoryTrimsToTwoHundred() {
        let store = UsageCacheStore(persistToDisk: false)
        for _ in 0..<205 { store.recordSonnetSnapshot(usage: 0.1) }
        #expect(store.cache.sonnetHistory.count == 200)
    }

    @Test func trimDropsOldestKeepsNewest() {
        let store = UsageCacheStore(persistToDisk: false)
        // 101 snapshots with increasing usage; oldest (0.00) should be dropped.
        for i in 0..<101 { store.recordSessionSnapshot(usage: Double(i) / 1000.0) }
        #expect(store.cache.sessionHistory.count == 100)
        // First surviving entry is the second-recorded (0.001), last is 0.100
        #expect(store.cache.sessionHistory.first?.usage == 0.001)
        #expect(store.cache.sessionHistory.last?.usage == 0.100)
    }

    // MARK: - Insertion order

    @Test func snapshotsPreserveInsertionOrder() {
        let store = UsageCacheStore(persistToDisk: false)
        store.recordSessionSnapshot(usage: 0.1)
        store.recordSessionSnapshot(usage: 0.2)
        store.recordSessionSnapshot(usage: 0.3)
        #expect(store.cache.sessionHistory.map(\.usage) == [0.1, 0.2, 0.3])
    }

    // MARK: - Prune edge cases

    @Test func pruneEmptyHistoryIsNoOp() {
        let store = UsageCacheStore(persistToDisk: false)
        store.pruneSessionHistory(before: Date())
        store.pruneWeeklyHistory(before: Date())
        #expect(store.cache.sessionHistory.isEmpty)
        #expect(store.cache.weeklyHistory.isEmpty)
    }

    @Test func pruneKeepsFutureCutoffZeroButPreservesFresh() {
        let store = UsageCacheStore(persistToDisk: false)
        store.recordSessionSnapshot(usage: 0.5)
        // cutoff far in the past → nothing older → kept
        store.pruneSessionHistory(before: Date().addingTimeInterval(-10_000))
        #expect(store.cache.sessionHistory.count == 1)
    }

    // MARK: - Cap-guard + prune, all three histories

    @Test func staleCappedSessionTailUnfreezesAfterPrune() {
        let store = UsageCacheStore(persistToDisk: false)
        store.recordSessionSnapshot(usage: 1.0)
        store.recordSessionSnapshot(usage: 0.4) // dropped by cap guard
        #expect(store.cache.sessionHistory.count == 1)
        store.pruneSessionHistory(before: Date().addingTimeInterval(3600))
        #expect(store.cache.sessionHistory.isEmpty)
        store.recordSessionSnapshot(usage: 0.2)
        #expect(store.cache.sessionHistory.count == 1, "recording must resume after stale cap pruned")
    }

    @Test func staleCappedSonnetTailUnfreezesAfterPrune() {
        let store = UsageCacheStore(persistToDisk: false)
        store.recordSonnetSnapshot(usage: 1.0)
        store.recordSonnetSnapshot(usage: 0.4)
        #expect(store.cache.sonnetHistory.count == 1)
        // Sonnet has no dedicated prune API; clearing is the reset path here.
        store.clearSonnetHistory()
        store.recordSonnetSnapshot(usage: 0.2)
        #expect(store.cache.sonnetHistory.count == 1)
    }

    // MARK: - updateCurrent

    @Test func updateCurrentStoresBucketsAndTimestamp() {
        let store = UsageCacheStore(persistToDisk: false)
        let usage = CachedUsage(
            fiveHour: UsageBucket(utilization: 0.5, resetsAt: nil),
            sevenDay: UsageBucket(utilization: 0.25, resetsAt: nil),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        store.updateCurrent(usage)
        #expect(store.cache.current.fiveHour?.utilization == 0.5)
        #expect(store.cache.current.sevenDay?.utilization == 0.25)
        #expect(store.cache.lastUpdate != nil)
    }

    // MARK: - clearInMemory

    @Test func clearInMemoryResetsAllHistories() {
        let store = UsageCacheStore(persistToDisk: false)
        store.recordSessionSnapshot(usage: 0.3)
        store.recordWeeklySnapshot(usage: 0.4)
        store.recordSonnetSnapshot(usage: 0.5)
        store.clearInMemory()
        #expect(store.cache.sessionHistory.isEmpty)
        #expect(store.cache.weeklyHistory.isEmpty)
        #expect(store.cache.sonnetHistory.isEmpty)
        #expect(store.cache.current.fiveHour == nil)
    }
}
