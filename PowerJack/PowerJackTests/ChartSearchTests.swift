import Foundation
import Testing

@testable import PowerJack

/// How local search and the language model's plan combine into the gallery.
@MainActor
struct ChartSearchTests {
    let history = ChartSearchFixture.history()
    let saved = SavedStudyViews(data: Data())
    typealias F = ChartSearchFixture

    private func search(_ text: String, plan: ChartSearchPlan? = nil) -> ChartSearchResults {
        ChartSearch.results(for: ChartQuery(text, history: history), plan: plan, history: history, saved: saved)
    }

    @Test("An empty search shows every chart in gallery order")
    func emptySearch() {
        let results = search("")
        #expect(results.cards.map(\.id.study) == TrainingStudy.allCases)
        #expect(results.answer == nil)
    }

    @Test("A lift search ranks strength first and keeps every chart on that lift")
    func liftSearch() throws {
        let results = search("bench progress")
        #expect(results.cards.first?.id.study == .legMax)
        #expect(!results.cards.isEmpty)
        for card in results.cards {
            #expect(card.options.exerciseKeys == [F.bench.key], "\(card.id.study)")
        }
    }

    @Test("A filter with no intent narrows every chart that can show it")
    func scopeOnly() throws {
        let results = search("arms October")
        #expect(results.cards.count > 6)
        for card in results.cards {
            #expect(card.options.period == .month(year: 2026, month: 10))
            if card.id.study.hasMuscleFocus {
                #expect(card.options.muscles == [.biceps, .triceps])
            } else {
                #expect(card.options.exerciseKeys == [F.curl.key], "the most-logged arm lift")
            }
        }
    }

    @Test("Charts with matching history come before empty ones")
    func dataFirst() {
        let figures = search("squat").cards.map { $0.result.figure != nil }
        #expect(figures.contains(true))
        #expect(figures == figures.sorted { $0 && !$1 })
    }

    @Test("A bodyweight lift skips charts that need an external load")
    func bodyweight() {
        let studies = search("push ups").cards.map(\.id.study)
        #expect(!studies.contains(.legMax))
        #expect(studies.contains(.pushups))
    }

    @Test("The model's charts lead, but the scope stays the user's")
    func planReorders() throws {
        let plan = ChartSearchPlan(charts: [.repRecords, .estimatedMaxTrend], total: nil)
        let results = search("How did my bench sessions go in October?", plan: plan)
        let withData = results.cards.filter { $0.result.figure != nil }.map(\.id.study)
        #expect(Array(withData.prefix(2)) == [.records, .legMax])
        for card in results.cards {
            #expect(card.options.exerciseKeys == [F.bench.key])
            #expect(card.options.period == .month(year: 2026, month: 10))
        }
    }

    @Test("A chart the model picks that can't show the scope is left out")
    func planCannotBreakScope() {
        // Muscle credits can't be filtered to one lift.
        let plan = ChartSearchPlan(charts: [.weeklyMuscleSets], total: nil)
        #expect(!search("How is my bench doing?", plan: plan).cards.contains { $0.id.study == .legWork })
    }

    @Test("The model can choose what to count when a question asks for a number, never for a filter")
    func planTotal() throws {
        let plan = ChartSearchPlan(charts: [], total: .workingSets)
        #expect(search("What did my squat look like in October?", plan: plan).answer == nil, "no number was asked for")
        let answer = try #require(search("How many squats did I do in October?", plan: plan).answer)
        guard case .table(let table) = answer.result.figure else {
            Issue.record("Expected a single value")
            return
        }
        #expect(table.rows.first?[2] == "6")
        #expect(answer.id.isAnswer)
        #expect(search("squat October", plan: plan).answer == nil)
    }

    @Test("A local answer wins over the model's number")
    func localAnswerFirst() throws {
        let plan = ChartSearchPlan(charts: [], total: .totalReps)
        let answer = try #require(search("How many bench sets did I do in October?", plan: plan).answer)
        #expect(answer.result.displayTitle.hasPrefix("Working sets"))
    }

    @Test("Something the log doesn't record has no charts, unless the question names a lift")
    func unrecorded() throws {
        let sleep = search("How did I sleep this week?")
        #expect(sleep.answer?.result.galleryCaption == "Not enough data")
        #expect(sleep.cards.isEmpty)
        let bench = search("Did sleep help my bench?")
        #expect(bench.answer?.result.galleryCaption == "Not enough data")
        #expect(!bench.cards.isEmpty)
        #expect(bench.cards.allSatisfy { $0.options.exerciseKeys == [F.bench.key] })
    }

    @Test("A lift with no logged sets says so instead of showing another lift")
    func unloggedLift() {
        let results = search("front squat progress")
        // Barbell and Smith front squats both fit, so the note uses the words.
        #expect(results.note == "No logged sets for Front Squat.")
        #expect(results.cards.allSatisfy { $0.result.figure == nil })
    }

    @Test("An empty log says so")
    func emptyLog() {
        let results = ChartSearch.results(for: ChartQuery("bench", history: F.empty), history: F.empty, saved: saved)
        #expect(results.note == "Your workout log has no workouts yet.")
    }

    @Test("Unrelated text finds nothing")
    func unrelated() {
        #expect(search("saxophone wallpaper").isEmpty)
    }

    @Test("Only questions ask the model")
    func asksModel() {
        #expect(!ChartSearch.asksModel(ChartQuery("arms", history: history)))
        #expect(!ChartSearch.asksModel(ChartQuery("bench October", history: history)))
        #expect(ChartSearch.asksModel(ChartQuery("How often do I bench?", history: history)))
        #expect(!ChartSearch.asksModel(ChartQuery("How did I sleep?", history: history)), "the log can't answer it")
    }

    @Test("Every chart has one model name, and each name maps back")
    func modelNames() {
        #expect(Set(ChartMeasure.allCases.map(\.study)) == Set(TrainingStudy.allCases))
        #expect(ChartMeasure.allCases.count == TrainingStudy.allCases.count)
        for study in TrainingStudy.allCases {
            #expect(ChartMeasure(study).study == study)
        }
    }
}
