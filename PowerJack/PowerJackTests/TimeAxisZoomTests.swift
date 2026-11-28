import Foundation
import Testing

@testable import PowerJack

struct TimeAxisZoomTests {
    private static let day = 86_400.0
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }
    /// Nov 1, 2025 to Mar 1, 2026 (120 days), midnight UTC.
    private let start = 1_761_955_200.0
    private var times: [Double] { [start, start + 30 * Self.day, start + 120 * Self.day] }

    @Test("The full domain runs first to last date, and a single day is padded to a week that can't zoom")
    func fullDomain() {
        let window = TimeAxisWindow(times: times.shuffled())
        #expect(window.full == start...(start + 120 * Self.day))
        #expect(window.visible == window.full)
        #expect(!window.isZoomed)
        #expect(window.canZoom)

        let single = TimeAxisWindow(times: [start])
        #expect(single.length == TimeAxisWindow.minimumLength)
        #expect(single.full.contains(start))
        #expect(!single.canZoom)
        #expect(single.zoomed(by: 4) == nil)
    }

    @Test("The shortest view is about a week, or the whole history when it's shorter")
    func minimumLength() {
        let window = TimeAxisWindow(times: times)
        #expect(abs(window.minimumSpan - 7.0 / 120) < 1e-9)
        let zoomed = TimeAxisWindow(times: times, fraction: window.zoomed(by: 1_000))
        #expect(abs((zoomed.visible.upperBound - zoomed.visible.lowerBound) - 7 * Self.day) < 1)

        let short = TimeAxisWindow(times: [start, start + 4 * Self.day])
        #expect(short.minimumSpan == 1)
        #expect(!short.canZoom)
    }

    @Test("Pinching keeps the date under the fingers in place")
    func anchoredPinch() {
        let initial = 0.2...0.6
        let position = 0.25
        let anchor = initial.lowerBound + position * 0.4
        let zoomed = ChartGestures.zoomed(initial, scale: 2, anchor: anchor, at: position, spans: 0.05...1)
        #expect(abs((zoomed.upperBound - zoomed.lowerBound) - 0.2) < 1e-9)
        #expect(abs(zoomed.lowerBound + position * 0.2 - anchor) < 1e-9)
    }

    @Test("Zoom and pan stay inside the history and between the shortest and full span")
    func clamping() {
        let tight = ChartGestures.zoomed(0...1, scale: 100, anchor: 0.99, at: 0.99, spans: 0.1...1)
        #expect(abs((tight.upperBound - tight.lowerBound) - 0.1) < 1e-9)
        #expect(tight.upperBound <= 1)

        let wide = ChartGestures.zoomed(0.4...0.5, scale: 0.01, anchor: 0.45, at: 0.5, spans: 0.1...1)
        #expect(wide == 0...1)

        let early = ChartGestures.panned(0.1...0.3, by: 5)
        #expect(early.lowerBound == 0 && abs(early.upperBound - 0.2) < 1e-9)
        let late = ChartGestures.panned(0.7...0.9, by: -5)
        #expect(abs(late.lowerBound - 0.8) < 1e-9 && late.upperBound == 1)
    }

    @Test("Pinching back out to the whole history clears the zoom")
    func resetAtFullSpan() {
        #expect(TimeAxisWindow.settled(0...1) == nil)
        #expect(TimeAxisWindow.settled(0.1...0.5) == 0.1...0.5)
        let window = TimeAxisWindow(times: times, fraction: 0.4...0.6)
        #expect(window.isZoomed)
        #expect(TimeAxisWindow(times: times, fraction: window.zoomed(by: 0.1)).isZoomed == false)
        #expect(TimeAxisWindow(times: times).panned(by: 0.5) == nil)
    }

    @Test("Taps map to the visible stretch")
    func tapTime() {
        let window = TimeAxisWindow(times: times, fraction: 0.5...0.75)
        #expect(window.time(at: 0) == start + 60 * Self.day)
        #expect(window.time(at: 1) == start + 90 * Self.day)
        #expect(window.time(at: 2) == start + 90 * Self.day)
    }

    @Test("Axis labels stay at four or fewer, inside the plot, and switch from months to days when zoomed")
    func axisLabels() {
        let whole = TimeAxisWindow(times: times)
        let months = whole.ticks(calendar: calendar)
        #expect(months.map(\.label) == ["Dec", "Jan", "Feb"])
        // The year shows under the first tick and where it changes.
        #expect(months.map(\.year) == ["2025", "2026", nil])

        let fortnight = TimeAxisWindow(times: times, fraction: 0...(14.0 / 120))
        let days = fortnight.ticks(calendar: calendar)
        #expect((1...4).contains(days.count))
        #expect(days.allSatisfy { fortnight.visible.contains($0.date.timeIntervalSince1970) })
        #expect(days[0].label.hasPrefix("Nov "))

        for share in stride(from: 0.06, through: 1, by: 0.07) {
            for lower in stride(from: 0, through: 1 - share, by: 0.13) {
                let window = TimeAxisWindow(times: times, fraction: lower...(lower + share))
                let ticks = window.ticks(calendar: calendar).map(\.date.timeIntervalSince1970)
                let length = window.visible.upperBound - window.visible.lowerBound
                #expect(ticks.count <= 4)
                #expect(ticks.allSatisfy {
                    $0 >= window.visible.lowerBound + length * 0.02 - 1 && $0 <= window.visible.upperBound - length * 0.14 + 1
                })
            }
        }
    }

    @Test("A chosen range sets the axis rather than the data")
    func chosenDomain() {
        let year = (start - 10 * Self.day)...(start + 200 * Self.day)
        let window = TimeAxisWindow(times: times, domain: year)
        #expect(window.full == year)
    }

    @Test("Day ticks stay on the same dates while panning")
    func stableTicks() {
        let a = TimeAxisWindow(times: times, fraction: 0.2...0.3)
        let b = TimeAxisWindow(times: times, fraction: 0.21...0.31)
        let shared = Set(a.ticks(calendar: calendar).map(\.date)).intersection(b.ticks(calendar: calendar).map(\.date))
        #expect(!shared.isEmpty)
    }
}
