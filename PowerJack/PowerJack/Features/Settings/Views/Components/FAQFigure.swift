//
//  FAQFigure.swift
//  PowerJack
//
//  The FAQ's diagrams of how training progresses, in plain words. Keep them in step with the
//  progression rules: each one simplifies what all three kinds of programs do.
//

import SwiftUI

struct FAQFigure: View {
    let figure: FAQ.Figure

    var body: some View {
        switch figure {
        case .weeklyLoop:
            WeeklyLoopChart()
        case .block:
            BlockChart()
        case .programLengths:
            ProgramLengthsChart()
        case .hypertrophy:
            HypertrophyChart()
        case .strength:
            StrengthChart()
        case .powerJack:
            PowerJackChart()
        case .pain:
            PainChart()
        case .breaks:
            BreaksChart()
        }
    }
}

/// Lift, rate and finish the week, then the checks each exercise goes through before next week is planned.
private struct WeeklyLoopChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowStep(number: 1, title: "Lift your sets", detail: "Each set is filled in with its target. Change it if you did something different, then tap the circle.")
            FlowArrow()
            FlowStep(number: 2, title: "Rate each exercise", detail: "How many more good reps you had left, and whether anything hurt.")
            FlowArrow()
            FlowStep(number: 3, title: "Finish the week", detail: "Then, for each exercise:")
            FlowArrow()
            FlowQuestion(title: "Did it hurt?")
            FlowOutcome(tone: .easeOff, when: "Moderate or worse", title: "Back off", detail: "No increases until it settles, and lighter if it's bad.")
            FlowArrow(label: "None, mild or noticeable")
            FlowQuestion(title: "Lighter week due?", detail: "At the end of each block")
            FlowOutcome(tone: .easeOff, when: "Yes", title: "Lighter week", detail: "About half the sets, at about 90% of the weight.")
            FlowArrow(label: "No")
            FlowQuestion(title: "How did it feel?", detail: "Compared with its aim")
            FlowOutcome(tone: .hold, when: "Harder than the aim", title: "Hold", detail: "The same target again, or a little lighter if you fell well short.")
            FlowOutcome(tone: .stepUp, when: "Right on the aim", title: "Step up", detail: "One more rep, or a little more weight.")
            FlowOutcome(tone: .stepUp, when: "Easier than the aim", title: "Bigger step", detail: "More reps or weight, to catch up with you.")
            FlowArrow()
            FlowStep(number: 4, title: "Next week's plan", detail: "Your new targets are filled in for your next workout. Then the loop starts again.")
        }
    }
}

/// A block from a 10-week program: each hard week leaves fewer reps in the tank, then the lighter week backs off.
private struct BlockChart: View {
    private struct Week {
        /// Reps to leave in the tank, or nil for the lighter week.
        let repsLeft: Int?
        /// How hard the week is, as a share of the hardest.
        let effort: CGFloat

        var label: String {
            repsLeft.map { "\($0) left" } ?? "Lighter"
        }

        var spokenLabel: String {
            repsLeft.map { "\($0) reps left" } ?? "lighter week"
        }
    }

    private let weeks = [
        Week(repsLeft: 3, effort: 0.45),
        Week(repsLeft: 2, effort: 0.7),
        Week(repsLeft: 2, effort: 0.7),
        Week(repsLeft: 1, effort: 1),
        Week(repsLeft: nil, effort: 0.25),
    ]

    @ScaledMetric private var barHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(weeks.indices, id: \.self) { index in
                    let week = weeks[index]
                    VStack(spacing: 4) {
                        Text(week.label)
                            .font(.caption2.weight(.semibold))
                        UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                            .fill(week.repsLeft == nil ? FlowTone.easeOff.color : .blue)
                            .frame(height: barHeight * week.effort)
                        Text("Week \(index + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Week \(index + 1), \(week.spokenLabel)")
                }
            }

            Text("Reps left in the tank on your last set")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Every length New Program offers, with its weeks laid out the way programs plan them.
private struct ProgramLengthsChart: View {
    private let lengths = Array(stride(from: 2, through: 12, by: 2))

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(lengths, id: \.self) { length in
                    let plan = ProgramBlocks.layout(weeks: length, carry: 0)
                    GridRow {
                        Text("\(length) weeks")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        // A square for every week of the longest program, so weeks line up across rows.
                        HStack(spacing: 3) {
                            ForEach(0..<(lengths.last ?? length), id: \.self) { index in
                                WeekSquare(kind: plan.indices.contains(index) ? plan[index] : nil)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(summary(of: plan))
                    }
                }
            }

            HStack(spacing: LayoutMetrics.sectionSpacing) {
                LegendItem(kind: .build, title: "Hard week")
                LegendItem(kind: .deload, title: "Lighter week")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func summary(of plan: [WeekKind]) -> String {
        let lighter = plan.count(where: { $0 == .deload })
        let hard = plan.count - lighter
        return lighter == 0
            ? "\(plan.count) weeks, all hard"
            : "\(plan.count) weeks: \(hard) hard, \(lighter) lighter"
    }
}

private struct WeekSquare: View {
    let kind: WeekKind?

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(kind.map(\.figureColor) ?? .clear)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 22)
    }
}

private struct LegendItem: View {
    let kind: WeekKind
    let title: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            RoundedRectangle(cornerRadius: 3)
                .fill(kind.figureColor)
                .frame(width: 12, height: 12)
        }
    }
}

private extension WeekKind {
    var figureColor: Color {
        self == .build ? .blue : FlowTone.easeOff.color
    }
}

/// Reps climb through the range, then the weight goes up.
private struct HypertrophyChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowQuestion(title: "How did it feel?", detail: "Compared with its aim")
            FlowOutcome(tone: .hold, when: "Harder, or reps short", title: "Same weight and reps", detail: "Short two weeks running? The weight comes down about 5%.")
            FlowArrow(label: "On the aim or easier")
            FlowQuestion(title: "At the top of the rep range?")
            FlowOutcome(tone: .stepUp, when: "Not yet", title: "Add reps", detail: "One more, or two if it felt easier. If it keeps feeling much easier, the weight goes up sooner.")
            FlowOutcome(tone: .stepUp, when: "Yes", title: "Add weight", detail: "A small jump in weight, and your reps start lower in the range again.", isLast: true)
        }
    }
}

/// Main lifts keep their reps and move their weight.
private struct StrengthChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowQuestion(title: "How did it feel?", detail: "Your last set of a main lift, compared with its aim")
            FlowOutcome(tone: .easeOff, when: "3 or more reps harder", title: "Less weight", detail: "About 2.5% lighter for each rep past two, up to 10%.")
            FlowOutcome(tone: .hold, when: "1 or 2 reps harder", title: "Same weight")
            FlowOutcome(tone: .stepUp, when: "Right on the aim", title: "A little more weight", detail: "A small nudge, about 1%.")
            FlowOutcome(tone: .stepUp, when: "Easier than the aim", title: "More weight", detail: "About 2.5% more for each rep easier, up to 7.5%.", isLast: true)
        }
    }
}

/// Main lifts: a heavy top set, then volume, with the weight moving week to week. Everything else: reps, then weight.
private struct PowerJackChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowQuestion(title: "Is it a main lift?", detail: "Up to four big lifts, like squats, deadlifts and presses")
            FlowOutcome(tone: .info, when: "No", title: "Reps first, then weight", detail: "Reps climb through the exercise's range, then the weight goes up, like in Hypertrophy programs.")
            FlowArrow(label: "Yes")
            FlowStep(title: "Heavy top set, then volume", detail: "One heavy set of around 5 reps, then lighter sets of around 8. A lift you train twice a week gets a heavy day and a volume day.")
            FlowArrow()
            FlowQuestion(title: "How did it feel?", detail: "Compared with its aim")
            FlowOutcome(tone: .easeOff, when: "2 or more reps short", title: "Less weight", detail: "About 2.5% lighter for each rep you missed, up to 10%. One rep short twice running counts too.")
            FlowOutcome(tone: .hold, when: "Harder, or a rep short", title: "Same weight")
            FlowOutcome(tone: .stepUp, when: "Right on the aim", title: "Up with the block", detail: "The weight rises as the aim moves closer to your limit.")
            FlowOutcome(tone: .stepUp, when: "Easier than the aim", title: "Extra weight", detail: "About 2.5% more on top.", isLast: true)
        }
    }
}

/// What each pain rating does to the exercise's next session.
private struct PainChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowStep(title: "Rate any pain", detail: "After each exercise, along with your reps left.")
            FlowArrow()
            FlowQuestion(title: "How much did it hurt?")
            FlowOutcome(tone: .stepUp, when: "None, mild or noticeable", title: "Carry on", detail: "Training progresses as usual. If noticeable pain keeps coming back or gets worse, increases pause.")
            FlowOutcome(tone: .hold, when: "Moderate", title: "Hold back", detail: "No increases while it lasts, and the weight may come down about 10%.")
            FlowOutcome(tone: .easeOff, when: "Severe or extreme", title: "Ease off", detail: "Lighter weight and fewer sets. Before you train it again, PowerJack checks in, so you can carry on lighter or skip it that day.", isLast: true)
        }
    }
}

/// How the next workout changes with the time since you last trained.
private struct BreaksChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowQuestion(title: "How long since you last trained?")
            FlowOutcome(tone: .stepUp, when: "Under 2 weeks", title: "Carry on", detail: "Your next workout picks up where you left off.")
            FlowOutcome(tone: .hold, when: "2 weeks or more", title: "Fresh block", detail: "The hard weeks build up again from the start.")
            FlowOutcome(tone: .easeOff, when: "About a month or more", title: "Ease back in", detail: "A fresh block with weights up to about 10% lighter, and an easier first week back.")
            FlowOutcome(tone: .easeOff, when: "About 3 months or more", title: "Rebuild", detail: "A fresh block with weights up to about 20% lighter, and easier weeks to get back up to speed.", isLast: true)
        }
    }
}

#Preview("FAQ Figures") {
    ScrollView {
        VStack(alignment: .leading, spacing: 40) {
            ForEach(FAQ.Figure.allCases, id: \.self) { figure in
                FAQFigure(figure: figure)
            }
        }
        .padding(32)
        .background(Color(.secondarySystemGroupedBackground))
    }
    .background(Color(.systemGroupedBackground))
}
