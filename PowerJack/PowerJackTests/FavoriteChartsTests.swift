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

    @Test("One graph of a several-graph page is narrowed to its lift and keeps the page's other choices")
    func narrowedGraph() throws {
        let page = StudyOptions(period: .year(2026), muscles: [.quads], presentation: .scatter,
                                searchFocus: StudySearchFocus(name: "legs", muscles: [.quads], exercises: []))
        let graph = page.narrowed(to: StudyHistory.squat)
        #expect(graph.exerciseKeys == [StudyHistory.squat])
        #expect(graph.muscles.isEmpty && graph.searchFocus == nil)
        #expect(graph.period == page.period && graph.presentation == page.presentation && graph.parameters == page.parameters)

        let history = ChartSearchSampleHistoryTests.history
        let legs = history.result(for: .legMax)
        guard case .liftPanels(let panels) = legs.figure else { Issue.record("legs show one graph per lift"); return }
        #expect(panels.count > 1)
        #expect(legs.graphKeys.count == panels.count)
        let key = try #require(legs.graphKeys.first)
        let single = history.result(for: .legMax, options: StudyOptions().narrowed(to: key))
        guard case .liftPanels(let only) = single.figure else { Issue.record("still a lift graph"); return }
        #expect(only.count == 1 && only.first?.exerciseKey == key)
        #expect(only.first?.points == panels.first?.points, "the graph shows the same sessions on its own")
    }

    @Test("Starring one graph saves it as its own favorite, apart from the whole page, and shows in Favorites")
    func graphToggle() throws {
        let history = ChartSearchSampleHistoryTests.history
        let page = StudyOptions(period: .all)
        let keys = history.result(for: .legMax, options: page).graphKeys
        let key = try #require(keys.first)

        let data = try FavoriteCharts(data: Data())
            .toggling(.legMax, options: page.narrowed(to: key), name: "Barbell Back Squat · Estimated max (lb)")
        let saved = FavoriteCharts(data: data)
        #expect(saved.starredGraphs(.legMax, options: page, keys: keys) == [key])
        #expect(saved.favorite(.legMax, options: page) == nil, "the whole page is not starred")
        #expect(saved.charts.first?.name == "Barbell Back Squat · Estimated max (lb)")

        let cards = saved.cards { history.result(for: $0, options: $1) }
        let card = try #require(cards.first)
        #expect(cards.count == 1 && card.id.study == .legMax && card.id.exerciseKeys == [key])
        #expect(card.id.favorite == saved.charts.first?.id)
        guard case .liftPanels(let only) = card.result.figure else { Issue.record("opens as a lift graph"); return }
        #expect(only.count == 1, "it opens as a single-graph page")

        let removed = FavoriteCharts(data: try saved.toggling(.legMax, options: page.narrowed(to: key), name: ""))
        #expect(removed.starredGraphs(.legMax, options: page, keys: keys).isEmpty)
    }

    @Test("Favorites saved before single graphs still open")
    func olderFavorites() throws {
        let old = #"{"version":1,"charts":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","study":\#(TrainingStudy.legMax.rawValue),"name":"Leg lifts","options":{"period":{"all":{}},"muscles":[],"exerciseKeys":[],"transpose":false,"presentation":"original","parameters":[]}}]}"#
        let saved = FavoriteCharts(data: Data(old.utf8))
        #expect(saved.charts.map(\.name) == ["Leg lifts"])
        #expect(saved.charts.first?.options.period == .all)
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
