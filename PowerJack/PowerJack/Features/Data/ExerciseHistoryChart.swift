import SwiftUI

struct ExerciseHistoryChart: View {
    let exercise: ProgramExerciseHistory
    let unit: WeightUnit

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metric: SetComparisonChart.Metric? = .reps

    var body: some View {
        ExpandableDataChart(title: exercise.name, height: 220, minimumSpan: 1, headerAccessory: { metricPill }) { _ in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(SetComparisonChart.Metric.allCases, id: \.self) { page in
                        SetComparisonChart(sets: exercise.sets, metric: page, unit: unit)
                            .frame(maxHeight: .infinity)
                            .containerRelativeFrame(.horizontal)
                            .scrollTransition(reduceMotion ? .identity : .interactive, axis: .horizontal) { plot, phase in
                                plot
                                    .rotationEffect(.degrees(3 * phase.value))
                                    .scaleEffect(1 - 0.02 * abs(phase.value))
                            }
                            .clipped()
                            .accessibilityHidden(page != (metric ?? .reps))
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .clipped()
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .defaultScrollAnchor(metric == .weight ? .trailing : .leading, for: .initialOffset)
            .scrollPosition(id: $metric, anchor: .center)
        }
    }

    private var metricPill: some View {
        let selected = metric ?? .reps
        return Button {
            select(selected == .reps ? .weight : .reps)
        } label: {
            HStack(spacing: 5) {
                Text(selected.rawValue)
                    .font(.caption.weight(.semibold))
                ForEach(SetComparisonChart.Metric.allCases, id: \.self) { page in
                    Circle()
                        .fill(Color.primary.opacity(page == selected ? 1 : 0.3))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Comparison chart")
        .accessibilityValue(selected.rawValue)
        .accessibilityHint("Switches between reps and weight")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(.weight)
            case .decrement: select(.reps)
            @unknown default: break
            }
        }
    }

    private func select(_ page: SetComparisonChart.Metric) {
        withAnimation(reduceMotion ? nil : .snappy) {
            metric = page
        }
    }
}

struct WorkoutSetsDetail: View {
    let exercise: ProgramExerciseHistory
    let session: ProgramExerciseHistory.Session
    let unit: WeightUnit

    var body: some View {
        List {
            Section("\(session.programName) · Week \(session.week) · Day \(session.day)") {
                if let date = session.date { Text(date, style: .date) }
                LabeledContent("Last-set RIR", value: session.ratings.map { $0?.valueText ?? "—" }.joined(separator: ", "))
            }
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    GridRow { Text("Set"); Text("Target"); Text("Actual") }.font(.caption.bold())
                    ForEach(exercise.sets[(session.firstSet - 1)..<session.lastSet]) { set in
                        GridRow {
                            Text("\(set.id)")
                            Text(prescription(load: set.targetLoad, reps: set.targetReps))
                            Text(prescription(load: set.load, reps: set.reps))
                        }.font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prescription(load: Int?, reps: Int?) -> String {
        let weight = load.map { "\(unit.format(tenthsPounds: $0)) \(unit.symbol)" }
        let reps = reps.map { "\($0) reps" }
        let value = [weight, reps].compactMap { $0 }.joined(separator: " × ")
        return value.isEmpty ? "—" : value
    }
}
