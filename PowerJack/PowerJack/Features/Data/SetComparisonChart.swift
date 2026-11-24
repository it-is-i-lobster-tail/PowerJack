import Charts
import SwiftUI

struct SetComparisonChart: View {
    let sets: [ProgramExerciseHistory.LoggedSet]

    enum Metric: String, CaseIterable {
        case reps = "Reps"
        case weight = "Weight"

        var target: KeyPath<ProgramExerciseHistory.LoggedSet, Int?> {
            self == .reps ? \.targetReps : \.targetLoad
        }

        var actual: KeyPath<ProgramExerciseHistory.LoggedSet, Int?> {
            self == .reps ? \.reps : \.load
        }

        var complementary: Self { self == .reps ? .weight : .reps }
    }

    var metric: Metric = .reps
    var unit: WeightUnit = .pounds

    private enum TargetComparison {
        case atTarget
        case aboveTarget
        case belowTarget
        case unavailable

        func label(for metric: Metric) -> String {
            switch self {
            case .atTarget: metric == .weight ? "At weight" : "At reps"
            case .aboveTarget: metric == .weight ? "Above weight" : "More reps"
            case .belowTarget: metric == .weight ? "Below weight" : "Less reps"
            case .unavailable: "No \(metric.rawValue.lowercased()) comparison"
            }
        }

        init(target: Int?, actual: Int?) {
            guard let target, let actual else {
                self = .unavailable
                return
            }
            if actual == target {
                self = .atTarget
            } else {
                self = actual > target ? .aboveTarget : .belowTarget
            }
        }

        var color: Color {
            switch self {
            case .atTarget: .blue
            case .aboveTarget: .green
            case .belowTarget: .orange
            case .unavailable: .gray
            }
        }
    }

    private enum Effort: String {
        case zero = "0 RIR"
        case oneToThree = "1–3 RIR"
        case fourOrMore = "4+ RIR"
        case unrecorded = "RIR unrecorded"

        init(_ rating: RepsInReserve?) {
            switch rating {
            case .some(.zero): self = .zero
            case .some(.one), .some(.two), .some(.three): self = .oneToThree
            case .some(.four), .some(.fiveOrMore): self = .fourOrMore
            case nil: self = .unrecorded
            }
        }

        var area: CGFloat {
            switch self {
            case .zero: 100
            case .oneToThree: 50
            case .fourOrMore: 16
            case .unrecorded: 30
            }
        }
    }

    var body: some View {
        let paired = sets.filter { $0[keyPath: metric.target] != nil && $0[keyPath: metric.actual] != nil }
        if paired.isEmpty {
            Text(metric == .reps ? "No completed sets with a rep target." : "No completed sets with a weight target.")
                .foregroundStyle(.secondary)
        } else {
            let upper = paired.reduce(1.0) { upper, set in
                max(upper, value(set[keyPath: metric.target] ?? 0), value(set[keyPath: metric.actual] ?? 0))
            }
            let quantity = metric == .reps ? "reps" : "weight (\(unit.symbol))"
            let tickStep = max(1, ceil(upper / 5))
            let ticks = Array(stride(from: 0.0, through: upper, by: tickStep))
            VStack(alignment: .leading, spacing: 8) {
                Text("Actual \(quantity)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Chart(paired) { set in
                    if let target = set[keyPath: metric.target], let actual = set[keyPath: metric.actual] {
                        let comparison = TargetComparison(target: set[keyPath: metric.complementary.target],
                                                          actual: set[keyPath: metric.complementary.actual])
                        let effort = Effort(set.repsInReserve)
                        PointMark(x: .value("Target", value(target)),
                                  y: .value("Actual", value(actual)))
                            .foregroundStyle(comparison.color)
                            .symbolSize(effort.area)
                            .opacity(0.8)
                            .accessibilityLabel(Text(verbatim: "Set \(set.id)"))
                            .accessibilityValue(Text(verbatim: "Target \(display(target)), actual \(display(actual)). \(comparison.label(for: metric.complementary)). \(set.repsInReserve?.label ?? effort.rawValue)"))
                    }
                }
                .chartXScale(domain: 0...upper, range: .plotDimension(startPadding: 6, endPadding: 6))
                .chartYScale(domain: 0...upper, range: .plotDimension(startPadding: 6, endPadding: 6))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let frame = proxy.plotFrame {
                            let plot = geometry[frame]
                            ForEach(ticks, id: \.self) { tick in
                                if let x = proxy.position(forX: tick), let y = proxy.position(forY: tick) {
                                    Rectangle()
                                        .fill(.secondary.opacity(0.2))
                                        .frame(width: plot.width, height: 1)
                                        .position(x: plot.midX, y: plot.minY + y)
                                    Rectangle()
                                        .fill(.secondary.opacity(0.14))
                                        .frame(width: 1, height: plot.height)
                                        .position(x: plot.minX + x, y: plot.midY)
                                    axisTick(tick)
                                        .frame(width: 34, alignment: .trailing)
                                        .position(x: plot.minX - 21, y: plot.minY + y)
                                    axisTick(tick)
                                        .position(x: plot.minX + x, y: plot.maxY + 9)
                                }
                            }
                        }
                    }
                    .accessibilityHidden(true)
                }
                .padding(.leading, 38)
                .padding(.trailing, 12)
                .padding(.bottom, 14)
                Text("Target \(quantity)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        ForEach([TargetComparison.atTarget, .aboveTarget, .belowTarget], id: \.self) { comparison in
                            legendItem(comparison.label(for: metric.complementary), color: comparison.color, diameter: 8)
                        }
                    }
                    HStack(spacing: 12) {
                        ForEach([Effort.zero, .oneToThree, .fourOrMore], id: \.self) { effort in
                            let diameter = (4 * effort.area / .pi).squareRoot()
                            legendItem(effort.rawValue, color: .gray, diameter: diameter)
                        }
                    }
                }
            }
        }
    }

    private func value(_ raw: Int) -> Double {
        metric == .reps ? Double(raw) : unit.value(fromTenthsPounds: raw)
    }

    private func axisTick(_ value: Double) -> some View {
        Text(value, format: .number.precision(.fractionLength(0)))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private func display(_ raw: Int) -> String {
        metric == .reps ? "\(raw) reps" : "\(unit.format(tenthsPounds: raw)) \(unit.symbol)"
    }

    private func legendItem(_ title: String, color: Color, diameter: CGFloat) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Target vs. actual reps") {
    let reps = [(8, 6), (8, 8), (8, 10), (10, 9), (10, 11), (12, 12)]
    let loads: [Int?] = [500, 500, 550, 450, 550, nil]
    let ratings: [RepsInReserve?] = [.zero, .one, .four, .two, .fiveOrMore, nil]
    let sets = reps.enumerated().map { index, pair in
        ProgramExerciseHistory.LoggedSet(id: index + 1, sessionIndex: 0,
                                         targetReps: pair.0, reps: pair.1,
                                         targetLoad: 500, load: loads[index], repsInReserve: ratings[index])
    }
    SetComparisonChart(sets: sets)
        .frame(height: 220)
        .padding()
}
