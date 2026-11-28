import Charts
import SwiftUI

/// Both the preview image and the full-size view use these marks and this palette.
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
        case .traces(let series, let dates):
            Chart {
                ForEach(Array(series.enumerated()), id: \.offset) { i, trace in
                    ForEach(Array(trace.points.enumerated()), id: \.offset) { _, point in
                        let x = PlottableValue.value(study.xLabel, point.x)
                        let y = PlottableValue.value(study.yLabel, point.y)
                        if trace.style == .bars {
                            BarMark(x: x, y: y)
                                .position(by: .value("Series", trace.name))
                                .foregroundStyle(ink(i))
                        } else if trace.style == .dots || trace.points.count == 1 {
                            if study.id == .effort, trace.name == "Target" {
                                PointMark(x: x, y: y)
                                    .symbol {
                                        Circle().strokeBorder(ink(i), lineWidth: compact ? 1 : 2)
                                            .frame(width: compact ? 7 : 13, height: compact ? 7 : 13)
                                    }
                            } else {
                                PointMark(x: x, y: y)
                                    .symbol(i.isMultiple(of: 2) ? BasicChartSymbolShape.circle : .diamond)
                                    .symbolSize(compact ? 14 : 36)
                                    .foregroundStyle(ink(i))
                            }
                        } else {
                            LineMark(x: x, y: y, series: .value("Series", trace.name))
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
            .chartYScale(domain: .automatic(includesZero: series.contains { $0.style == .bars }))
            .modifier(StudyAxes(compact: compact, x: study.xLabel, y: study.yLabel))
            .modifier(StudyXAxis(series: series, study: study, compact: compact, dates: dates, plotsDates: false))
        case .liftPanels(let series):
            VStack(alignment: .leading, spacing: compact ? 3 : 18) {
                ForEach(Array(series.prefix(compact ? 3 : series.count).enumerated()), id: \.offset) { index, trace in
                    if !compact && !fillsScreen {
                        let title = "\(trace.name) · \(study.yLabel)"
                        HStack {
                            Text(title).font(.headline)
                            Spacer()
                            if let expandPanel {
                                ExpandChartButton(title: title) {
                                    var panel = study
                                    panel.figure = .liftPanels([trace])
                                    expandPanel(panel, title)
                                }
                            }
                        }
                    }
                    Chart(Array(trace.points.enumerated()), id: \.offset) { _, point in
                        let date = Date(timeIntervalSince1970: point.x)
                        if trace.style == .bars {
                            BarMark(x: .value("Date", date), y: .value(study.yLabel, point.y))
                                .foregroundStyle(ink(index))
                        } else if trace.style == .dots || trace.points.count == 1 {
                            PointMark(x: .value("Date", date), y: .value(study.yLabel, point.y)).foregroundStyle(ink(index))
                        } else {
                            LineMark(x: .value("Date", date), y: .value(study.yLabel, point.y)).foregroundStyle(ink(index))
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: trace.style == .bars))
                    .chartYAxis(compact ? .hidden : .visible)
                    .frame(height: compact || fillsScreen ? nil : 145)
                    .frame(maxHeight: fillsScreen ? .infinity : nil)
                    .modifier(StudyXAxis(series: [trace], study: study, compact: compact, dates: true, plotsDates: true))
                    if compact { Divider() }
                }
            }
        case .comparison(let points, let connected):
            let categories = points.map(\.category).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let groups = points.map(\.series).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
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
            .chartXScale(domain: .automatic(includesZero: false))
            .chartXAxis(compact ? .hidden : .visible)
            .chartYAxis(compact ? .hidden : .visible)
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
}

/// Date charts get the pinch time-axis zoom and tap inspection in full size. Other x axes keep plain numbers.
private struct StudyXAxis: ViewModifier {
    let series: [StudySeries]
    let study: StudyResult
    let compact: Bool
    let dates: Bool
    let plotsDates: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if compact {
            content.chartXAxis(.hidden)
        } else if dates {
            content.modifier(StudyDateInspection(series: series, study: study, plotsDates: plotsDates))
        } else {
            content
                .chartXScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { tick in
                        AxisGridLine()
                        if let value = tick.as(Double.self) { AxisValueLabel { Text(value.studyNumber) } }
                    }
                }
        }
    }
}

/// Tap the plot to inspect a session, pinch to zoom its time axis. VoiceOver can step through the same dates.
private struct StudyDateInspection: ViewModifier {
    let series: [StudySeries]
    let study: StudyResult
    let plotsDates: Bool
    @State private var selection: Double?
    @State private var zoom: ClosedRange<Double>?

    @ViewBuilder func body(content: Content) -> some View {
        let dates = Set(series.flatMap { $0.points.map(\.x) }).sorted()
        if let latest = dates.last {
            let selected = selection.flatMap { dates.contains($0) ? $0 : nil } ?? latest
            VStack(alignment: .leading, spacing: 5) {
                content
                    .modifier(TimeAxisZoom(times: dates, plotsDates: plotsDates, fraction: $zoom) { time in
                        let visible = TimeAxisWindow(times: dates, fraction: zoom).visible
                        let candidates = dates.filter(visible.contains)
                        selection = (candidates.isEmpty ? dates : candidates).min { abs($0 - time) < abs($1 - time) }
                    })
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            if let plot = proxy.plotFrame, let x = position(selected, in: proxy),
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
        }
    }

    private func position(_ time: Double, in proxy: ChartProxy) -> CGFloat? {
        plotsDates ? proxy.position(forX: Date(timeIntervalSince1970: time)) : proxy.position(forX: time)
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
/// Horizontal bars put each name on its own line above its bar, so long exercise names never sit on the plot.
struct StudyCategoryPlot: View {
    /// Room for a two-line name above a bar.
    static let rowHeight: CGFloat = 60
    private static let barThickness: CGFloat = 16
    private static let barDrop: CGFloat = 12

    /// The full-size height that gives every horizontal category its own row.
    static func height(categories: Int) -> CGFloat { CGFloat(categories) * rowHeight + 44 }

    let study: StudyResult
    let bars: [StudyBar]
    let compact: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let groups = bars.map(\.group).studyUnique
        let categories = bars.map(\.label).studyUnique
        let limit = study.horizontalCategories ? 6 : (categories.contains { $0.count > 10 } ? 3 : 5)
        let ticks = Set(
            categories.count <= limit
                ? categories : (0..<limit).map { categories[$0 * (categories.count - 1) / (limit - 1)] })
        let plot = Chart(Array(bars.enumerated()), id: \.offset) { _, bar in
            let color = WorkoutChartPalette.color(at: groups.firstIndex(of: bar.group) ?? 0, scheme: scheme)
            if study.horizontalCategories {
                mark(x: .value(study.xLabel, bar.value), y: .value(study.yLabel, bar.label), group: bar.group)
                    .foregroundStyle(color)
                    .offset(y: compact ? 0 : Self.barDrop)
            } else {
                mark(x: .value(study.xLabel, bar.label), y: .value(study.yLabel, bar.value), group: bar.group)
                    .foregroundStyle(color)
            }
        }
        if compact {
            plot.chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        } else if study.horizontalCategories {
            plot.chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5))
                AxisMarks(values: [0]) { AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.secondary) }
            }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let anchor = proxy.plotFrame {
                        let frame = geometry[anchor]
                        let labelHeight = Self.rowHeight / 2 + Self.barDrop - Self.barThickness / 2 - 4
                        ForEach(categories, id: \.self) { label in
                            if let center = proxy.position(forY: label) {
                                Text(categoryCaption(label))
                                    .font(.caption)
                                    .lineLimit(2)
                                    .frame(width: frame.width, height: labelHeight, alignment: .bottomLeading)
                                    .position(
                                        x: frame.midX,
                                        y: frame.minY + center + Self.barDrop - Self.barThickness / 2 - 2 - labelHeight / 2)
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .chartXAxisLabel(study.xLabel)
            .chartLegend(.hidden)
        } else {
            plot.chartXAxis {
                // Categorical axes can enumerate the entire scale even when given explicit tick values.
                AxisMarks(values: categories) { tick in
                    if let label = tick.as(String.self), ticks.contains(label) {
                        AxisTick()
                        AxisValueLabel {
                            Text(categoryCaption(label)).lineLimit(2)
                                .fixedSize(horizontal: categoryCaption(label).count <= 8, vertical: true)
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) }
            .chartXAxisLabel(study.xLabel)
            .chartYAxisLabel(study.yLabel)
            .chartLegend(.hidden)
        }
    }

    private var barSpan: MarkDimension {
        study.horizontalCategories && !compact ? .fixed(Self.barThickness) : .automatic
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
                BarMark(x: x, y: y, height: .fixed(Self.barThickness)).cornerRadius(3)
            } else {
                BarMark(x: x, y: y)
                    .cornerRadius(compact ? 1.5 : 3)
            }
        }
    }
}

private struct StudyAxes: ViewModifier {
    let compact: Bool
    let x: String
    let y: String
    func body(content: Content) -> some View {
        if compact {
            content.chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        } else {
            content.chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel()
                }
            }
            .chartXAxisLabel(x)
            .chartYAxisLabel(y)
            .chartLegend(.hidden)
        }
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
