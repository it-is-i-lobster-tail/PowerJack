import Foundation
import Testing

@testable import PowerJack

/// Starred charts are kept on this device with their exact choices, and bad data never breaks them.
@MainActor
struct FavoriteChartsTests {
    let bench = StudyOptions(period: .year(2026), exerciseKeys: [StudyHistory.bench], presentation: .original,
                             parameters: [.reps: 5])

    @Test("Starring saves the chart with its choices, newest first, and starring again removes it")
    func toggle() throws {
        var data = try FavoriteCharts(data: Data()).toggling(.legMax, options: bench, name: "Bench max")
        data = try FavoriteCharts(data: data).toggling(.records, options: StudyOptions(muscles: [.quads]), name: "Quad records")
        let saved = FavoriteCharts(data: data)
        #expect(saved.charts.map(\.name) == ["Quad records", "Bench max"])
        #expect(saved.favorite(.legMax, options: bench)?.options == bench)
        #expect(saved.favorite(.legMax, options: StudyOptions()) == nil, "other choices are another chart")

        let removed = FavoriteCharts(data: try saved.toggling(.legMax, options: bench, name: "Bench max"))
        #expect(removed.charts.map(\.name) == ["Quad records"])
        let id = try #require(removed.charts.first?.id)
        #expect(FavoriteCharts(data: try removed.removing(id)).charts.isEmpty)
    }

    @Test("A range of days from search round-trips")
    func rangePeriod() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let options = StudyOptions(period: .range(start: start, end: start.addingTimeInterval(86_400 * 30)))
        let data = try FavoriteCharts(data: Data()).toggling(.armReps, options: options, name: "Reps")
        #expect(FavoriteCharts(data: data).charts.first?.options == options)
    }

    @Test("Garbage, another version, or one broken entry never loses the readable favorites", arguments: [
        Data(), Data("not json".utf8), Data("[1, 2]".utf8), Data(#"{"version": 2, "charts": []}"#.utf8),
        Data(#"{"version": 1, "charts": "nope"}"#.utf8),
    ])
    func unreadable(data: Data) {
        #expect(FavoriteCharts(data: data).charts.isEmpty)
    }

    @Test("One unreadable favorite is skipped and the rest stay")
    func oneBrokenEntry() throws {
        let data = try FavoriteCharts(data: Data()).toggling(.legMax, options: bench, name: "Bench max")
        var saved = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        saved["charts"] = [["study": 9999, "name": "From a newer app"]] + (saved["charts"] as? [Any] ?? [])
        let mixed = try JSONSerialization.data(withJSONObject: saved)
        #expect(FavoriteCharts(data: mixed).charts.map(\.name) == ["Bench max"])
    }

    @Test("Search ideas come from the lifter's own log, and each one finds charts")
    func searchIdeas() {
        let history = ChartSearchSampleHistoryTests.history
        let ideas = SearchIdeas.make(from: history)
        #expect(ideas.count == 5)
        #expect(ideas.first == "Barbell Back Squat progress" || ideas.first == "Barbell Bench Press progress", "\(ideas)")
        for idea in ideas {
            let results = ChartSearch.results(for: ChartQuery(idea, history: history), history: history,
                                              saved: SavedStudyViews(data: Data()))
            #expect(results.cards.contains { $0.result.figure != nil }, "\(idea)")
        }
        #expect(SearchIdeas.make(from: ChartSearchFixture.empty).count == 5, "an empty log still has ideas")
    }
}
