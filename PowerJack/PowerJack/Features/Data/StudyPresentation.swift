import Foundation

enum StudyPresentation: String, CaseIterable, Codable {
    case original, bar, line, scatter, table

    var label: String {
        switch self {
        case .original: "Original"
        case .bar: "Bar"
        case .line: "Line"
        case .scatter: "Scatter plot"
        case .table: "Table"
        }
    }
}

extension StudyResult {
    var availablePresentations: [StudyPresentation] {
        // A sparse relationship may have paired rows before there are enough observations for its fitted chart.
        if case .table = figure, alternateBars.isEmpty { return [.original] }
        switch id {
        case .armReps, .legMax, .fixedSquat, .repeatBench, .benchSets, .returnToSquat, .blocks, .forecast, .pushups:
            return [.original, .bar, .line, .scatter, .table]
        case .legWork, .frequency, .repRanges, .repChanges, .yearlyRecords, .recency, .squatSuccess:
            return [.original, .bar, .scatter, .table]
        case .effort, .exerciseOrder, .relationship, .typicalBench:
            return [.original, .scatter, .table]
        case .duration, .goal, .milestones:
            return [.original, .line, .scatter, .table]
        case .gluteSources, .records, .skipped, .substitutions, .repMix, .tonnage:
            return [.original, .bar, .scatter]
        case .lastCurl, .missingEstimates:
            return [.original, .bar, .line, .scatter]
        case .sessionLedger:
            return [.original]
        }
    }

    var transposeLabel: String? {
        switch id {
        case .legWork, .frequency, .repRanges: "Swap rows and columns"
        case .armReps, .repChanges, .recency: "Swap axes"
        default: nil
        }
    }

    var supportsTranspose: Bool { transposeLabel != nil }

    func presented(as style: StudyPresentation, transpose: Bool) -> Self {
        var result = self
        let style = availablePresentations.contains(style) ? style : .original
        result.presentation = style
        guard figure != nil else { return result }
        if case .matrix(let columns, let rows, let values) = figure {
            let axes = matrixAxes(transposed: transpose)
            result.xLabel = axes.column
            result.yLabel = axes.row
            if transpose {
                let swapped = columns.indices.map { col in rows.indices.map { row in values[row][col] } }
                result.figure = .matrix(columns: rows, rows: columns, values: swapped)
            }
        }
        if style == .table {
            // These source tables include observations such as the actual set or the paired week.
            let sourceTable: StudyTable?
            switch id {
            case .legMax, .relationship, .exerciseOrder, .yearlyRecords, .repeatBench, .pushups, .blocks, .benchSets, .effort:
                sourceTable = detail
            default:
                sourceTable = nil
            }
            if let values = sourceTable ?? result.plottedValues {
                if sourceTable == nil {
                    switch result.figure {
                    case .traces, .attempts, .matrix: result.readingFigure = result.figure
                    default: break
                    }
                }
                result.figure = .table(values)
            }
            result.detail = nil
            if id == .squatSuccess {
                result.summary =
                    "For each actual opening load, Made counts the sets that reached the prescribed reps. Attempts includes every logged opening set with that target."
            }
            return result
        }

        switch result.figure {
        case .traces(let series, let dates) where style != .original:
            let visible = id == .relationship && style == .scatter ? series.filter { $0.style != .fit } : series
            result.figure = .traces(visible.map { $0.presented(as: style) }, dates: dates)
        case .liftPanels(let series) where style != .original:
            result.figure = .liftPanels(series.map { $0.presented(as: style) })
        case .matrix(let columns, let rows, let values) where style != .original:
            let axis = matrixAxes(transposed: transpose)
            result.xLabel = axis.column
            result.yLabel = axis.value
            let timeIsRows = timeline.map { $0.buckets.map(\.label) == rows } ?? false
            var bars: [StudyBar]
            if timeIsRows && id == .frequency {
                // One series per weekday: the weekday totals, or one dot for each week.
                bars = columns.indices.flatMap { col in
                    let cells = rows.indices.compactMap { values[$0][col] }
                    return style == .bar ? [StudyBar(label: columns[col], value: cells.reduce(0, +))]
                        : cells.map { StudyBar(label: columns[col], value: $0) }
                }
            } else if timeIsRows {
                // Time stays on its own axis and the other dimension names the series, so a legend never lists weeks.
                bars = rows.indices.flatMap { row in
                    columns.indices.compactMap { col in
                        values[row][col].map { StudyBar(label: rows[row], value: $0, group: columns[col]) }
                    }
                }
                result.horizontalCategories = true
                result.xLabel = axis.value
                result.yLabel = axis.row
            } else {
                bars = columns.indices.flatMap { col in
                    rows.indices.compactMap { row in
                        values[row][col].map { StudyBar(label: columns[col], value: $0, group: rows[row]) }
                    }
                }
            }
            result.figure = .bars(bars)
        case .comparison(let points, _) where style == .bar:
            result.xLabel = yLabel
            result.yLabel = xLabel
            result.figure = .bars(points.map { StudyBar(label: $0.category, value: $0.value, group: $0.series) })
        case .comparison(let points, _) where style == .scatter:
            result.figure = .comparison(points, connected: false)
        case .attempts(let counts) where style != .original:
            result.xLabel = "Opening load"
            result.yLabel = "Reached target (%)"
            result.readingFigure = result.figure
            result.figure = .bars(
                counts.filter { $0.attempts > 0 }.map {
                    StudyBar(label: $0.label, value: 100 * Double($0.made) / Double($0.attempts))
                })
            result.detail = plottedValues
            result.summary =
                "Each value is the percentage of logged opening sets that reached their prescribed rep target at that load."
        case .table(let original) where style != .original && !alternateBars.isEmpty:
            result.figure = .bars(alternateBars)
            result.detail = original
        case .bars where transpose:
            result.horizontalCategories = true
            result.xLabel = yLabel
            result.yLabel = xLabel
        default:
            break
        }
        if case .bars(let bars) = result.figure { result.figure = .bars(Self.limitingSeries(bars, sums: style != .scatter)) }
        return result
    }

    /// More than six series keep the five largest and fold the rest into "Other".
    static func limitingSeries(_ bars: [StudyBar], sums: Bool) -> [StudyBar] {
        let groups = bars.map(\.group).studyUnique
        guard groups.count > StudyAxisPlan.maximumSeries else { return bars }
        let totals = groups.map { group in (group, bars.filter { $0.group == group }.reduce(0) { $0 + abs($1.value) }) }
        let kept = Set(StudyAxisPlan.keptSeries(totals.map { (name: $0.0, total: $0.1) }))
        guard sums else {
            return bars.filter { kept.contains($0.group) }
                + bars.filter { !kept.contains($0.group) }.map { StudyBar(label: $0.label, value: $0.value, group: "Other") }
        }
        var merged = bars.filter { kept.contains($0.group) }
        var other: [(label: String, value: Double)] = []
        for bar in bars where !kept.contains(bar.group) {
            if let index = other.firstIndex(where: { $0.label == bar.label }) {
                other[index].value += bar.value
            } else {
                other.append((bar.label, bar.value))
            }
        }
        merged += other.map { StudyBar(label: $0.label, value: $0.value, group: "Other") }
        return merged
    }

    var legendLabels: [String] {
        switch figure {
        case .traces(let series, _): series.map(\.name)
        case .bars(let bars): bars.map(\.group).filter { !$0.isEmpty }.studyUnique
        case .comparison(let points, _): points.map(\.series).studyUnique
        default: []
        }
    }

    var plottedValues: StudyTable? {
        switch figure {
        case .traces(let series, let dates):
            return seriesTable(series, dates: dates)
        case .liftPanels(let series):
            return seriesTable(series, dates: true)
        case .bars(let bars):
            let columns = horizontalCategories ? [yLabel, "Series", xLabel] : [xLabel, "Series", yLabel]
            return StudyTable(
                columns: columns,
                rows: bars.map {
                    [$0.label, $0.group.isEmpty ? "—" : $0.group, $0.value.studyNumber]
                })
        case .comparison(let points, _):
            return StudyTable(
                columns: [yLabel, "Series", xLabel],
                rows: points.map {
                    [$0.category, $0.series, $0.value.studyNumber]
                })
        case .attempts(let counts):
            return StudyTable(
                columns: ["Opening load", "Made", "Attempts"],
                rows: counts.map {
                    [$0.label, String($0.made), String($0.attempts)]
                })
        case .matrix(let columns, let rows, let values):
            return StudyTable(
                columns: [yLabel.isEmpty ? matrixAxes(transposed: false).row : yLabel] + columns,
                rows: rows.indices.map { row in
                    [rows[row]] + values[row].map { $0?.studyNumber ?? "—" }
                })
        case .table(let table):
            return table
        case nil:
            return nil
        }
    }

    private func seriesTable(_ series: [StudySeries], dates: Bool) -> StudyTable {
        let rows = series.flatMap { trace in
            trace.points.map { point in
                let x =
                    dates
                    ? Date(timeIntervalSince1970: point.x).formatted(date: .abbreviated, time: .omitted)
                    : point.x.studyNumber
                return [trace.name, x, point.y.studyNumber]
            }
        }
        return StudyTable(columns: ["Series", xLabel, yLabel], rows: rows)
    }

    private func matrixAxes(transposed: Bool) -> (column: String, row: String, value: String) {
        let week = timeline?.noun ?? "Week"
        return switch id {
        case .legWork: (transposed ? "Muscle" : week, transposed ? week : "Muscle", "Credited sets")
        case .frequency: (transposed ? week : "Weekday", transposed ? "Weekday" : week, "Working sets")
        default: (transposed ? "Exercise" : "Rep range", transposed ? "Rep range" : "Exercise", "Working sets")
        }
    }
}

extension StudySeries {
    fileprivate func presented(as style: StudyPresentation) -> Self {
        var series = self
        // Targets, reference intervals and fitted averages remain reference lines in any view.
        guard self.style != .fit else { return series }
        switch style {
        case .bar: series.style = .bars
        case .scatter: series.style = .dots
        case .line: series.style = self.style == .step ? .step : .line
        default: break
        }
        return series
    }
}

extension Array where Element == String {
    var studyUnique: [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
