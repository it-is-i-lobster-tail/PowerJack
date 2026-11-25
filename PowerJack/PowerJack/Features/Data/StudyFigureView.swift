import Charts
import SwiftUI

/// Both the preview image and the full-size view use these marks and this palette.
struct StudyFigureView: View {
    let study: StudyResult
    let compact: Bool

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
                            PointMark(x: x, y: y)
                                .symbol(i.isMultiple(of: 2) ? BasicChartSymbolShape.circle : .diamond)
                                .symbolSize(compact ? 14 : 36)
                                .foregroundStyle(ink(i))
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
            .chartXScale(domain: .automatic(includesZero: false))
            .chartYScale(domain: .automatic(includesZero: series.contains { $0.style == .bars }))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: compact ? 3 : 4)) { tick in
                    AxisGridLine()
                    if !compact, let value = tick.as(Double.self) {
                        AxisValueLabel {
                            if dates {
                                Text(Date(timeIntervalSince1970: value), format: .dateTime.month(.abbreviated).day())
                            } else {
                                Text(value.studyNumber)
                            }
                        }
                    }
                }
            }
            .modifier(StudyAxes(compact: compact, x: study.xLabel, y: study.yLabel))
        case .liftPanels(let series):
            VStack(alignment: .leading, spacing: compact ? 3 : 18) {
                ForEach(Array(series.prefix(compact ? 3 : series.count).enumerated()), id: \.offset) { index, trace in
                    if !compact { Text("\(trace.name) · \(study.yLabel)").font(.headline) }
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
                    .chartXAxis(compact ? .hidden : .visible)
                    .chartYAxis(compact ? .hidden : .visible)
                    .frame(height: compact ? nil : 145)
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
            StudyMatrix(columns: cols, rows: rows, values: values, compact: compact)
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

/// Category order is taken from the query. Only an ordered category can offer a line.
private struct StudyCategoryPlot: View {
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
            } else {
                mark(x: .value(study.xLabel, bar.label), y: .value(study.yLabel, bar.value), group: bar.group)
                    .foregroundStyle(color)
            }
        }
        if compact {
            plot.chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        } else {
            plot.chartXAxis {
                if study.horizontalCategories {
                    AxisMarks(values: .automatic(desiredCount: 5))
                } else {
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
            }
            .chartYAxis {
                if study.horizontalCategories {
                    AxisMarks(position: .leading, values: categories) { tick in
                        if let label = tick.as(String.self), ticks.contains(label) {
                            AxisTick()
                            AxisValueLabel(centered: true) {
                                let caption = categoryCaption(label)
                                Text(caption).lineLimit(2)
                                    .fixedSize(horizontal: caption.count <= 12, vertical: true)
                            }
                        }
                    }
                } else {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5))
                }
            }
            .chartXAxisLabel(study.xLabel)
            .chartYAxisLabel(study.yLabel)
            .chartLegend(.hidden)
        }
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
                .position(by: .value("Series", group), axis: study.horizontalCategories ? .vertical : .horizontal)
                .symbolSize(compact ? 14 : 38)
        case .bar:
            BarMark(x: x, y: y)
                .position(by: .value("Series", group), axis: study.horizontalCategories ? .vertical : .horizontal)
                .cornerRadius(compact ? 1.5 : 3)
        default:
            // Native monthly totals are stacked. The explicit bar style compares groups side by side.
            BarMark(x: x, y: y)
                .cornerRadius(compact ? 1.5 : 3)
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

private struct StudyMatrix: View {
    @Environment(\.colorScheme) private var scheme
    let columns: [String]
    let rows: [String]
    let values: [[Double?]]
    let compact: Bool

    var body: some View {
        let maximum = max(1, values.flatMap { $0 }.compactMap { $0 }.max() ?? 1)
        let shown = compact ? min(6, rows.count) : rows.count
        Grid(horizontalSpacing: compact ? 2 : 3, verticalSpacing: compact ? 2 : 4) {
            if !compact {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(columns.indices, id: \.self) { i in Text(columns[i]).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(0..<shown, id: \.self) { r in
                GridRow {
                    if !compact { Text(rows[r]).font(.caption.weight(.medium)).gridColumnAlignment(.leading) }
                    ForEach(columns.indices, id: \.self) { c in
                        let value = values[r][c]
                        RoundedRectangle(cornerRadius: compact ? 2 : 4)
                            .fill(
                                value.map {
                                    WorkoutChartPalette.color(at: 0, scheme: scheme).opacity(0.12 + 0.8 * $0 / maximum)
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
                            .accessibilityLabel("\(rows[r]), \(columns[c]), \(value?.studyNumber ?? "no log")")
                    }
                }
            }
        }
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
