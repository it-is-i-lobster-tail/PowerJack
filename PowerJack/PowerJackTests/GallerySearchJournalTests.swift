import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
struct GallerySearchJournalTests {
    private let first = StudyQueryPlan(exercises: [], filters: "", wholeTraining: true, charts: [.directRepTotals])
    private let next = StudyQueryPlan(exercises: [], filters: "", wholeTraining: true, charts: [.weeklyMuscleCredits])

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

    @Test func reusesFreshIntentsAndRefreshesStaleIntents() async throws {
        let journal = GallerySearchJournal(inMemory: true)
        let day = Date(timeIntervalSince1970: 1_000_000)
        let q = "How many sets?"
        var calls = 0
        _ = await journal.resolve(q, now: day) { _ in calls += 1; return first }
        let boundary = day.addingTimeInterval(GallerySearchJournal.lifetime)
        _ = await journal.resolve("  HOW  MANY sets? ", now: boundary.addingTimeInterval(-1)) { _ in calls += 1; return next }
        #expect(calls == 1)
        #expect(journal.cached(q)?.plan.charts == [.directRepTotals])
        let failed = await journal.resolve(q, now: boundary) { _ in calls += 1; return nil }
        #expect(failed?.charts == [.directRepTotals])
        #expect(journal.cached(q)?.date == day)
        let jobs = (0..<2).map { _ in Task { @MainActor in
            await journal.resolve(q, now: boundary) { _ in calls += 1; await Task.yield(); return next }
        } }
        for job in jobs { #expect(await job.value?.charts == [.weeklyMuscleCredits]) }
        #expect(calls == 3)
        #expect(journal.cached(q)?.date == boundary)
        #expect(journal.suggestions(for: "").isEmpty)
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

    #if targetEnvironment(simulator)
    @Test func absentNamedLiftKeepsItsOwnScopeAndZero() throws {
        let store = PowerJackStore(inMemory: true)
        let context = store.container.mainContext
        let today = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 25)))
        try SimulatorTrainingHistory.populate(in: context, now: today)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let h = StudyHistory(programs: try context.fetch(FetchDescriptor<Program>()), archive: try HistoryArchive.records(in: context),
                             logs: try context.fetch(FetchDescriptor<WorkoutLog>()), unit: .pounds, today: today)
        #expect(StudyQuestion("Did I train on November 24?", history: h).missingHistoryNote(h)?.contains("No workouts were logged") == true)
        #expect(StudyQuestion("In the past 14 days ending today, how many sets?", history: h).missingHistoryNote(h) == nil)
        let query = "How many completed front-squat work sets have I actually logged?"
        let search = StudySearch(query: query, history: h, exercises: exercises, index: nil)
        let q = StudyQuestion(query, history: h, knownNames: search.knownExerciseNames)
        #expect(q.missingHistoryNote(h)?.localizedCaseInsensitiveContains("front squat") == true)
        let result = try #require(search.galleryCards(history: h, saved: .init(data: Data())).first?.source)
        #expect(result.summary.contains("0 matching"))
        for phrase in ["Goblet squat", "calf raises", "deadlift, specifically the Romanian variation"] {
            let parsed = StudyQuestion(phrase, history: h, knownNames: search.knownExerciseNames)
            #expect(!parsed.liftNames.isEmpty)
            #expect(parsed.missingHistoryNote(h) == nil)
            #expect(!parsed.sessions(h).isEmpty)
        }
        #expect(StudyQuestion("Back squats", history: h).missingHistoryNote(h) == nil)
        #expect(StudyQuestion("Back squats on November 24", history: h).missingHistoryNote(h)?.contains("Nov 24") == true)
        #expect(StudyQuestion("Compare front squats with back squats", history: h).missingHistoryNote(h)?.localizedCaseInsensitiveContains("back squat") == false)
    }
    #endif
}
