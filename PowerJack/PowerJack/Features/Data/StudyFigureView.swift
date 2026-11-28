import Charts
import SwiftUI

/// Both the preview image and the full-size view use these marks and this palette.
/// Every axis comes from `StudyAxisPlan`, so charts share one set of tick, label and range rules.
struct StudyFigureView: View {
    let study: StudyResult
    let compact: Bool
    /// Full screen shows one graph filling the space, without the lift panel's own title row.
    var fillsScreen = false
    /// Opens one lift panel on its own. Given a single-panel study and its title.
    var expandPanel: ((StudyResult, String) -> Void)?

    @Environment(\.colorScheme) private var scheme
    private func ink(_ index: Int) -> Color { WorkoutChartPalette.color(at: index, scheme: scheme) }

    @ViewBuilder var body: some View {
        switch study.figure {
        case .traces(let all, let dates):
            let series = dates ? all.map { $0.inside(study.dateDomain(for: all)) } : all
            let values = study.valueAxis(series.flatMap { $0.points.map(\.y) }, bars: series.contains { $0.style == .bars })
            Group {
                if dates {
                    Chart { traceMarks(series) { .value(study.xLabel, Date(timeIntervalSince1970: $0.x)) } }
                } else {
                    Chart { traceMarks(series) { .value(study.xLabel, $0.x) } }
                }
            }
            .modifier(StudyAxes(compact: compact, x: study.xLabel, y: study.yLabel, values: values))
            .modifier(StudyXAxis(series: series, study: study, compact: compact, dates: dates))
        case .liftPanels(let all):
            VStack(alignment: .leading, spacing: compact ? 3 : 18) {
                ForEach(Array(all.prefix(compact ? 3 : all.count).enumerated()), id: \.offset) { index, whole in
                    let trace = whole.inside(study.dateDomain(for: all))
                    if !compact && !fillsScreen {
                        let title = "\(trace.name) · \(study.yLabel)"
                        HStack {
                            Text(title).font(.headline)
                            Spacer()
                            if let expandPanel {
                                ExpandChartButton(title: title) {
                                    var panel = study
                                    panel.figure = .liftPanels([whole])
                                    expandPanel(panel, title)
                                }
                            }
                        }
                    }
                    let values = study.valueAxis(trace.points.map(\.y), bars: trace.style == .bars)
                    Chart(Array(trace.points.enumerated()), id: \.offset) { _, point in
                        let date = Date(timeIntervalSince1970: point.x)
                        if trace.style == .bars {
                            BarMark(x: .value("Date", date), y: .value(study.yLabel, point.y),
                                    width: .fixed(StudyFigureView.barWidth(trace.points.count)))
                                .foregroundStyle(ink(index))
                        } else if trace.style == .dots || trace.points.count == 1 {
                            PointMark(x: .value("Date", date), y: .value(study.yLabel, point.y)).foregroundStyle(ink(index))
                        } else {
                            LineMark(x: .value("Date", date), y: .value(study.yLabel, point.y)).foregroundStyle(ink(index))
                        }
                    }
                    .modifier(StudyValueAxis(compact: compact, values: values))
                    .frame(height: compact || fillsScreen ? nil : 145)
                    .frame(maxHeight: fillsScreen ? .infinity : nil)
                    .modifier(StudyXAxis(series: [trace], study: study, compact: compact, dates: true))
                    if compact { Divider() }
                }
            }
        case .comparison(let points, let connected):
            let categories = points.map(\.category).studyUnique
            let groups = points.map(\.series).studyUnique
            let values = study.valueAxis(points.map(\.value), bars: false)
            Chart {
                ForEach(categories, id: \.self) { label in
                    let values = points.filter { $0.category == label }.map(\.value)
                    if connected, let a = values.min(), let b = values.max() {
                        RuleMark(
                            xStart: .value(study.xLabel, a), xEnd: .value(study.xLabel, b), y: .value(study.yLabel, label)
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    let index = groups.firstIndex(of: point.series) ?? 0
                    PointMark(x: .value(study.xLabel, point.value), y: .value(study.yLabel, point.category))
                        .symbol(index == 0 ? BasicChartSymbolShape.circle : .diamond)
                        .symbolSize(index == 0 ? (compact ? 32 : 100) : (compact ? 16 : 45))
                        .foregroundStyle(ink(index))
                }
            }
            .chartXScale(domain: values.domain)
            .chartXAxis {
                if !compact {
                    AxisMarks(values: values.ticks) { tick in
                        AxisGridLine()
                        AxisValueLabel { if let value = tick.as(Double.self) { Text(value.studyNumber) } }
                    }
                }
            }
            .chartYAxis {
                if !compact { AxisMarks(values: categories) { AxisGridLine() } }
            }
            .chartOverlay { proxy in
                // Each lift's name sits level with the middle of its own row of dots.
                GeometryReader { geometry in
                    if !compact, let anchor = proxy.plotFrame {
                        let frame = geometry[anchor]
                        ForEach(categories, id: \.self) { name in
                            if let y = proxy.position(forY: name) {
                                Text(name).font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing).lineLimit(2)
                                    .frame(width: Self.rowNameWidth - 8, alignment: .trailing)
                                    .position(x: frame.minX - Self.rowNameWidth / 2, y: frame.minY + y)
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .padding(.leading, compact ? 0 : Self.rowNameWidth)
            .chartXAxisLabel(compact ? "" : study.xLabel)
        case .attempts(let counts):
            VStack(alignment: .leading, spacing: compact ? 5 : 16) {
                ForEach(counts, id: \.label) { entry in
                    if !compact {
                        Text("\(entry.label) · \(entry.made) of \(entry.attempts)").font(.subheadline.weight(.semibold))
                    }
                    let shown = compact ? min(24, entry.attempts) : entry.attempts
                    let filled = Int((Double(entry.made) * Double(shown) / Double(entry.attempts)).rounded())
                    let dotSize: CGFloat = compact ? 4 : 9
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: dotSize, maximum: dotSize), spacing: compact ? 2 : 4)],
                        alignment: .leading, spacing: 3
                    ) {
                        ForEach(0..<shown, id: \.self) { i in
                            Circle().fill(i < filled ? ink(0) : .clear)
                                .overlay { Circle().strokeBorder(ink(0), lineWidth: 1) }
                                .frame(width: dotSize, height: dotSize)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: compact ? .infinity : nil, alignment: .leading)
        case .bars(let bars):
            StudyCategoryPlot(study: study, bars: bars, compact: compact)
        case .matrix(let cols, let rows, let values):
            StudyMatrix(study: study, columns: cols, rows: rows, values: values, compact: compact)
        case .table(let table):
            StudyTableView(table: table, compact: compact)
        case nil:
            if compact {
                Image(systemName: "chart.xyaxis.line").font(.title2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No matching history", systemImage: "chart.xyaxis.line", description: Text(study.emptyReason))
            }
        }
    }

    /// Room for lift names beside rows of dots.
    static let rowNameWidth: CGFloat = 112

    /// Date bars keep a visible width however many there are.
    static func barWidth(_ count: Int) -> CGFloat { max(2, min(14, 220 / CGFloat(max(1, count)))) }

    @ChartContentBuilder
    private func traceMarks<X: Plottable>(_ series: [StudySeries], x: @escaping (StudyPoint) -> PlottableValue<X>)
        -> some ChartContent
    {
        ForEach(Array(series.enumerated()), id: \.offset) { i, trace in
            ForEach(Array(trace.points.enumerated()), id: \.offset) { _, point in
                let y = PlottableValue.value(study.yLabel, point.y)
                if trace.style == .bars {
                    BarMark(x: x(point), y: y, width: .fixed(Self.barWidth(trace.points.count)))
                        .position(by: .value("Series", trace.name))
                        .foregroundStyle(ink(i))
                } else if trace.style == .dots || trace.points.count == 1 {
                    if study.id == .effort, trace.name == "Target" {
                        PointMark(x: x(point), y: y)
                            .symbol {
                                Circle().strokeBorder(ink(i), lineWidth: compact ? 1 : 2)
                                    .frame(width: compact ? 7 : 13, height: compact ? 7 : 13)
                            }
                    } else {
                        PointMark(x: x(point), y: y)
                            .symbol(i.isMultiple(of: 2) ? BasicChartSymbolShape.circle : .diamond)
                            .symbolSize(compact ? 14 : 36)
                            .foregroundStyle(ink(i))
                    }
                } else {
                    LineMark(x: x(point), y: y, series: .value("Series", trace.name))
                        .interpolationMethod(trace.style == .step ? .stepEnd : .linear)
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: compact ? 1.8 : 2.3, lineCap: .round,
                                dash: trace.style == .fit ? [5, 4] : [])
                        )
                        .foregroundStyle(ink(i))
                }
            }
        }
    }
}

extension StudyResult {
    /// The range a date axis spans: the chosen dates trimmed to the history, or whole days around the data.
    func dateDomain(for series: [StudySeries], calendar: Calendar = .current) -> DateInterval {
        if let xRange { return xRange }
        let times = series.flatMap { $0.points.map(\.x) }
        let first = calendar.startOfDay(for: Date(timeIntervalSince1970: times.min() ?? 0))
        let last = calendar.startOfDay(for: Date(timeIntervalSince1970: times.max() ?? 0))
        return DateInterval(start: first, end: calendar.date(byAdding: .day, value: 1, to: last) ?? last)
    }

    /// Whole counts get whole ticks. Bars stand on zero.
    func valueAxis(_ values: [Double], bars: Bool, axis: String? = nil) -> StudyAxisPlan.ValueAxis {
        let label = axis ?? yLabel
        let kind: StudyAxisPlan.YKind = values.allSatisfy { $0 == $0.rounded() } && !label.contains("(")
            ? .count : .measure(unit: label)
        return StudyAxisPlan.valueAxis(values: values, kind: kind, includesZero: bars)
    }
}

extension StudySeries {
    /// Only the points inside the axis range. Reference lines are trimmed to its ends.
    func inside(_ range: DateInterval) -> StudySeries {
        let start = range.start.timeIntervalSince1970
        let end = range.end.timeIntervalSince1970
        var trimmed = self
        if style == .fit, let first = points.first, let last = points.last, points.count == 2, first.y == last.y {
            let a = max(start, first.x)
            let b = min(end, last.x)
            trimmed.points = a <= b ? [StudyPoint(a, first.y), StudyPoint(b, last.y)] : []
        } else {
            trimmed.points = points.filter { $0.x >= start && $0.x < end }
        }
        return trimmed
    }
}

/// Date charts get the pinch time-axis zoom and tap inspection in full size. Other x axes are whole set
/// positions or measured changes, padded so end bars stay whole.
private struct StudyXAxis: ViewModifier {
    let series: [StudySeries]
    let study: StudyResult
    let compact: Bool
    let dates: Bool

    @ViewBuilder func body(content: Content) -> some View {
        let domain = study.dateDomain(for: series)
        if compact {
            if dates {
                content.chartXScale(domain: domain.start...domain.end).chartXAxis(.hidden)
            } else {
                content.chartXScale(domain: numeric.domain).chartXAxis(.hidden)
            }
        } else if dates {
            content.modifier(StudyDateInspection(series: series, study: study, domain: domain))
        } else {
            let axis = numeric
            content
                .chartXScale(domain: axis.domain)
                .chartXAxis {
                    AxisMarks(values: axis.ticks) { tick in
                        AxisGridLine()
                        if let value = tick.as(Double.self) { AxisValueLabel { Text(value.studyNumber) } }
                    }
                }
        }
    }

    /// Whole positions such as set numbers get a tick each and half a step either side.
    private var numeric: StudyAxisPlan.ValueAxis {
        let xs = series.flatMap { $0.points.map(\.x) }
        guard let low = xs.min(), let high = xs.max() else { return .init(domain: 0...1, ticks: [0, 1]) }
        if xs.allSatisfy({ $0 == $0.rounded() }), high - low <= 12 {
            return .init(domain: (low - 0.5)...(high + 0.5), ticks: Array(stride(from: low, through: high, by: 1)))
        }
        return StudyAxisPlan.valueAxis(values: xs, kind: .measure(unit: study.xLabel), includesZero: false)
    }
}

/// Tap the plot to inspect a session, pinch to zoom its time axis. VoiceOver can step through the same dates.
private struct StudyDateInspection: ViewModifier {
    let series: [StudySeries]
    let study: StudyResult
    let domain: DateInterval
    @State private var selection: Double?
    @State private var zoom: ClosedRange<Double>?

    @ViewBuilder func body(content: Content) -> some View {
        let dates = Set(series.flatMap { $0.points.map(\.x) }).sorted()
        let bounds = domain.start.timeIntervalSince1970...domain.end.timeIntervalSince1970
        if let latest = dates.last {
            let selected = selection.flatMap { dates.contains($0) ? $0 : nil } ?? latest
            VStack(alignment: .leading, spacing: 5) {
                content
                    .modifier(TimeAxisZoom(times: dates, domain: bounds, fraction: $zoom) { time in
                        let visible = TimeAxisWindow(times: dates, domain: bounds, fraction: zoom).visible
                        let candidates = dates.filter(visible.contains)
                        selection = (candidates.isEmpty ? dates : candidates).min { abs($0 - time) < abs($1 - time) }
                    })
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            if let plot = proxy.plotFrame,
                               let x = proxy.position(forX: Date(timeIntervalSince1970: selected)),
                               (0...geometry[plot].width).contains(x) {
                                let frame = geometry[plot]
                                Rectangle().fill(.secondary.opacity(0.5))
                                    .frame(width: 1, height: frame.height)
                                    .offset(x: frame.minX + x, y: frame.minY)
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    Text(readout(selected)).font(.caption).monospacedDigit()
                        .accessibilityLabel("Selected workout")
                        .accessibilityValue(readout(selected))
                        .accessibilityAdjustableAction { direction in
                            guard let i = dates.firstIndex(of: selected) else { return }
                            switch direction {
                            case .increment: selection = dates[min(dates.count - 1, i + 1)]
                            case .decrement: selection = dates[max(0, i - 1)]
                            @unknown default: break
                            }
                        }
            }
        } else {
            content
                .chartXScale(domain: domain.start...domain.end)
                .chartXAxis {
                    let ticks = StudyAxisPlan.timeTicks(in: domain)
                    AxisMarks(values: ticks.map(\.date)) { tick in
                        AxisGridLine()
                        AxisValueLabel { if ticks.indices.contains(tick.index) { StudyTimeTickLabel(tick: ticks[tick.index]) } }
                    }
                }
        }
    }

    private func readout(_ x: Double) -> String {
        let date = Date(timeIntervalSince1970: x).formatted(date: .abbreviated, time: .omitted)
        let values = series.map { trace in
            let observations = trace.points.filter { $0.x == x }.map { point in
                study.id == .effort && trace.name == "Reported" && point.y == 5 ? "5+" : point.y.studyNumber
            }
            let value =
                observations.isEmpty
                ? (study.id == .effort && trace.name == "Reported" ? "Unrated" : "—")
                : observations.joined(separator: ", ")
            return "\(trace.name) \(value)"
        }
        return ([date, study.yLabel] + values).joined(separator: " · ")
    }
}

/// Category order is taken from the query. Only an ordered category can offer a line.
/// Calendar buckets plot on a date axis. Horizontal bars put each name on its own line above its bar,
/// so long exercise names never sit on the plot.
struct StudyCategoryPlot: View {
    /// The bar band of a horizontal row. Its name sits above it.
    static let barBand: CGFloat = 28
    /// Past this many rows a horizontal chart scrolls inside its card.
    static let visibleRows = 12
    private static let nameLine: CGFloat = 17

    /// Room for a name (one or two lines) above a bar.
    static func rowHeight(labels: [String]) -> CGFloat {
        let lines: CGFloat = labels.contains { $0.count > 34 } ? 2 : 1
        return barBand + lines * nameLine + 4
    }

    /// The full-size height that gives every horizontal category its own row.
    static func height(labels: [String]) -> CGFloat {
        let rows = labels.studyUnique
        return CGFloat(rows.count) * rowHeight(labels: rows) + 44
    }

    let study: StudyResult
    let bars: [StudyBar]
    let compact: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if !study.horizontalCategories, let timeline = study.timeline,
           bars.allSatisfy({ timeline.interval(for: $0.label) != nil }) {
            timePlot(timeline)
        } else if study.horizontalCategories {
            horizontalPlot
        } else {
            GeometryReader { geometry in categoryPlot(width: geometry.size.width) }
        }
    }

    private var groups: [String] { bars.map(\.group).studyUnique }
    private var categories: [String] { bars.map(\.label).studyUnique }
    private func color(_ group: String) -> Color {
        WorkoutChartPalette.color(at: groups.firstIndex(of: group) ?? 0, scheme: scheme)
    }

    /// Stacked totals when bars stack, otherwise the values themselves.
    private var valueAxis: StudyAxisPlan.ValueAxis {
        let stacks = study.presentation == .original
        let values = stacks
            ? categories.map { label in bars.filter { $0.label == label }.reduce(0) { $0 + $1.value } }
            : bars.map(\.value)
        return study.valueAxis(values, bars: study.presentation != .line && study.presentation != .scatter,
                               axis: study.horizontalCategories ? study.xLabel : study.yLabel)
    }

    // MARK: Calendar buckets

    private func timePlot(_ timeline: StudyTimeline) -> some View {
        let values = valueAxis
        let ticks = StudyAxisPlan.timeTicks(in: timeline.range)
        let side = study.presentation == .bar ? groups.count : 1
        var stacked: [String: Double] = [:]
        let marks = bars.map { bar in
            let interval = timeline.interval(for: bar.label)!
            let base = side > 1 ? 0 : stacked[bar.label, default: 0]
            if study.presentation == .original { stacked[bar.label] = base + bar.value }
            // Each bar fills most of its own trimmed bucket, side by side or stacked.
            let inner = interval.duration * 0.8 / Double(side)
            let index = side > 1 ? Double(groups.firstIndex(of: bar.group) ?? 0) : 0
            let start = interval.start.addingTimeInterval(interval.duration * 0.1 + inner * index)
            return StudyBucketMark(
                bar: bar, middle: interval.start.addingTimeInterval(interval.duration / 2), start: start,
                end: start.addingTimeInterval(inner), base: base)
        }
        let plot = Chart(Array(marks.enumerated()), id: \.offset) { _, mark in bucketMark(mark) }
        .chartXScale(domain: timeline.range.start...timeline.range.end)
        return Group {
            if compact {
                plot.chartXAxis(.hidden).chartYScale(domain: values.domain).chartYAxis(.hidden).chartLegend(.hidden)
            } else {
                plot.chartXAxis {
                    AxisMarks(values: ticks.map(\.date)) { tick in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel { if ticks.indices.contains(tick.index) { StudyTimeTickLabel(tick: ticks[tick.index]) } }
                    }
                }
                .modifier(StudyAxes(compact: false, x: timeline.noun, y: study.yLabel, values: values))
            }
        }
    }

    @ChartContentBuilder
    private func bucketMark(_ mark: StudyBucketMark) -> some ChartContent {
        switch study.presentation {
        case .scatter:
            PointMark(x: .value(study.xLabel, mark.middle), y: .value(study.yLabel, mark.bar.value))
                .symbolSize(compact ? 14 : 38)
                .foregroundStyle(color(mark.bar.group))
        case .line:
            LineMark(x: .value(study.xLabel, mark.middle), y: .value(study.yLabel, mark.bar.value),
                     series: .value("Series", mark.bar.group))
                .symbol(.circle)
                .symbolSize(compact ? 5 : 14)
                .foregroundStyle(color(mark.bar.group))
        default:
            RectangleMark(
                xStart: .value(study.xLabel, mark.start), xEnd: .value(study.xLabel, mark.end),
                yStart: .value(study.yLabel, mark.base), yEnd: .value(study.yLabel, mark.base + mark.bar.value))
                .foregroundStyle(color(mark.bar.group))
        }
    }

    // MARK: Names along x

    private func categoryPlot(width: CGFloat) -> some View {
        let values = valueAxis
        let metrics = StudyCategoryPlot.metrics(typeSize)
        let labels = StudyAxisPlan.categoryLabels(
            categories.map(categoryCaption), slot: max(1, width - 44) / CGFloat(max(1, categories.count)),
            metrics: metrics, maximumHeight: 110)
        let slot = max(1, width - 44) / CGFloat(max(1, categories.count))
        let plot = Chart(Array(bars.enumerated()), id: \.offset) { _, bar in
            mark(x: .value(study.xLabel, bar.label), y: .value(study.yLabel, bar.value), group: bar.group)
                .foregroundStyle(color(bar.group))
        }
        return Group {
            if compact {
                plot.chartXAxis(.hidden).chartYScale(domain: values.domain).chartYAxis(.hidden).chartLegend(.hidden)
            } else {
                plot.chartXAxis {
                    AxisMarks(values: categories) { tick in
                        if let label = tick.as(String.self), let text = labels.shown[categoryCaption(label)] {
                            AxisTick()
                            AxisValueLabel(anchor: labels.style == .diagonal ? .topTrailing : .top,
                                           collisionResolution: .disabled) {
                                StudyCategoryLabel(text: text, style: labels.style, slot: slot, metrics: metrics)
                            }
                        }
                    }
                }
                .modifier(StudyAxes(compact: false, x: study.xLabel, y: study.yLabel, values: values))
                .padding(.leading, leadingRoom(labels, slot: slot, metrics: metrics))
                .accessibilityChartDescriptor(self)
            }
        }
    }

    /// A tilted first name reaches left past its bar. Make room so it isn't cut at the card's edge.
    private func leadingRoom(_ labels: StudyAxisPlan.CategoryLabels, slot: CGFloat,
                             metrics: StudyAxisPlan.TextMetrics) -> CGFloat {
        guard labels.style == .diagonal, let first = categories.first.map(categoryCaption),
              let text = labels.shown[first] else { return 0 }
        let reach = (metrics.width(text) + metrics.lineHeight) * sqrt(0.5)
        return max(0, reach - slot / 2 - 30)
    }

    static func metrics(_ size: DynamicTypeSize) -> StudyAxisPlan.TextMetrics {
        let font = UIFont.preferredFont(
            forTextStyle: .caption2, compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size)))
        return StudyAxisPlan.TextMetrics(lineHeight: ceil(font.lineHeight)) {
            ceil(($0 as NSString).size(withAttributes: [.font: font]).width)
        }
    }

    // MARK: Horizontal rows

    @ViewBuilder private var horizontalPlot: some View {
        let values = valueAxis
        let row = Self.rowHeight(labels: categories)
        let nameHeight = row - Self.barBand
        let plot = Chart(Array(bars.enumerated()), id: \.offset) { _, bar in
            mark(x: .value(study.xLabel, bar.value), y: .value(study.yLabel, bar.label), group: bar.group)
                .foregroundStyle(color(bar.group))
                .offset(y: compact ? 0 : nameHeight / 2)
        }
        .chartXScale(domain: values.domain)
        if compact {
            plot.chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        } else {
            plot.chartXAxis {
                AxisMarks(values: values.ticks) { tick in
                    AxisGridLine()
                    AxisValueLabel { if let value = tick.as(Double.self) { Text(value.studyNumber) } }
                }
                AxisMarks(values: [0]) { AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.secondary) }
            }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let anchor = proxy.plotFrame {
                        let frame = geometry[anchor]
                        ForEach(categories, id: \.self) { label in
                            if let center = proxy.position(forY: label) {
                                Text(categoryCaption(label))
                                    .font(.caption)
                                    .lineLimit(2)
                                    .frame(width: frame.width, height: nameHeight, alignment: .bottomLeading)
                                    .position(x: frame.midX, y: frame.minY + center - row / 2 + nameHeight / 2)
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .chartXAxisLabel(study.xLabel)
            .chartLegend(.hidden)
            .overlay { if let note = values.note { StudyEmptyNote(text: note) } }
        }
    }

    private var barSpan: MarkDimension {
        study.horizontalCategories && !compact ? .fixed(Self.barBand - 6) : .automatic
    }

    private func categoryCaption(_ label: String) -> String {
        let dimension = study.horizontalCategories ? study.yLabel : study.xLabel
        return study.id == .armReps && dimension == "Day" ? label.filter(\.isNumber) : label
    }

    @ChartContentBuilder
    private func mark<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>, group: String)
        -> some ChartContent
    {
        switch study.presentation {
        case .line:
            LineMark(x: x, y: y, series: .value("Series", group))
                .symbol(.circle)
                .symbolSize(compact ? 5 : 14)
        case .scatter:
            PointMark(x: x, y: y)
                .position(by: .value("Series", group), axis: study.horizontalCategories ? .vertical : .horizontal,
                          span: barSpan)
                .symbolSize(compact ? 14 : 38)
        case .bar:
            BarMark(x: x, y: y)
                .position(by: .value("Series", group), axis: study.horizontalCategories ? .vertical : .horizontal,
                          span: barSpan)
                .cornerRadius(compact ? 1.5 : 3)
        default:
            // Native monthly totals are stacked. The explicit bar style compares groups side by side.
            if study.horizontalCategories && !compact {
                BarMark(x: x, y: y, height: .fixed(Self.barBand - 8)).cornerRadius(3)
            } else {
                BarMark(x: x, y: y)
                    .cornerRadius(compact ? 1.5 : 3)
            }
        }
    }
}

extension StudyCategoryPlot: AXChartDescriptorRepresentable {
    /// VoiceOver reads every full name, even one the axis had to shorten.
    func makeChartDescriptor() -> AXChartDescriptor {
        let names = categories
        let x = AXCategoricalDataAxisDescriptor(title: study.xLabel, categoryOrder: names)
        let values = bars.map(\.value)
        let y = AXNumericDataAxisDescriptor(
            title: study.yLabel, range: (values.min() ?? 0)...(values.max() ?? 1), gridlinePositions: []
        ) { $0.studyNumber }
        let series = groups.map { group in
            AXDataSeriesDescriptor(
                name: group, isContinuous: false,
                dataPoints: bars.filter { $0.group == group }.map { .init(x: $0.label, y: $0.value) })
        }
        return AXChartDescriptor(title: study.displayTitle, summary: nil, xAxis: x, yAxis: y, series: series)
    }
}

private struct StudyBucketMark {
    let bar: StudyBar
    let middle: Date
    let start: Date
    let end: Date
    let base: Double
}

/// A category name level, tilted 45° or upright, in a box the size it actually covers.
private struct StudyCategoryLabel: View {
    let text: String
    let style: StudyAxisPlan.LabelStyle
    let slot: CGFloat
    let metrics: StudyAxisPlan.TextMetrics

    var body: some View {
        let width = metrics.width(text)
        let line = metrics.lineHeight
        switch style {
        case .horizontal:
            Text(text).multilineTextAlignment(.center).lineLimit(2)
                .frame(width: max(1, slot - 4)).fixedSize(horizontal: false, vertical: true)
        case .diagonal:
            let side = (width + line) * sqrt(0.5)
            Text(text).lineLimit(1).fixedSize()
                .rotationEffect(.degrees(-45))
                .frame(width: side, height: side)
        case .vertical:
            Text(text).lineLimit(1).fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: line, height: width)
        }
    }
}

/// The value axis every chart shares: nice bounds and ticks, and a note when nothing rose above zero.
private struct StudyAxes: ViewModifier {
    let compact: Bool
    let x: String
    let y: String
    let values: StudyAxisPlan.ValueAxis
    func body(content: Content) -> some View {
        if compact {
            content.chartYScale(domain: values.domain).chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        } else {
            content.modifier(StudyValueAxis(compact: false, values: values))
                .chartXAxisLabel(x)
                .chartYAxisLabel(y)
                .chartLegend(.hidden)
        }
    }
}

private struct StudyValueAxis: ViewModifier {
    let compact: Bool
    let values: StudyAxisPlan.ValueAxis
    func body(content: Content) -> some View {
        content
            .chartYScale(domain: values.domain)
            .chartYAxis {
                if !compact {
                    AxisMarks(position: .leading, values: values.ticks) { tick in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel { if let value = tick.as(Double.self) { Text(value.studyNumber) } }
                    }
                }
            }
            .overlay { if !compact, let note = values.note { StudyEmptyNote(text: note) } }
    }
}

private struct StudyEmptyNote: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).allowsHitTesting(false)
    }
}

struct StudyMatrix: View {
    @Environment(\.colorScheme) private var scheme
    let study: StudyResult
    @State private var selection: String?
    let columns: [String]
    let rows: [String]
    let values: [[Double?]]
    let compact: Bool

    var body: some View {
        let maximum = max(1, values.flatMap { $0 }.compactMap { $0 }.max() ?? 1)
        let shown = compact ? min(6, rows.count) : rows.count
        VStack(alignment: .leading, spacing: compact ? 0 : 8) {
            if !compact {
                Text(selection ?? "Select a cell for its labels and value.")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
            }
            Grid(horizontalSpacing: compact ? 2 : 3, verticalSpacing: compact ? 2 : 4) {
                if !compact {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        ForEach(columns.indices, id: \.self) { i in
                            Text(columns[i]).font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).frame(width: columnWidth(i))
                        }
                    }
                }
                ForEach(0..<shown, id: \.self) { r in
                    GridRow {
                        if !compact {
                            Text(rows[r]).font(.caption.weight(.medium)).fixedSize(
                                horizontal: false, vertical: true
                            )
                            .frame(width: 116, alignment: .leading)
                        }
                        ForEach(columns.indices, id: \.self) { c in
                            let value = values[r][c]
                            let cell = RoundedRectangle(cornerRadius: compact ? 2 : 4)
                                .fill(
                                    value.map {
                                        WorkoutChartPalette.color(at: 0, scheme: scheme).opacity(
                                            0.12 + 0.8 * $0 / maximum)
                                    } ?? Color.secondary.opacity(0.1)
                                )
                                .frame(minWidth: compact ? 2 : 32, minHeight: compact ? 5 : 32)
                                .overlay {
                                    if !compact {
                                        Text(value?.studyNumber ?? "–").font(.caption.monospacedDigit())
                                            .foregroundStyle(
                                                (value ?? 0) / maximum > 0.60
                                                    ? (scheme == .dark ? Color.black : .white) : .primary)
                                    }
                                }
                            if compact {
                                cell
                            } else {
                                let units = study.id == .legWork ? "credited sets" : "working sets"
                                let amount = value.map { "\($0.studyNumber) \(units)" } ?? "No log"
                                let label = "\(study.yLabel) \(rows[r]) · \(study.xLabel) \(columns[c]) · \(amount)"
                                Button {
                                    selection = label
                                } label: {
                                    cell.frame(width: columnWidth(c), height: 44)
                                        .overlay {
                                            if selection == label {
                                                RoundedRectangle(cornerRadius: 4).strokeBorder(.primary, lineWidth: 2)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(label)
                                .accessibilityAddTraits(selection == label ? .isSelected : [])
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: study) { selection = nil }
    }
    private func columnWidth(_ i: Int) -> CGFloat {
        Self.width(for: columns[i])
    }

    static func width(for column: String) -> CGFloat {
        min(128, max(44, CGFloat(column.count) * 7 + 8))
    }

}

struct StudyTableView: View {
    @Environment(\.colorScheme) private var scheme
    let table: StudyTable
    var compact = false
    var scrollsHorizontally = true

    private static let firstColumnWidth: CGFloat = 114
    private static let columnWidth: CGFloat = 92
    private static let columnSpacing: CGFloat = 12

    static func contentWidth(columns: Int) -> CGFloat {
        guard columns > 0 else { return 0 }
        return firstColumnWidth + CGFloat(columns - 1) * (columnWidth + columnSpacing)
    }

    var body: some View {
        if compact {
            let cols = min(3, table.columns.count)
            VStack(spacing: 0) {
                compactRow(Array(table.columns.prefix(cols)), header: true)
                ForEach(Array(table.rows.prefix(4).enumerated()), id: \.offset) { _, row in
                    Divider()
                    compactRow(Array(row.prefix(cols)), header: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if scrollsHorizontally {
            ScrollView(.horizontal) { rows }
        } else {
            rows
        }
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            row(table.columns, header: true)
            ForEach(table.rows.indices, id: \.self) { index in
                Divider()
                row(table.rows[index], header: false)
            }
        }
    }

    private func compactRow(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(cells.indices, id: \.self) { i in
                Text(cells[i]).font(.system(size: 8, weight: header ? .bold : .medium))
                    .foregroundStyle(header ? WorkoutChartPalette.color(at: 0, scheme: scheme) : .primary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.vertical, 3)
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: Self.columnSpacing) {
            ForEach(cells.indices, id: \.self) { i in
                Text(cells[i])
                    .font(header ? .caption.weight(.semibold) : .subheadline)
                    .foregroundStyle(header ? .secondary : .primary)
                    .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    .frame(width: i == 0 ? Self.firstColumnWidth : Self.columnWidth, alignment: .leading)
            }
        }.padding(.vertical, 9)
    }
}
