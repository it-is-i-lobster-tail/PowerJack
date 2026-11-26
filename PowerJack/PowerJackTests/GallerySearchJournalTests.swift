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

    @Test func focusOffersRecentsAndSelectingAMatchFillsTheField() async throws {
        let journal = GallerySearchJournal(inMemory: true)
        journal.record("My old squat question")
        for word in ["Bench", "Rows", "Calves"] { journal.record(word) }
        var applied = ""
        let screen = try await HostedView(GallerySearchField(journal: journal) { applied = $0 })
        defer { screen.close() }
        #expect(screen.labels.contains("Recent searches"))
        #expect(!screen.labels.contains("My old squat question"))
        try #require(await screen.focusAndType("old squat", into: "Search charts"))
        try #require(await screen.tap("My old squat question"))
        #expect(applied == "My old squat question")
        #expect(journal.suggestions(for: "").first == applied)
    }

}
