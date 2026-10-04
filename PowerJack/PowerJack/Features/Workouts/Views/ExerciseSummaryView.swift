//
//  ExerciseSummaryView.swift
//  PowerJack
//
//  Shown after a workout is finished: completed sets per muscle as bars
//  that grow in one row at a time.
//

import SwiftUI

struct ExerciseSummaryView: View {
    /// Lets the screen finish sliding in before the first row appears.
    private static let startDelay: TimeInterval = 0.35
    private static let fadeDuration: TimeInterval = 0.35
    private static let growDuration: TimeInterval = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sorted most sets first, as `Workout.completedSetsByMuscle` returns them.
    let setCounts: [MuscleSetCount]
    let onContinue: () -> Void

    /// Rows whose label is on screen.
    @State private var shownRows = 0
    /// Rows whose bar has grown to its full length.
    @State private var filledRows = 0

    private var mostSets: Int { setCounts.map(\.sets).max() ?? 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text("Workout complete!")
                    .font(.largeTitle.bold())

                Text("Today you did")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                    ForEach(Array(setCounts.enumerated()), id: \.element.id) { index, setCount in
                        GridRow {
                            Text(setCount.muscle.rawValue.capitalized)
                                .font(.headline)
                                .opacity(index < shownRows ? 1 : 0)

                            SetCountBar(
                                sets: setCount.sets,
                                fraction: Double(setCount.sets) / Double(mostSets),
                                progress: index < filledRows ? 1 : 0
                            )
                        }
                    }
                }
                .padding(.top, LayoutMetrics.compactSpacing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutMetrics.sectionSpacing)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onContinue) {
                Text("Next Workout")
                    .font(.title3)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.glassProminent)
            .padding(LayoutMetrics.sectionSpacing)
        }
        .task {
            try? await revealRows()
        }
    }

    /// Shows each row in turn: the label, then its bar grows to length while the count climbs.
    private func revealRows() async throws {
        guard !reduceMotion else {
            shownRows = setCounts.count
            filledRows = setCounts.count
            return
        }

        try await Task.sleep(for: .seconds(Self.startDelay))
        for index in setCounts.indices {
            withAnimation(.easeOut(duration: Self.fadeDuration)) {
                shownRows = index + 1
            }
            try await Task.sleep(for: .seconds(Self.fadeDuration))

            withAnimation(.easeOut(duration: Self.growDuration)) {
                filledRows = index + 1
            }
            try await Task.sleep(for: .seconds(Self.growDuration))
        }
    }
}

/// A bar sized against the row with the most sets, with the set count riding at its end.
/// `progress` is animatable, so the count climbs frame by frame as the bar grows.
private struct SetCountBar: View, Animatable {
    private static let height: CGFloat = 28
    /// Room kept at the end of the longest bar for the count, e.g. "12 sets".
    private static let countWidth: CGFloat = 76

    let sets: Int
    let fraction: Double
    /// 0 is an empty bar, 1 is full length.
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var shownSets: Int { Int(Double(sets) * progress) }

    var body: some View {
        GeometryReader { proxy in
            let fullWidth = max(0, proxy.size.width - Self.countWidth)

            HStack(spacing: LayoutMetrics.compactSpacing) {
                Capsule()
                    .fill(.tint)
                    .frame(width: fullWidth * fraction * progress)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(shownSets)")
                        .font(.headline.monospacedDigit())
                    Text(shownSets == 1 ? "set" : "sets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                .opacity(progress > 0 ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(sets == 1 ? "1 set" : "\(sets) sets")
    }
}

#Preview("ExerciseSummaryView") {
    ExerciseSummaryView(
        setCounts: [
            MuscleSetCount(muscle: .chest, sets: 6),
            MuscleSetCount(muscle: .back, sets: 3),
            MuscleSetCount(muscle: .triceps, sets: 2),
            MuscleSetCount(muscle: .biceps, sets: 1),
        ],
        onContinue: {}
    )
}
