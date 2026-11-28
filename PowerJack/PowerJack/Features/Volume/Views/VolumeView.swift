//
//  VolumeView.swift
//  PowerJack
//
//  The user's training history: average working sets per week for every muscle,
//  colored by what that volume means for growth.
//

import Charts
import SwiftUI

struct VolumeView: View {
    let logs: [WorkoutLog]
    let currentProgram: Program?
    let range: VolumeRange
    var dateFilter: WorkoutDateFilter?
    var selectedMuscles: Set<Muscle> = []
    var searchMuscles: Set<Muscle>?
    let isLandscape: Bool

    private var muscles: [Muscle] {
        Muscle.allCases.filter { selectedMuscles.isEmpty || selectedMuscles.contains($0) }
    }

    private func bars(for averages: [Muscle: Double]) -> [MuscleBar] {
        muscles.filter { searchMuscles?.contains($0) ?? true }.map { muscle in
            let sets = averages[muscle] ?? 0
            let tier = VolumeTier(weeklySets: sets)
            return MuscleBar(muscle: muscle, value: sets, color: tier.color, accessibilityNote: tier.name)
        }
    }

    var body: some View {
        let averages = WeeklyVolume.averages(of: logs, in: range, currentProgram: currentProgram, dateFilter: dateFilter)
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {

            if dateFilter == nil && range == .currentProgram && currentProgram == nil {
                Text("Average working sets per week").font(.headline)
                Text("Start a program to see its weekly volume.")
                    .foregroundStyle(.secondary)
            } else if logs.isEmpty || (dateFilter != nil && averages.isEmpty) {
                Text("Average working sets per week").font(.headline)
                Text(dateFilter.map { "No workouts logged for \($0.name) with these filters." }
                     ?? "No workouts logged for these filters.")
                    .foregroundStyle(.secondary)
            } else {
                let bars = bars(for: averages)
                ExpandableDataChart(title: "Average working sets per week",
                                    height: min(400, CGFloat(bars.count) * 32 + 32),
                                    minimumSpan: 0.08) { window in
                    WeeklySetsPlot(bars: bars, window: window)
                }
                .id(ChartRange(preset: range, dates: dateFilter))
                VolumeLegend()
                Divider()
                VolumeTrendChart(points: WeeklyVolume.trend(of: logs, in: range, currentProgram: currentProgram,
                                                            dateFilter: dateFilter,
                                                            selectedMuscles: selectedMuscles),
                                 muscles: muscles, isLandscape: isLandscape, searchMuscles: searchMuscles)
            }
        }
    }

    private struct ChartRange: Hashable {
        let preset: VolumeRange
        let dates: WorkoutDateFilter?
    }
}

private struct VolumeTrendChart: View {
    let points: [WeeklyVolume.TrendPoint]
    let muscles: [Muscle]
    let isLandscape: Bool
    let searchMuscles: Set<Muscle>?
    @Environment(\.colorScheme) private var colorScheme
    @State private var highlights: Set<Muscle> = []
    @State private var searchHighlights: Set<Muscle>?

    private var visibleHighlights: Set<Muscle> {
        (searchHighlights ?? searchMuscles ?? highlights).intersection(muscles)
    }
    private var legendColumns: [GridItem] {
        if isLandscape {
            return Array(repeating: GridItem(.flexible(), alignment: .leading), count: 6)
        }
        return [GridItem(.adaptive(minimum: 90), alignment: .leading)]
    }

    var body: some View {
        Group {
            if points.isEmpty {
                Text("Weekly Working Sets Over Time").font(.headline)
                Text("No completed weeks with workouts in this range.")
                    .foregroundStyle(.secondary)
            } else {
                FullScreenTrendChart(title: "Weekly Working Sets Over Time", inlineHeight: 200) { height in
                    trendContent(height: height)
                }
            }
        }
        .onChange(of: searchMuscles) { searchHighlights = nil }
    }

    /// A nil height is full screen: the graph fills the space and keeps its muscle key, without the caption.
    private func trendContent(height: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if height != nil {
                Text("Secondary muscles count as half a set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(muscles.filter { !visibleHighlights.contains($0) } + muscles.filter { visibleHighlights.contains($0) }) { muscle in
                    let name = muscle.rawValue.capitalized
                    let ink = color(for: muscle).opacity(isHighlighted(muscle) ? 1 : 0.12)
                    ForEach(points) { point in
                        let sets = point.setsByMuscle[muscle, default: 0]
                        let series = point.periodStart.map { "\(name)-\($0.timeIntervalSinceReferenceDate)" } ?? name
                        LineMark(x: .value("Week", point.week), y: .value("Working sets", sets),
                                 series: .value("Muscle", series))
                            .foregroundStyle(ink)
                        PointMark(x: .value("Week", point.week), y: .value("Working sets", sets))
                            .foregroundStyle(ink)
                            .symbolSize(12)
                            .accessibilityLabel(name)
                    }
                }
            }
            .chartYScale(domain: 0...upper, range: .plotDimension(startPadding: 5, endPadding: 5))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let frame = proxy.plotFrame {
                        axisLabels(proxy: proxy, plot: geometry[frame])
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.leading, 26)
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
            .frame(height: height)
            .frame(maxHeight: height == nil ? .infinity : nil)

            LazyVGrid(columns: legendColumns, spacing: 6) {
                ForEach(muscles) { muscle in
                    Button {
                        var next = visibleHighlights
                        if next.remove(muscle) == nil { next.insert(muscle) }
                        if searchMuscles != nil { searchHighlights = next } else { highlights = next }
                    } label: {
                        Label {
                            Text(muscle.rawValue.capitalized)
                        } icon: {
                            Circle()
                                .fill(color(for: muscle).opacity(isHighlighted(muscle) ? 1 : 0.22))
                                .frame(width: 8, height: 8)
                        }
                        .font(.caption.weight(visibleHighlights.contains(muscle) ? .semibold : .regular))
                        .foregroundStyle(isHighlighted(muscle) ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(visibleHighlights.contains(muscle) ? .isSelected : [])
                    .accessibilityHint("Toggles highlight on the chart")
                }
            }
        }
    }

    private func isHighlighted(_ muscle: Muscle) -> Bool {
        visibleHighlights.isEmpty || visibleHighlights.contains(muscle)
    }

    private var upper: Double {
        max(1, ceil(points.flatMap { $0.setsByMuscle.values }.max() ?? 0))
    }

    private func color(for muscle: Muscle) -> Color {
        WorkoutChartPalette.color(at: Muscle.allCases.firstIndex(of: muscle) ?? 0, scheme: colorScheme)
    }

    private func axisLabels(proxy: ChartProxy, plot: CGRect) -> some View {
        let step = max(1, ceil(upper / 4))
        let ticks = Array(stride(from: 0.0, through: upper, by: step))
        let showsYear = points.first?.periodStart != points.last?.periodStart
        let labelWidth: CGFloat = showsYear ? 74 : 62
        var dateTicks: [(date: Date, x: CGFloat)] = []
        for point in points {
            guard let x = proxy.position(forX: point.week) else { continue }
            if let last = dateTicks.last, x - last.x < labelWidth { continue }
            dateTicks.append((point.week, x))
        }
        return ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.self) { tick in
                if let y = proxy.position(forY: tick) {
                    Rectangle()
                        .fill(.secondary.opacity(0.2))
                        .frame(width: plot.width, height: 1)
                        .position(x: plot.midX, y: plot.minY + y)
                    Text(tick, format: .number.precision(.fractionLength(0)))
                        .frame(width: 26, alignment: .trailing)
                        .position(x: plot.minX - 18, y: plot.minY + y)
                }
            }
            ForEach(dateTicks, id: \.date) { tick in
                Text(tick.date, format: showsYear
                     ? .dateTime.month(.abbreviated).day().year(.twoDigits)
                     : .dateTime.month(.abbreviated).day())
                    .fixedSize()
                    .position(x: plot.minX + tick.x, y: plot.maxY + 10)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct WeeklySetsPlot: View {
    let bars: [MuscleBar]
    let window: ClosedRange<Double>

    var body: some View {
        let upper = max(1, ceil(bars.map(\.value).max() ?? 1))
        let domain = (upper * window.lowerBound)...(upper * window.upperBound)
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            ForEach(bars) { bar in
                GridRow {
                    Text(bar.muscle.rawValue.capitalized)
                    GeometryReader { geometry in
                        let portion = (bar.value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
                        Capsule()
                            .fill(bar.color ?? .accentColor)
                            .frame(width: geometry.size.width * min(1, max(0, portion)),
                                   height: min(18, geometry.size.height * 0.62))
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    Text(bar.value, format: .number.precision(.fractionLength(0...1)))
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
                .font(.subheadline)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(bar.muscle.rawValue.capitalized)
                .accessibilityValue("\(bar.value.formatted(.number.precision(.fractionLength(0...1)))) sets per week, \(bar.accessibilityNote ?? "")")
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                HStack {
                    Text(domain.lowerBound, format: .number.precision(.fractionLength(0...1)))
                    Spacer()
                    Text(domain.upperBound, format: .number.precision(.fractionLength(0...1)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }
}

/// What each bar color means.
private struct VolumeLegend: View {
    private static let swatchSize: CGFloat = 12

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: LayoutMetrics.compactSpacing, verticalSpacing: 6) {
            ForEach(VolumeTier.allCases) { tier in
                GridRow {
                    Circle()
                        .fill(tier.color)
                        .frame(width: Self.swatchSize, height: Self.swatchSize)
                    Text(tier.name)
                    Text("\(tier.setRange) sets")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.subheadline)
    }
}
