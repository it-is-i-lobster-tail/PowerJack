import Charts
import SwiftUI

extension ProgramExerciseHistory {
    struct MaxEstimate {
        let tenthsPounds: Int
        let hasRecordedRIR: Bool

        static func best(in estimates: [Self]) -> Self? {
            estimates.max {
                if $0.tenthsPounds == $1.tenthsPounds { return !$0.hasRecordedRIR && $1.hasRecordedRIR }
                return $0.tenthsPounds < $1.tenthsPounds
            }
        }
    }

    var personalBest: MaxEstimate? { MaxEstimate.best(in: sets.compactMap(estimate)) }

    func estimate(_ set: LoggedSet) -> MaxEstimate? {
        guard supportsLoadEstimate else { return nil }
        return Self.estimate(load: set.load, reps: set.reps, rating: set.repsInReserve)
    }

    static func estimate(load: Int?, reps: Int?, rating: RepsInReserve?) -> MaxEstimate? {
        guard let load, load > 0, let reps, reps > 0,
              reps <= StrengthRules.e1rmMaxReps else { return nil }
        let rir = rating?.rawValue ?? 0
        let repsToFailure = reps + rir
        guard rir <= StrengthRules.e1rmMaxRIR, repsToFailure <= StrengthRules.e1rmMaxReps else { return nil }

        let estimate = Double(load) * 36 / Double(37 - repsToFailure)
        return MaxEstimate(tenthsPounds: Int(estimate.rounded()), hasRecordedRIR: rating != nil)
    }
}

struct OneRepMaxChart: View {
    let exercise: ProgramExerciseHistory
    let personalBest: ProgramExerciseHistory.MaxEstimate?
    let unit: WeightUnit

    private struct Point: Identifiable {
        let id: ProgramExerciseHistory.Session.ID
        let date: Date
        let estimate: ProgramExerciseHistory.MaxEstimate
    }

    private let points: [Point]
    private let first: Point
    private let last: Point

    init?(exercise: ProgramExerciseHistory, personalBest: ProgramExerciseHistory.MaxEstimate?, unit: WeightUnit) {
        let points = exercise.sessions.compactMap { session -> Point? in
            let sets = exercise.sets[(session.firstSet - 1)..<session.lastSet]
            guard let date = session.date,
                  let best = ProgramExerciseHistory.MaxEstimate.best(in: sets.compactMap(exercise.estimate))
            else { return nil }
            return Point(id: session.id, date: date, estimate: best)
        }.sorted { $0.date < $1.date }
        guard let first = points.first, let last = points.last else { return nil }
        self.exercise = exercise
        self.personalBest = personalBest
        self.unit = unit
        self.points = points
        self.first = first
        self.last = last
    }

    /// Pinching zooms the time axis. Inline and full screen share the visible stretch.
    @State private var zoom: ClosedRange<Double>?

    var body: some View {
        FullScreenTrendChart(title: exercise.name, inlineHeight: 150) { height in
            VStack(alignment: .leading, spacing: 8) {
                if let height {
                    LabeledContent("Personal best · estimated") {
                        Text(personalBest.map(weight) ?? "—")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }
                    .font(.subheadline)
                    Text("Estimated one-rep max over time (\(unit.symbol))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    plot.frame(height: height + 22)
                } else {
                    plot.frame(maxHeight: .infinity)
                }
            }
        }
    }

    private var times: [Double] { points.map(\.date.timeIntervalSince1970) }

    private var plot: some View {
        let window = TimeAxisWindow(times: times, fraction: zoom)
        let start = window.isZoomed ? Date(timeIntervalSince1970: window.visible.lowerBound) : first.date
        let end = window.isZoomed ? Date(timeIntervalSince1970: window.visible.upperBound) : last.date
        return VStack(alignment: .leading, spacing: 8) {
            trend(points)
            HStack {
                Text(start, format: .dateTime.month(.abbreviated).day().year())
                if start != end {
                    Spacer()
                    Text(end, format: .dateTime.month(.abbreviated).day().year())
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, 42)
        }
    }

    private func trend(_ points: [Point]) -> some View {
        let values = points.map { unit.value(fromTenthsPounds: $0.estimate.tenthsPounds) }
        let scale = ComparisonAxisScale(values: values, wholeNumbers: false)
        return Chart(points) { point in
            let load = unit.value(fromTenthsPounds: point.estimate.tenthsPounds)
            LineMark(x: .value("Date", point.date), y: .value("Estimated max", load))
                .foregroundStyle(Color.accentColor)
            PointMark(x: .value("Date", point.date), y: .value("Estimated max", load))
                .foregroundStyle(Color.accentColor)
                .accessibilityValue(weight(point.estimate))
        }
        .chartYScale(domain: scale.lowerBound...scale.upperBound)
        .chartYAxis(.hidden)
        .modifier(TimeAxisZoom(times: times, showsAxis: false, padding: 6, fraction: $zoom))
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let plot = geometry[anchor]
                    ForEach(scale.tickPositions, id: \.self) { position in
                        let tick = scale.value(at: position)
                        if let y = proxy.position(forY: tick) {
                            Rectangle().fill(.secondary.opacity(0.2))
                                .frame(width: plot.width, height: 1)
                                .position(x: plot.midX, y: plot.minY + y)
                            Text(tick, format: .number.precision(.fractionLength(0...1)))
                                .frame(width: 36, alignment: .trailing)
                                .position(x: plot.minX - 22, y: plot.minY + y)
                        }
                    }
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .padding(.leading, 42)
        .padding(.vertical, 5)
    }

    private func weight(_ estimate: ProgramExerciseHistory.MaxEstimate) -> String {
        "\(unit.format(tenthsPounds: estimate.tenthsPounds)) \(unit.symbol)"
    }
}
