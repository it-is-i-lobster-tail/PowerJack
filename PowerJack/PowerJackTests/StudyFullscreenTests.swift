import SwiftUI
import Testing

@testable import PowerJack

@MainActor
struct StudyFullscreenTests {
    @Test("The forecast guide compares both predictions at the latest displayed workout")
    func forecastExample() throws {
        let earlier = 1_750_000_000.0
        let latest = earlier + 86_400
        let series = [
            StudySeries(name: "Observed", points: [.init(earlier, 78), .init(latest, 80)]),
            StudySeries(name: "Prior 3 median", points: [.init(earlier, 75), .init(latest, 81)]),
            StudySeries(name: "Prior session", points: [.init(earlier, 76), .init(latest, 78)]),
        ]
        let study = StudyResult(
            id: .forecast, scope: "Bench press", figure: .traces(series, dates: true),
            xLabel: "Workout date", yLabel: "Estimated max (kg)")
        let example = try #require(study.readingExample)
        #expect(example.contains("80 kg"))
        #expect(example.contains("81 kg, off by 1 kg"))
        #expect(example.contains("78 kg, off by 2 kg"))
        #expect(study.presented(as: .table, transpose: false).readingExample == example)
    }

    @Test("The session comparison guide pairs each set’s rep count with its date")
    func sessionComparisonExample() async throws {
        let table = StudyTable(columns: ["Set", "Nov 4", "Nov 18", "Change"], rows: [["1", "8", "10", "2"]])
        let study = StudyResult(id: .lastCurl, scope: "Matching sessions", figure: .table(table))
        let screen = try await HostedView(StudyReadingGuide(study: study))
        defer { screen.close() }
        try #require(await screen.tap("How to Read"))
        #expect(screen.contains("For set 1, you logged 8 reps on Nov 4 and 10 reps on Nov 18."))
    }

    @Test("A full-screen table shows only the table, scrolling to every row and column")
    func tableViewport() async throws {
        let table = StudyTable(
            columns: (1...8).map { "Column \($0)" },
            rows: (1...44).map { row in (1...8).map { "\(row), \($0)" } })
        let result = StudyResult(id: .records, scope: "Rep records", figure: .table(table))
        let screen = try await HostedView(StudyFullscreenView(study: result, title: "Rep records"))
        defer { screen.close() }

        #expect(screen.contains("Rep records"))
        #expect(screen.contains("Share chart"))
        #expect(screen.contains("Close"))
        #expect(!screen.contains("How to Read"))
        let wide = try #require(screen.horizontalScrollViews.first)
        #expect(wide.contentSize.width >= StudyTableView.contentWidth(columns: table.columns.count) - 1)
        #expect(wide.pinchGestureRecognizer == nil || wide.maximumZoomScale <= wide.minimumZoomScale)
        await screen.scrollToBottom()
        #expect(screen.contains("44, 1"))
    }

    @Test("A full-screen lift panel shows that one lift with its tap readout and no guide")
    func singlePanel() async throws {
        let day = 86_400.0
        let squat = StudySeries(name: "Front Squat", points: (0..<20).map { .init(1_750_000_000 + Double($0) * 7 * day, 100 + Double($0)) })
        var panel = StudyResult(id: .legMax, scope: "Legs", figure: .liftPanels([squat]), xLabel: "Date", yLabel: "Estimated max")
        panel.summary = "Summary text"
        let screen = try await HostedView(StudyFullscreenView(study: panel, title: "Front Squat · Estimated max"))
        defer { screen.close() }
        #expect(screen.contains("Front Squat · Estimated max"))
        #expect(screen.contains("Selected workout"))
        #expect(!screen.contains("How to Read"))
        #expect(!screen.contains("Summary text"))
    }
}
