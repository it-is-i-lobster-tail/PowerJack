import Foundation
import SwiftData
import Testing

@testable import PowerJack

/// Searches a lifter actually types, run against the simulator's year of sample training: four
/// programs, three workouts a week, fourteen exercises. The hand-checked numbers live in
/// `ChartSearchTests`. These check that real-sized history gives the right charts, with data, quickly.
@MainActor
struct ChartSearchSampleHistoryTests {
    /// Built once: seeding a year of workouts takes a moment.
    static let history: StudyHistory = {
        let store = PowerJackStore(inMemory: true)
        let context = store.container.mainContext
        let now = ChartSearchFixture.today
        try! SimulatorTrainingHistory.populate(in: context, now: now)
        return StudyHistory(programs: try! context.fetch(FetchDescriptor<Program>()),
                            archive: try! context.fetch(FetchDescriptor<HistoryRecord>()),
                            logs: try! context.fetch(FetchDescriptor<WorkoutLog>()),
                            unit: .pounds, today: now)
    }()

    private var history: StudyHistory { Self.history }
    private let saved = SavedStudyViews(data: Data())

    private func search(_ text: String, plan: ChartSearchPlan? = nil,
                        cache: ChartResultCache = ChartResultCache()) -> ChartSearchResults {
        ChartSearch.results(for: ChartQuery(text, history: history), plan: plan, history: history, saved: saved,
                            cache: cache)
    }

    private func key(_ name: String) throws -> String {
        try #require(history.sessions.first { $0.name == name }?.key, "\(name) is logged")
    }

    @Test("The sample history is a year of real-sized training")
    func sampleSize() {
        #expect(history.workouts.filter { $0.status == .complete }.count > 120)
        #expect(Set(history.sessions.map(\.key)).count >= 12)
    }

    @Test("Searches lifters type lead with the chart that answers them, filled with their data", arguments: [
        ("bench progress", TrainingStudy.legMax), ("is my squat going up", .legMax), ("squat PRs", .records),
        ("heaviest bench for 5 reps", .records), ("how long are my workouts", .duration),
        ("skipped sets", .skipped), ("bench tonnage", .tonnage), ("which muscles am I neglecting", .recency),
        ("push up progress", .pushups), ("what days do I train", .frequency), ("how hard were my squat sets", .effort),
    ])
    func leadingChart(text: String, chart: TrainingStudy) throws {
        let cards = search(text).cards
        let lead = try #require(cards.first, "\(text) shows charts")
        #expect(cards.prefix(3).map(\.id.study).contains(chart), "\(text): \(cards.prefix(3).map(\.id.study))")
        #expect(lead.result.figure != nil, "\(text): the first chart has data")
    }

    @Test("Every pause while typing a search shows charts, never an empty screen")
    func typingNeverBlank() {
        for text in ["bench progress", "squat records", "how long are my workouts"] {
            for length in 1...text.count {
                let prefix = String(text.prefix(length))
                #expect(!search(prefix).cards.isEmpty, "\(prefix)")
            }
        }
    }

    @Test("A lift search keeps every chart on that lift")
    func liftScope() throws {
        let bench = try key("Barbell Bench Press")
        for card in search("bench progress").cards {
            #expect(card.options.exerciseKeys == [bench], "\(card.id.study)")
        }
    }

    @Test("A muscle search with a month narrows every chart, and most of them have data")
    func scopeOnly() {
        let month = history.calendar.dateComponents([.year, .month], from: history.today)
        let cards = search("legs this month").cards
        #expect(cards.count > 10)
        #expect(cards.allSatisfy { $0.options.period == .month(year: month.year!, month: month.month!) })
        #expect(cards.filter { $0.result.figure != nil }.count > cards.count / 2)
    }

    @Test("A count matches the sets the log holds for that month")
    func monthlySets() throws {
        let calendar = history.calendar
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: history.today)!
        let name = lastMonth.formatted(.dateTime.month(.wide))
        let month = calendar.dateInterval(of: .month, for: lastMonth)!
        let expected = history.sessions.filter { month.contains($0.date) && $0.date < month.end }
            .reduce(0) { $0 + $1.done.count }
        let answer = try #require(search("How many sets did I do in \(name)?").answer)
        guard case .table(let table) = answer.result.figure else {
            Issue.record("Expected a single value")
            return
        }
        #expect(expected > 0)
        #expect(table.rows.first?[2] == String(expected))
    }

    @Test("The model's chart order leads without changing the lift")
    func planOrder() throws {
        let bench = try key("Barbell Bench Press")
        let plan = ChartSearchPlan(charts: [.repsAcrossSets, .estimatedMaxTrend], total: nil)
        let cards = search("How is my bench doing lately?", plan: plan).cards
        #expect(cards.prefix(2).map(\.id.study) == [.benchSets, .legMax])
        #expect(cards.allSatisfy { $0.options.exerciseKeys == [bench] })
    }

    @Test("The result cache gives the same charts as a fresh search")
    func cacheMatchesFresh() {
        let cache = ChartResultCache()
        for text in ["b", "be", "bench", "bench progress", "", "bench progress"] {
            let cached = search(text, cache: cache)
            let fresh = search(text)
            #expect(cached.cards.map(\.id) == fresh.cards.map(\.id), "\(text)")
            #expect(cached.cards.map(\.result) == fresh.cards.map(\.result), "\(text)")
        }
    }

    /// Typing "bench progress" one letter at a time, as the field does after each pause.
    @Test("Typing a search letter by letter stays interactive")
    func typingLatency() {
        let cache = ChartResultCache()
        _ = search("", cache: cache)
        let text = "bench progress"
        var slowest = Duration.zero
        for length in 1...text.count {
            let start = ContinuousClock.now
            _ = search(String(text.prefix(length)), cache: cache)
            slowest = max(slowest, ContinuousClock.now - start)
        }
        #expect(slowest < .milliseconds(150), "slowest keystroke took \(slowest)")
    }

    @Test("The model's plan arriving reorders charts without recomputing them")
    func planLatency() {
        let cache = ChartResultCache()
        let question = "How is my bench doing lately?"
        _ = search(question, cache: cache)
        let start = ContinuousClock.now
        _ = search(question, plan: ChartSearchPlan(charts: [.estimatedMaxTrend, .repRecords], total: nil), cache: cache)
        #expect(ContinuousClock.now - start < .milliseconds(50))
    }
}
