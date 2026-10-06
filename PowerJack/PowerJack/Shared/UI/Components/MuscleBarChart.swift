//
//  MuscleBarChart.swift
//  PowerJack
//
//  One labeled bar per muscle, sized against the longest bar, with the value riding at its end.
//  Used by the workout summary and the Volume tab.
//

import SwiftUI

struct MuscleBar: Identifiable, Equatable {
    let muscle: Muscle
    let value: Double
    /// `nil` uses the app's tint.
    var color: Color? = nil
    /// Read by VoiceOver after the value, e.g. a volume tier.
    var accessibilityNote: String? = nil

    var id: Muscle { muscle }
}

struct MuscleBarChart: View {
    enum Reveal {
        /// Each row fades in and then grows, one at a time. Suits a short list shown once.
        case rowByRow
        /// Every bar grows at once, and later changes animate in place.
        case together
    }

    private static let startDelay: TimeInterval = 0.35
    private static let fadeDuration: TimeInterval = 0.35
    private static let growDuration: TimeInterval = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let bars: [MuscleBar]
    var reveal: Reveal = .together
    /// Decimal places shown for values, e.g. 0 for whole sets.
    var fractionDigits = 0
    /// Short unit after the value, e.g. "sets". `nil` shows the number alone.
    var unit: ((Double) -> String)? = nil
    /// Unit read by VoiceOver, e.g. "sets per week".
    var spokenUnit = "sets"

    /// Rows whose label is on screen.
    @State private var shownRows = 0
    /// Rows whose bar has grown to its full length.
    @State private var filledRows = 0

    private var longestValue: Double { max(bars.map(\.value).max() ?? 0, 1) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                GridRow {
                    Text(bar.muscle.rawValue.capitalized)
                        .font(.headline)
                        .opacity(index < shownRows ? 1 : 0)

                    ValueBar(
                        value: bar.value,
                        fraction: bar.value / longestValue,
                        progress: index < filledRows ? 1 : 0,
                        color: bar.color,
                        fractionDigits: fractionDigits,
                        unit: unit
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(bar.muscle.rawValue.capitalized)
                .accessibilityValue(accessibilityValue(for: bar))
            }
        }
        .animation(.easeOut(duration: Self.fadeDuration), value: bars)
        .task {
            try? await revealRows()
        }
    }

    private func accessibilityValue(for bar: MuscleBar) -> String {
        let value = bar.value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
        return [ "\(value) \(spokenUnit)", bar.accessibilityNote ]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func revealRows() async throws {
        guard !reduceMotion else {
            shownRows = bars.count
            filledRows = bars.count
            return
        }

        try await Task.sleep(for: .seconds(Self.startDelay))
        switch reveal {
        case .together:
            withAnimation(.easeOut(duration: Self.fadeDuration)) {
                shownRows = bars.count
            }
            withAnimation(.easeOut(duration: Self.growDuration)) {
                filledRows = bars.count
            }
        case .rowByRow:
            // The label appears, then its bar grows to length while the value climbs.
            for index in bars.indices {
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
}

/// Value, length and growth are all animatable, so the number climbs frame by frame with the bar.
private struct ValueBar: View, Animatable {
    private static let height: CGFloat = 28
    /// Room kept at the end of the longest bar for the value, e.g. "12 sets".
    private static let valueWidth: CGFloat = 76

    var value: Double
    var fraction: Double
    /// 0 is an empty bar, 1 is full length.
    var progress: Double
    let color: Color?
    let fractionDigits: Int
    let unit: ((Double) -> String)?

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(value, AnimatablePair(fraction, progress)) }
        set {
            value = newValue.first
            fraction = newValue.second.first
            progress = newValue.second.second
        }
    }

    /// Rounded down so a climbing count never shows a value it hasn't reached.
    private var shownValue: Double {
        let scale = pow(10, Double(fractionDigits))
        return (value * progress * scale).rounded(.down) / scale
    }

    private var fill: AnyShapeStyle {
        color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(TintShapeStyle())
    }

    var body: some View {
        GeometryReader { proxy in
            let fullWidth = max(0, proxy.size.width - Self.valueWidth)

            HStack(spacing: LayoutMetrics.compactSpacing) {
                Capsule()
                    .fill(fill)
                    .frame(width: fullWidth * fraction * progress)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(shownValue, format: .number.precision(.fractionLength(0...fractionDigits)))
                        .font(.headline.monospacedDigit())
                    if let unit {
                        Text(unit(shownValue))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
                .opacity(progress > 0 ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: Self.height)
    }
}

#Preview("MuscleBarChart") {
    MuscleBarChart(
        bars: [
            MuscleBar(muscle: .chest, value: 14.5, color: VolumeTier.maxGrowth.color),
            MuscleBar(muscle: .back, value: 9, color: VolumeTier.growth.color),
            MuscleBar(muscle: .calves, value: 1.5, color: VolumeTier.tooLittle.color),
        ],
        fractionDigits: 1
    )
    .padding()
}
