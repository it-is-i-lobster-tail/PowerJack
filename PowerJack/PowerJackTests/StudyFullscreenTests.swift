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

    @Test("A full-screen table can pan to every row and column and still zoom")
    func tableViewport() async throws {
        let table = StudyTable(
            columns: (1...8).map { "Column \($0)" },
            rows: (1...44).map { row in (1...8).map { "\(row), \($0)" } })
        let result = StudyResult(id: .records, scope: "Rep records", figure: .table(table))
        let screen = try await HostedView(StudyFullscreenView(study: result, title: "Rep records"))
        defer { screen.close() }

        let canvas = try #require(
            screen.horizontalScrollViews.first { $0.accessibilityIdentifier == "data.fullscreen.canvas" })
        #expect(canvas.contentSize.width >= StudyTableView.contentWidth(columns: table.columns.count))
        #expect(canvas.contentSize.height > canvas.bounds.height)
        #expect(canvas.pinchGestureRecognizer?.isEnabled == true)
        #expect(canvas.panGestureRecognizer.isEnabled)
        let initialViewport = canvas.bounds.height
        let footer = try #require(screen.frame(of: "How to Read"))
        await screen.scrollToBottom()
        #expect(screen.frame(of: "How to Read")?.minY == footer.minY)
        let question = "What’s the most you’ve lifted for exactly this many reps?"
        #expect(!screen.contains(question))
        try #require(await screen.tap("How to Read"))
        #expect(await screen.waitUntil { canvas.bounds.height < initialViewport - 20 })
        #expect(screen.contains(question))
        try #require(await screen.tap("How to Read"))
        #expect(await screen.waitUntil { abs(canvas.bounds.height - initialViewport) < 2 })
        #expect(!screen.contains(question))
        let original = canvas.contentSize
        canvas.setZoomScale(2, animated: false)
        await screen.settle()
        #expect(canvas.contentSize.width >= original.width * 2 - 1)
        #expect(canvas.contentSize.height >= original.height * 2 - 1)
        let corner = CGPoint(
            x: canvas.contentSize.width - canvas.bounds.width,
            y: canvas.contentSize.height - canvas.bounds.height)
        canvas.setContentOffset(corner, animated: false)
        await screen.settle()
        #expect(abs(canvas.contentOffset.x - corner.x) < 1)
        #expect(abs(canvas.contentOffset.y - corner.y) < 1)
    }
}
