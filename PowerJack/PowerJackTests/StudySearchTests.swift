import Foundation
import SwiftData
import Testing

@testable import PowerJack

@MainActor
struct StudySearchTests {
    @Test("A muscle query changes credits and primary strength filters without changing saved controls")
    func anatomy() throws {
        let history = StudyHistory(programs: [], archive: [], logs: [], unit: .pounds)
        let search = StudySearch(query: "arms", history: history, exercises: [], index: nil)
        let saved = StudyOptions(muscles: [.quads], transpose: true)
        let credits = try #require(search.matches(for: .legWork, saved: saved).first)
        #expect(Set(credits.muscles) == [.biceps, .triceps] && credits.transpose)
        #expect(history.result(for: .legWork, options: credits).displayTitle == "Weekly set credits for arms")
        let sources = try #require(search.matches(for: .gluteSources, saved: saved).first)
        #expect(history.result(for: .gluteSources, options: sources).galleryCaption == "Set credits for arms")
        let trends = try #require(search.matches(for: .legMax, saved: saved).first)
        #expect(history.result(for: .legMax, options: trends).galleryCaption == "Estimated one-rep max trends for arms")
        let sets = try #require(search.matches(for: .frequency, saved: saved).first)
        #expect(history.result(for: .frequency, options: sets).displayTitle == "Working arm sets by weekday")
        var edited = credits
        edited.muscles = [.calves]
        #expect(history.result(for: .legWork, options: edited).displayTitle.contains("calves"))
        #expect(StudySearch(query: "", history: history, exercises: [], index: nil).matches(for: .legWork, saved: saved) == [saved])
    }

    @Test("Calendar, intent and lifting parameters can be combined in questions")
    func filters() throws {
        let date = try #require(Calendar.current.date(from: .init(year: 2026, month: 11, day: 24)))
        let history = StudyHistory(programs: [], archive: [], logs: [], unit: .pounds, today: date)
        func query(_ text: String) -> StudySearch { StudySearch(query: text, history: history, exercises: [], index: nil) }
        let october = query("upper body volume Oct")
        let volume = try #require(october.matches(for: .legWork, saved: .init()).first)
        #expect(volume.period == .month(year: 2026, month: 10))
        #expect(volume.muscles == StudyOptions.upperBody)
        #expect(october.matches(for: .forecast, saved: .init()).isEmpty)
        let neglected = try #require(query("Which muscles have I neglected this month?").matches(for: .recency, saved: .init()).first)
        #expect(Set(neglected.muscles) == Set(Muscle.allCases))
        #expect(neglected.period == .month(year: 2026, month: 11))
        let lower = query("legs strength")
        #expect(lower.matches(for: .frequency, saved: .init()).isEmpty)
        let strength = try #require(lower.matches(for: .legMax, saved: .init()).first)
        #expect(Set(strength.muscles) == Set(StudyHistory.legs))
        let scheme = query("Did I hit 3×5 at 185 lb on Oct 10?")
        let options = try #require(scheme.matches(for: .repeatBench, saved: .init()).first)
        #expect(options.parameters == [.sets: 3, .reps: 5, .load: 1850])
        #expect(options.period == .day(year: 2026, month: 10, day: 10))
        #expect(scheme.matches(for: .duration, saved: .init()).isEmpty)
        #expect(query("Which weekdays get the most working sets?").matches(for: .frequency, saved: .init()).count == 1)
        #expect(query("saxophone wallpaper").matches(for: .legWork, saved: .init()).isEmpty)
    }

    #if DEBUG && targetEnvironment(simulator)
    @Test("Press includes horizontal and vertical presses plus push-ups and excludes pulling movements")
    func pressing() throws {
        let store = PowerJackStore(inMemory: true)
        let context = store.container.mainContext
        let date = try #require(Calendar.current.date(from: .init(year: 2026, month: 11, day: 24)))
        try SimulatorTrainingHistory.populate(in: context, now: date)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let history = StudyHistory(programs: try context.fetch(FetchDescriptor<Program>()),
                                   archive: try HistoryArchive.records(in: context),
                                   logs: try context.fetch(FetchDescriptor<WorkoutLog>()), unit: .pounds, today: date)
        let index = ExerciseChartSearch.Index(exercises.map(ExerciseChartSearch.Document.init), encoder: nil)
        let search = StudySearch(query: "press", history: history, exercises: exercises, index: index)
        let ledger = try #require(search.matches(for: .sessionLedger, saved: .init()).first)
        #expect(ledger.exerciseKeys.contains(StudyHistory.bench))
        #expect(ledger.exerciseKeys.contains("catalog:push-up"))
        #expect(!ledger.exerciseKeys.contains(StudyHistory.squat))
        #expect(!ledger.exerciseKeys.contains(StudyHistory.curl))
        for (question, anchor) in [("bench press progress", "bench"), ("am I getting stronger at squats?", "squat")] {
            let query = StudySearch(query: question, history: history, exercises: exercises, index: index)
            let cards = query.galleryCards(history: history, saved: .init(data: Data()))
            #expect(cards.first?.id.study == .legMax)
            #expect(!cards.isEmpty)
            #expect(cards.allSatisfy { !$0.options.exerciseKeys.isEmpty &&
                $0.options.exerciseKeys.allSatisfy { history.exerciseName(for: $0).lowercased().contains(anchor) } })
        }
        let arms = StudySearch(query: "arms", history: history, exercises: exercises, index: index)
        let options = try #require(arms.matches(for: .legMax, saved: .init()).first)
        guard case .liftPanels(let series) = history.result(for: .legMax, options: options).figure else {
            Issue.record("Expected primary-arm strength series")
            return
        }
        let primaryNames = Set(history.sessions.filter { $0.primary == .biceps || $0.primary == .triceps }.map(\.name))
        #expect(!series.isEmpty && series.allSatisfy { primaryNames.contains($0.name) })
    }
    #endif
}
