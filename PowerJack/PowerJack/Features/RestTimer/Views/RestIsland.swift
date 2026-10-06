//
//  RestIsland.swift
//  PowerJack
//
//  The in-app rest countdown, styled after the Dynamic Island. iOS hides the app's own
//  Live Activity while the app is open, so this stands in for it.
//

import SwiftUI

struct RestIsland: View {
    static let collapsedSize = CGSize(width: 224, height: 40)
    /// Space kept clear at the top of the screen for the collapsed island.
    static let reservedHeight: CGFloat = collapsedSize.height + 12

    let rest: RestPeriod
    @Binding var isExpanded: Bool
    let onOpenExercise: () -> Void

    var body: some View {
        // Ticks line up with the rest's start, so the last tick lands exactly on its end.
        TimelineView(.periodic(from: rest.startedAt, by: 1)) { context in
            RestIslandContent(
                rest: rest,
                date: context.date,
                isExpanded: isExpanded,
                onTap: handleTap,
                onOpenExercise: openExercise
            )
        }
        .padding(.horizontal, LayoutMetrics.compactSpacing)
    }

    private func handleTap(isReady: Bool) {
        if isExpanded {
            setExpanded(false)
        } else if isReady {
            onOpenExercise()
        } else {
            setExpanded(true)
        }
    }

    private func openExercise() {
        setExpanded(false)
        onOpenExercise()
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
            isExpanded = expanded
        }
    }
}

private struct RestIslandContent: View {
    let rest: RestPeriod
    let date: Date
    let isExpanded: Bool
    let onTap: (_ isReady: Bool) -> Void
    let onOpenExercise: () -> Void

    // A small tolerance keeps floating point error from showing "Rest 0:00" for a tick.
    private var isReady: Bool { !rest.isResting(at: date.addingTimeInterval(0.05)) }
    private var tint: Color { isReady ? .green : .orange }
    private var secondsLeft: Int {
        max(0, Int((rest.remaining(at: date) - 0.05).rounded(.up)))
    }
    private var countdownText: String { Duration.seconds(secondsLeft).minuteSecondText }
    private var cornerRadius: CGFloat { isExpanded ? 32 : RestIsland.collapsedSize.height / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isExpanded {
                details
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .padding(.horizontal, isExpanded ? 18 : 10)
        .padding(.vertical, isExpanded ? 16 : 0)
        .frame(
            width: isExpanded ? nil : RestIsland.collapsedSize.width,
            height: isExpanded ? nil : RestIsland.collapsedSize.height
        )
        .frame(maxWidth: isExpanded ? 420 : nil)
        .foregroundStyle(.white)
        .background(.black, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        // Keeps the island's outline visible against a black dark-mode background.
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(VisualOpacity.subtle), lineWidth: 1)
        }
        .shadow(color: .black.opacity(VisualOpacity.light), radius: isExpanded ? 18 : 6, y: 4)
        .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture { onTap(isReady) }
        .animation(.smooth, value: isReady)
        .sensoryFeedback(.success, trigger: isReady) { wasReady, nowReady in
            !wasReady && nowReady
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isReady ? "Opens your current exercise" : "Shows the next set")
    }

    private var header: some View {
        HStack(spacing: isExpanded ? 12 : 8) {
            RestIslandRing(
                fractionRemaining: rest.fractionRemaining(at: date),
                isReady: isReady,
                lineWidth: isExpanded ? 4 : 3
            )
            .frame(width: isExpanded ? 40 : 22, height: isExpanded ? 40 : 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(isReady ? "Start set" : "Rest")
                    .font(isExpanded ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                if isExpanded {
                    Text(isReady ? "Your rest is over" : "Next set in \(countdownText)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(VisualOpacity.heavy))
                }
            }

            Spacer(minLength: 8)

            Group {
                if isReady {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(isExpanded ? .system(size: 30) : .body)
                } else {
                    Text(countdownText)
                        .font(isExpanded
                            ? .system(size: 34, weight: .semibold, design: .rounded)
                            : .subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: secondsLeft)
                }
            }
            .foregroundStyle(tint)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rest.exerciseName)
                    .font(.subheadline.weight(.semibold))
                Text(rest.detailText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(VisualOpacity.heavy))
            }

            Button(action: onOpenExercise) {
                Text(isReady ? "Start set" : "Go to exercise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(tint)
        }
    }
}

private struct RestIslandRing: View {
    let fractionRemaining: Double
    let isReady: Bool
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(VisualOpacity.light), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: isReady ? 1 : fractionRemaining)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Each tick moves the ring one second; animating it keeps the motion smooth.
                .animation(.linear(duration: 1), value: fractionRemaining)
            if isReady {
                Image(systemName: "checkmark")
                    .font(.system(size: lineWidth * 3, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
    }

    private var tint: Color { isReady ? .green : .orange }
}

#Preview("RestIsland - Resting") {
    @Previewable @State var isExpanded = false

    RestIsland(
        rest: RestPeriod(
            startedAt: .now,
            endsAt: .now.addingTimeInterval(135),
            exerciseName: "Barbell Back Squat",
            setNumber: 2,
            setCount: 3,
            reps: 8,
            weightTenthsPounds: 2250
        ),
        isExpanded: $isExpanded,
        onOpenExercise: {}
    )
    .frame(maxHeight: .infinity, alignment: .top)
}

#Preview("RestIsland - Ready, Expanded") {
    @Previewable @State var isExpanded = true

    RestIsland(
        rest: RestPeriod(
            startedAt: .now.addingTimeInterval(-200),
            endsAt: .now.addingTimeInterval(-20),
            exerciseName: "Pull Up",
            setNumber: 3,
            setCount: 3,
            reps: nil,
            weightTenthsPounds: nil
        ),
        isExpanded: $isExpanded,
        onOpenExercise: {}
    )
    .frame(maxHeight: .infinity, alignment: .top)
}
