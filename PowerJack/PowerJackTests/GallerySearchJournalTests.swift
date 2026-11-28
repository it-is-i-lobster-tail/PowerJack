import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
struct GallerySearchJournalTests {
    private let first = ChartSearchPlan(charts: [.repTotals], total: nil)
    private let next = ChartSearchPlan(charts: [.weeklyMuscleSets], total: .workingSets)

    @Test func keepsEveryVisitAndCompletesOlderPhrases() throws {
        let journal = GallerySearchJournal(inMemory: true)
        let now = Date()
        let words = ["My squat sets", "June bench", "June total", "RIR history", "JUNE   BENCH"]
        for (i, word) in words.enumerated() { journal.record(word, at: now.addingTimeInterval(Double(i))) }
        journal.record("   ")
        let context = try #require(journal.context)
        #expect(try context.fetchCount(FetchDescriptor<GallerySearchVisit>()) == 5)
        #expect(journal.suggestions(for: "") == ["JUNE   BENCH", "RIR history", "June total"])
        #expect(journal.suggestions(for: "SqUAT") == ["My squat sets"])
        #expect(journal.suggestions(for: "june b") == ["JUNE   BENCH"])
    }

    @Test func keepsTheNewestVisitsAndPhrases() throws {
        let journal = GallerySearchJournal(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<205 { journal.record("Search \(i)", at: start.addingTimeInterval(Double(i))) }
        let context = try #require(journal.context)
        let kept = GallerySearchJournal.keptRows
        let visits = try context.fetch(FetchDescriptor<GallerySearchVisit>(sortBy: [SortDescriptor(\.date)]))
        #expect(visits.count == kept)
        #expect(visits.first?.text == "Search 5")
        #expect(visits.last?.text == "Search 204")
        #expect(try context.fetchCount(FetchDescriptor<GallerySearchPhrase>()) == kept)
        #expect(journal.suggestions(for: "") == ["Search 204", "Search 203", "Search 202"])
        #expect(journal.suggestions(for: "Search 4").first == "Search 49", "Search 4 itself rotated out")
        #expect(journal.suggestions(for: "Search 0").isEmpty)
    }

    @Test func oldSavedPlansRotateOut() async throws {
        let journal = GallerySearchJournal(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = await journal.resolve("Old question", now: start) { first }
        for i in 0..<GallerySearchJournal.keptRows { journal.record("Search \(i)", at: start.addingTimeInterval(Double(i + 1))) }
        #expect(journal.cachedPlan("Old question", now: start) == nil)
        // A plan saved now counts as recent, even for a phrase searched long ago.
        _ = await journal.resolve("Search 0", now: start.addingTimeInterval(1_000)) { next }
        journal.record("One more", at: start.addingTimeInterval(1_001))
        #expect(journal.cachedPlan("Search 0", now: start.addingTimeInterval(1_002)) == next)
        #expect(journal.suggestions(for: "Search 1").first == "Search 199")
    }

    @Test func reusesFreshPlansAndRefreshesStalePlans() async throws {
        let journal = GallerySearchJournal(inMemory: true)
        let day = Date(timeIntervalSince1970: 1_000_000)
        let q = "How many sets?"
        var calls = 0
        _ = await journal.resolve(q, now: day) { calls += 1; return first }
        let boundary = day.addingTimeInterval(GallerySearchJournal.lifetime)
        // The same question with different spacing and case reuses the saved plan.
        _ = await journal.resolve("  HOW  MANY sets? ", now: boundary.addingTimeInterval(-1)) { calls += 1; return next }
        #expect(calls == 1)
        #expect(journal.cachedPlan(q, now: boundary.addingTimeInterval(-1)) == first)
        #expect(journal.cachedPlan(q, now: boundary) == nil, "expired")
        // A failed refresh keeps the expired plan rather than losing it.
        struct Unavailable: Error {}
        let failed = await journal.resolve(q, now: boundary) { calls += 1; throw Unavailable() }
        #expect(failed == first)
        // Two searches at once share one model call.
        let jobs = (0..<2).map { _ in Task { @MainActor in
            await journal.resolve(q, now: boundary) { calls += 1; await Task.yield(); return next }
        } }
        for job in jobs { #expect(await job.value == next) }
        #expect(calls == 3)
        #expect(journal.cachedPlan(q, now: boundary) == next)
        #expect(journal.suggestions(for: "").isEmpty, "a saved plan is not a recent search")
    }

    @Test func clearingForgetsRecentSearchesButKeepsSavedPlans() async throws {
        let journal = GallerySearchJournal(inMemory: true)
        for word in ["Bench", "Rows"] { journal.record(word) }
        let plan = ChartSearchPlan(charts: [.estimatedMaxTrend], total: nil)
        _ = await journal.resolve("Bench") { plan }
        journal.clearRecent()
        #expect(journal.suggestions(for: "").isEmpty)
        #expect(journal.cachedPlan("Bench") == plan)
    }

    @Test func emptySearchOffersRecentsAndIdeasAndRunsTheTappedOne() async throws {
        var ran = ""
        var cleared = false
        let screen = try await HostedView(DataSearchStart(recent: ["My old squat question"], ideas: ["Workouts this year"],
                                                          run: { ran = $0 }, clear: { cleared = true }))
        defer { screen.close() }
        #expect(screen.labels.contains("Recent searches"))
        #expect(screen.labels.contains("Try a search"))
        try #require(await screen.tap("My old squat question"))
        #expect(ran == "My old squat question")
        try #require(await screen.tap("Workouts this year"))
        #expect(ran == "Workouts this year")
        try #require(await screen.tap("Clear"))
        #expect(cleared)
    }

}
