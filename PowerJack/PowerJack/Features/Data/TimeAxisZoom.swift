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

    /// `domain` is the chosen date range. Without one the axis spans the data.
    init(times: [Double], domain: ClosedRange<Double>? = nil, fraction: ClosedRange<Double>? = nil) {
        if let domain, domain.upperBound > domain.lowerBound {
            full = domain
        } else {
            let first = times.min() ?? 0
            let last = times.max() ?? 0
            let pad = first == last ? Self.minimumLength / 2 : 0
            full = (first - pad)...(last + pad)
        }
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

    /// Ticks for the visible stretch, on the shared calendar rules. Day and week ticks stay put while panning.
    func ticks(limit: Int = 4, calendar: Calendar = .current) -> [StudyAxisPlan.TimeTick] {
        StudyAxisPlan.timeTicks(
            in: DateInterval(start: Date(timeIntervalSince1970: visible.lowerBound),
                             end: Date(timeIntervalSince1970: visible.upperBound)),
            origin: Date(timeIntervalSince1970: full.lowerBound), maximumCount: limit, calendar: calendar)
    }
}

/// Pinch a date chart to zoom its time axis, drag sideways to move along it, and tap to pick a time.
/// The visible window is owned by the caller so labels outside the chart can follow it.
struct TimeAxisZoom: ViewModifier {
    let times: [Double]
    /// The chosen date range in seconds since 1970, when the axis should span it rather than the data.
    var domain: ClosedRange<Double>?
    /// Whether the chart plots `Date` values rather than seconds as `Double`.
    var plotsDates = true
    var showsAxis = true
    var padding: CGFloat = 0
    @Binding var fraction: ClosedRange<Double>?
    var tap: ((Double) -> Void)?

    func body(content: Content) -> some View {
        let window = TimeAxisWindow(times: times, domain: domain, fraction: fraction)
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
        let ticks = window.ticks()
        if plotsDates {
            let domain = Date(timeIntervalSince1970: window.visible.lowerBound)
                ... Date(timeIntervalSince1970: window.visible.upperBound)
            let chart = content.chartXScale(domain: domain, range: range)
            if showsAxis {
                chart.chartXAxis { marks(ticks.map(\.date), ticks: ticks) }
            } else {
                chart.chartXAxis(.hidden)
            }
        } else {
            let chart = content.chartXScale(domain: window.visible, range: range)
            if showsAxis {
                chart.chartXAxis { marks(ticks.map(\.date.timeIntervalSince1970), ticks: ticks) }
            } else {
                chart.chartXAxis(.hidden)
            }
        }
    }

    private func marks<Value: Plottable>(_ values: [Value], ticks: [StudyAxisPlan.TimeTick]) -> some AxisContent {
        AxisMarks(values: values) { tick in
            AxisGridLine()
            AxisValueLabel {
                if ticks.indices.contains(tick.index) { StudyTimeTickLabel(tick: ticks[tick.index]) }
            }
        }
    }
}

/// A date tick's label, with the year underneath on the first tick and wherever it changes.
struct StudyTimeTickLabel: View {
    let tick: StudyAxisPlan.TimeTick
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tick.label)
            if let year = tick.year { Text(year).foregroundStyle(.secondary) }
        }
        .fixedSize()
    }
}
