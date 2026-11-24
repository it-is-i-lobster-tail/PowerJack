import SwiftUI

enum WorkoutChartPalette {
    // Alternate cool and warm inks, with a brighter partner for dark backgrounds.
    private static let inks: [(light: Int, dark: Int)] = [
        (0x126C49, 0x5CD49F), (0xA24F0F, 0xFFAE66), (0x286A85, 0x78C7E7), (0x8E486A, 0xEDA2C7),
        (0x586B14, 0xBAD671), (0x665292, 0xBDACF2), (0x087473, 0x65D4CA), (0xA04032, 0xFF9685),
        (0x426095, 0x9EBAFF), (0x866316, 0xEDCB72), (0x43764B, 0x96D498), (0x864780, 0xE3A4DA)
    ]

    static func color(at index: Int, scheme: ColorScheme) -> Color {
        let ink = inks[index % inks.count]
        let rgb = scheme == .dark ? ink.dark : ink.light
        return Color(red: Double(rgb >> 16) / 255, green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255)
    }
}

struct ExerciseWorkoutTable: View {
    let sessions: ArraySlice<ProgramExerciseHistory.Session>
    let exercise: ProgramExerciseHistory
    let unit: WeightUnit
    @Binding var selected: ProgramExerciseHistory.Session?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workouts").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                GridRow {
                    Text("Workout").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Sets")
                    Text("RIR").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(sessions.indices, id: \.self) { index in
                    let session = sessions[index]
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(WorkoutChartPalette.color(at: index, scheme: scheme))
                                .frame(width: 13, height: 13)
                                .accessibilityHidden(true)
                            Button { selected = session } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Week \(session.week) · Day \(session.day)").fontWeight(.medium)
                                    if let date = session.date {
                                        Text(date, format: .dateTime.month(.abbreviated).day().year())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Text(session.firstSet == session.lastSet ? "\(session.firstSet)" : "\(session.firstSet)–\(session.lastSet)")
                        Text(session.ratings.map { $0?.valueText ?? "—" }.joined(separator: ", "))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(session.programName), week \(session.week), day \(session.day), sets \(session.firstSet) through \(session.lastSet)")
                    .accessibilityAction { selected = session }
                    .accessibilityValue("Reps in reserve: \(session.ratings.map { $0?.label ?? "unrecorded" }.joined(separator: ", "))")
                }
            }
            .font(.subheadline.monospacedDigit())
            Text("RIR is reps in reserve on the last set. A dash means no rating was recorded.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $selected) { session in
            NavigationStack {
                WorkoutSetsDetail(exercise: exercise, session: session, unit: unit)
                    .toolbar { Button("Done") { selected = nil } }
            }
        }
    }
}
