import Foundation
import SwiftData
import Testing

@testable import PowerJack

struct HybridStudySearchTests {
    @Test func routesQuestionsWithoutDelayingCompactFilters() {
        for quick in ["", "arms", "legs strength", "upper body volume Oct", "press"] {
            #expect(!StudyQuestionInterpreter.needsModel(quick))
        }
        for question in ["How often do I bench?", "Compare squat and deadlift", "Do I train legs enough"] {
            #expect(StudyQuestionInterpreter.needsModel(question))
        }
    }

    @MainActor @Test func staleModelPlanCannotReplaceLocalMissingEvidence() throws {
        let history = StudyHistory(programs: [], archive: [], logs: [], unit: .pounds)
        let query = "Did better sleep help my bench press?"
        let search = StudySearch(query: query, history: history, exercises: [], index: nil)
        let saved = SavedStudyViews(data: Data())
        let local = try #require(search.galleryCards(history: history, saved: saved).first?.source)
        let plan = StudyQueryPlan(exercises: ["bench press"], filters: "", wholeTraining: false,
                                  charts: [.estimatedStrengthTrend])
        let augmented = try #require(search.questionCards(plan, query: query, history: history,
                                                          exercises: [], saved: saved).first?.source)
        #expect(local.galleryCaption == "Not enough data")
        #expect(augmented.summary == local.summary)
        #expect(augmented.figure == nil)
    }

    @Test func rejectsIncompatibleDenominators() {
        #expect(StudyQueryPlan.missingMeasurement(for: "What percentage of planned workouts did I finish?") != nil)
        #expect(StudyQueryPlan.missingMeasurement(for: "How often did I hit my planned reps?") == nil)
        #expect(StudyQueryPlan.missingMeasurement(for: "Average rest between sets") != nil)
        #expect(StudyQueryPlan.missingMeasurement(for: "Average workout duration") == nil)
    }

    @MainActor @Test func failedGenerationKeepsTheLocalAnswer() async throws {
        let query = "How much time did I spend training in March, in minutes?"
        let h = StudyHistory(programs: [], archive: [], logs: [], unit: .pounds)
        let search = StudySearch(query: query, history: h, exercises: [], index: nil)
        let saved = SavedStudyViews(data: Data())
        var attempts = 0
        for available in [false, true] {
            let plan = try await StudyQuestionInterpreter.interpret(query, available: available) { _ in
                attempts += 1
                return try JSONDecoder().decode(StudyQueryPlan.self, from: Data(#"{"charts":["unknown"]}"#.utf8))
            }
            #expect(plan == nil)
            let local = search.galleryCards(history: h, saved: saved)
            #expect(local.first?.source?.question == query)
        }
        #expect(attempts == 1)
    }

    @Test func everyChartHasOneModelMeasure() {
        let measures = ChartMeasure.allCases.map(\.study)
        #expect(measures.count == TrainingStudy.allCases.count)
        #expect(Set(measures) == Set(TrainingStudy.allCases))
    }

    @MainActor @Test func calendarScopeAndUnobservedPlan() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        let program = UUID()
        let batch = UUID()
        let records = try [(1, 10), (3, 40), (6, 60)].map { month, minutes in
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: 5)))
            var row = HistoryRow(programID: program)
            row.day = month
            row.workoutStatus = "Complete"
            row.workoutStarted = date
            row.workoutEnded = date.addingTimeInterval(Double(minutes) * 60)
            row.workoutSeconds = Double(minutes) * 60
            row.exerciseName = "Bench"
            row.exerciseKey = "bench"
            row.setType = "Working"
            row.setStatus = "Complete"
            row.reps = 5
            return HistoryRecord(row, batchID: batch, savedAt: date, programStarted: date, order: month)
        }
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25)))
        let h = StudyHistory(programs: [], archive: records, logs: [], unit: .pounds, today: today, calendar: calendar)
        let minutes = StudyQuestion("How much time did I spend training in March, in minutes?", history: h)
        #expect(minutes.result(h)?.plottedValues?.rows == [["40"]])
        let day = StudyQuestion("How much time did I spend training on March 4, in minutes?", history: h)
        #expect(day.result(h)?.figure == nil)
        let plan = StudyQuestion("What percentage of planned workouts did I finish?", history: h)
        let result = try #require(plan.result(h))
        #expect(result.figure == nil && result.summary.contains("planned-workout count"))
    }

    #if DEBUG && targetEnvironment(simulator)
    @MainActor @Test func validatesModelPicksAndPreservesRelatedMatches() throws {
        let store = PowerJackStore(inMemory: true)
        let context = store.container.mainContext
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 25)))
        try SimulatorTrainingHistory.populate(in: context, now: date)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let history = StudyHistory(programs: try context.fetch(FetchDescriptor<Program>()),
                                   archive: try HistoryArchive.records(in: context),
                                   logs: try context.fetch(FetchDescriptor<WorkoutLog>()), unit: .pounds, today: date)
        let query = "Is my bench press getting stronger?"
        let search = StudySearch(query: query, history: history, exercises: exercises, index: nil)
        var answer = StudyQueryPlan(exercises: ["bench press"], filters: "", wholeTraining: false,
                                   charts: [.estimatedStrengthTrend])
        func cards() -> [GalleryCard] {
            search.modelCards(answer, query: query, history: history, exercises: exercises, saved: .init(data: Data()))
        }
        #expect(cards().first?.id.study == .legMax)
        #expect(cards().first?.related == false)
        answer.charts = []
        let related = cards()
        #expect(!related.isEmpty && related.allSatisfy { $0.related && $0.source?.figure != nil })
        answer.charts = [.estimatedStrengthTrend]
        answer.timeframe = "August"
        let inventedMonth = cards()
        #expect(inventedMonth.allSatisfy { $0.related })
        answer.timeframe = ""
        answer.grouping = .month
        let wrongGroup = cards()
        #expect(!wrongGroup.contains { !$0.related && $0.id.study == .legMax })
        answer.grouping = .unspecified
        let paraphrase = "Where on the calendar did my bench estimates fluctuate in March?"
        let semantic = StudySearch(query: paraphrase, history: history, exercises: exercises, index: nil)
        let plan = StudyQueryPlan(exercises: ["bench"], filters: "bench March", wholeTraining: false,
                                 charts: [.estimatedStrengthTrend], grouping: .week, timeframe: "March")
        let inferred = semantic.questionCards(plan, query: paraphrase, history: history, exercises: exercises,
                                              saved: .init(data: Data()))
        let chart = try #require(inferred.first?.source)
        #expect(chart.id == .legMax && chart.question == paraphrase)
        let rows = try #require(chart.detail?.rows)
        #expect(!rows.isEmpty && rows.allSatisfy { $0[0].hasPrefix("Mar ") && $0[1] == "Barbell Bench Press" })

        answer.exercises.append("unrecorded comparison lift")
        answer.charts = [.pairedStrengthChanges]
        let ambiguous = cards()
        #expect(ambiguous.allSatisfy { $0.related })
    }
    #endif
}
