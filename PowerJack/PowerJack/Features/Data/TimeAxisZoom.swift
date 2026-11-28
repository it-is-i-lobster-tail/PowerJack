import Charts
import SwiftUI

/// The visible stretch of a chart's time axis, in seconds since 1970.
/// Pinching shows fewer days and dragging moves along time. The page itself never scales.
struct TimeAxisWindow: Equatable {
    static let minimumLength: TimeInterval = 7 * 86_400

    /// First to last date. A single day is padded to a week so it still has an axis.
    let full: ClosedRange<Double>
    /// The visible part as fractions of `full`. Nil shows all of it.
    let fraction: ClosedRange<Double>?

    init(times: [Double], fraction: ClosedRange<Double>? = nil) {
        let first = times.min() ?? 0
        let last = times.max() ?? 0
        let pad = first == last ? Self.minimumLength / 2 : 0
        full = (first - pad)...(last + pad)
        self.fraction = fraction
    }

    var length: Double { full.upperBound - full.lowerBound }

    /// About a week, or the whole history when it is shorter than that.
    var minimumSpan: Double { length > 0 ? min(1, Self.minimumLength / length) : 1 }
    var canZoom: Bool { minimumSpan < 1 }
    var isZoomed: Bool { fraction != nil }

    var visible: ClosedRange<Double> {
        guard let fraction else { return full }
        return (full.lowerBound + fraction.lowerBound * length)...(full.lowerBound + fraction.upperBound * length)
    }

    func time(at position: Double) -> Double {
        visible.lowerBound + min(1, max(0, position)) * (visible.upperBound - visible.lowerBound)
    }

    /// Pinching back out to the whole history clears the zoom.
    static func settled(_ window: ClosedRange<Double>) -> ClosedRange<Double>? {
        window.upperBound - window.lowerBound >= 1 - 1e-9 ? nil : window
    }

    /// Zoom around the middle of the visible stretch, as VoiceOver's Zoom in and Zoom out do.
    func zoomed(by scale: Double) -> ClosedRange<Double>? {
        let window = fraction ?? 0...1
        return Self.settled(ChartGestures.zoomed(
            window, scale: scale, anchor: (window.lowerBound + window.upperBound) / 2, at: 0.5,
            spans: minimumSpan...1))
    }

    /// Move by a share of the visible stretch. Negative goes earlier.
    func panned(by share: Double) -> ClosedRange<Double>? {
        guard let fraction else { return nil }
        return ChartGestures.panned(fraction, by: -share)
    }

    // MARK: Axis labels

    static let leadingMargin = 0.02
    static let trailingMargin = 0.14

    enum Step: Equatable {
        case days(Int), months(Int), years(Int)
    }

    /// The finest calendar step that keeps at most `limit` labels inside the plot.
    func axis(limit: Int = 4, calendar: Calendar = .current) -> (step: Step, ticks: [Double]) {
        let steps: [Step] = [.days(1), .days(2), .days(3), .days(7), .days(14),
                             .months(1), .months(2), .months(3), .months(6),
                             .years(1), .years(2), .years(5), .years(10)]
        for step in steps {
            let ticks = ticks(every: step, calendar: calendar)
            if ticks.count <= limit { return (step, ticks) }
        }
        return (.years(10), [])
    }

    func label(_ time: Double, step: Step, calendar: Calendar = .current) -> String {
        let date = Date(timeIntervalSince1970: time)
        var style = Date.FormatStyle.dateTime
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        switch step {
        case .days: return date.formatted(style.month(.abbreviated).day())
        case .months:
            // January carries the year so a long history stays unambiguous.
            return calendar.component(.month, from: date) == 1
                ? date.formatted(style.year()) : date.formatted(style.month(.abbreviated))
        case .years: return date.formatted(style.year())
        }
    }

    private func ticks(every step: Step, calendar: Calendar) -> [Double] {
        let range = visible
        // Labels start at their tick and run right, so the trailing edge keeps room for the widest one.
        let length = range.upperBound - range.lowerBound
        let inner = (range.lowerBound + length * Self.leadingMargin)...(range.upperBound - length * Self.trailingMargin)
        let start = Date(timeIntervalSince1970: range.lowerBound)
        // Days count from the history's first day so ticks stay on the same dates while panning.
        let origin = calendar.startOfDay(for: Date(timeIntervalSince1970: full.lowerBound))
        var date: Date
        let unit: Calendar.Component
        let count: Int
        switch step {
        case .days(let n):
            unit = .day; count = n
            let offset = calendar.dateComponents([.day], from: origin, to: calendar.startOfDay(for: start)).day ?? 0
            let aligned = offset - ((offset % n) + n) % n
            date = calendar.date(byAdding: .day, value: aligned, to: origin) ?? start
        case .months(let n):
            unit = .month; count = n
            date = calendar.dateInterval(of: .month, for: start)?.start ?? start
            let month = calendar.component(.month, from: date) - 1
            date = calendar.date(byAdding: .month, value: -(month % n), to: date) ?? date
        case .years(let n):
            unit = .year; count = n
            date = calendar.dateInterval(of: .year, for: start)?.start ?? start
            let year = calendar.component(.year, from: date)
            date = calendar.date(byAdding: .year, value: -(year % n), to: date) ?? date
        }
        var ticks: [Double] = []
        while date.timeIntervalSince1970 <= inner.upperBound, ticks.count < 64 {
            if inner.contains(date.timeIntervalSince1970) { ticks.append(date.timeIntervalSince1970) }
            guard let next = calendar.date(byAdding: unit, value: count, to: date) else { break }
            date = next
        }
        return ticks
    }
}

/// Pinch a date chart to zoom its time axis, drag sideways to move along it, and tap to pick a time.
/// The visible window is owned by the caller so labels outside the chart can follow it.
struct TimeAxisZoom: ViewModifier {
    let times: [Double]
    /// Whether the chart plots `Date` values rather than seconds as `Double`.
    var plotsDates = true
    var showsAxis = true
    var padding: CGFloat = 0
    @Binding var fraction: ClosedRange<Double>?
    var tap: ((Double) -> Void)?

    func body(content: Content) -> some View {
        let window = TimeAxisWindow(times: times, fraction: fraction)
        scaled(content, window: window)
            .chartPlotStyle { plot in
                // Unzoomed charts keep end markers whole. Zoomed ones hide marks outside the window.
                plot.clipShape(Rectangle().inset(by: window.isZoomed ? 0 : -40))
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let anchor = proxy.plotFrame {
                        let frame = geometry[anchor]
                        ChartGestures(
                            window: window.fraction ?? 0...1, minimumSpan: window.minimumSpan, maximumSpan: 1,
                            pansOnlyWhenZoomed: true,
                            change: { fraction = TimeAxisWindow.settled($0) },
                            tap: { point in
                                guard frame.width > 0 else { return }
                                tap?(window.time(at: point.x / frame.width))
                            })
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
                .accessibilityHidden(true)
            }
            .accessibilityActions {
                if window.canZoom {
                    Button("Zoom in") { fraction = window.zoomed(by: 2) }
                    Button("Zoom out") { fraction = window.zoomed(by: 0.5) }
                }
                if window.isZoomed {
                    Button("Earlier") { fraction = window.panned(by: -0.8) }
                    Button("Later") { fraction = window.panned(by: 0.8) }
                }
            }
            .onChange(of: window.full) { fraction = nil }
    }

    @ViewBuilder
    private func scaled(_ content: Content, window: TimeAxisWindow) -> some View {
        let range = PlotDimensionScaleRange.plotDimension(startPadding: padding, endPadding: padding)
        let axis = window.axis()
        let labels = axis.ticks.map { window.label($0, step: axis.step) }
        if plotsDates {
            let domain = Date(timeIntervalSince1970: window.visible.lowerBound)
                ... Date(timeIntervalSince1970: window.visible.upperBound)
            let chart = content.chartXScale(domain: domain, range: range)
            if showsAxis {
                chart.chartXAxis { marks(axis.ticks.map { Date(timeIntervalSince1970: $0) }, labels: labels) }
            } else {
                chart.chartXAxis(.hidden)
            }
        } else {
            let chart = content.chartXScale(domain: window.visible, range: range)
            if showsAxis {
                chart.chartXAxis { marks(axis.ticks, labels: labels) }
            } else {
                chart.chartXAxis(.hidden)
            }
        }
    }

    private func marks<Value: Plottable>(_ values: [Value], labels: [String]) -> some AxisContent {
        AxisMarks(values: values) { tick in
            AxisGridLine()
            AxisValueLabel {
                if labels.indices.contains(tick.index) { Text(labels[tick.index]) }
            }
        }
    }
}
