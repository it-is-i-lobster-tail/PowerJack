import SwiftData
import SwiftUI

struct PreviewWorkoutView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.Key.weightUnit) private var unit = WeightUnit.deviceDefault
    @State private var copy: WorkoutPreviewCopy.Copy?
    @State private var currentOpportunity: WorkoutAchievement?

    let program: Program
    let workout: Workout
    var highlight: WorkoutReminders.Highlight? = nil

    var body: some View {
        let preview = WorkoutPreview(program: program, workout: workout)
        let variation = WorkoutPreviewCopy.variation(for: workout.syncID)
        let displayCopy = copy ?? WorkoutPreviewCopy.fallback(for: preview, variation: variation)

        Group {
            if preview.lifts.isEmpty {
                ContentUnavailableView("No Upcoming Sets", systemImage: "list.bullet")
            } else {
                detail(preview, copy: displayCopy)
            }
        }
        .navigationTitle("Workout Preview")
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: preview) {
            copy = nil
            currentOpportunity = nil
            guard !preview.lifts.isEmpty else { return }
            if highlight == nil,
               let programs = try? context.fetch(FetchDescriptor<Program>()),
               let history = try? WorkoutPreviewHistory(programs: programs, in: context, now: .now) {
                currentOpportunity = WorkoutAchievement.selected(
                    preview: preview, program: program, workout: workout, history: history, at: .now
                )
            }
            let generated = await WorkoutPreviewCopy.generate(
                for: preview, workoutID: workout.syncID, variation: variation
            )
            if !Task.isCancelled { copy = generated }
        }
    }

    private func detail(_ preview: WorkoutPreview, copy displayCopy: WorkoutPreviewCopy.Copy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text(displayCopy.tagline)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(displayCopy.focus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let opportunity = highlight.map(\.achievement) ?? currentOpportunity {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(opportunity.title, systemImage: "trophy")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(opportunity.detail(unit: unit))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LayoutMetrics.sectionSpacing)
                    .powerJackGlassPanel()
                }

                VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                    ForEach(Array(preview.lifts.enumerated()), id: \.offset) { _, lift in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lift.name)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(lift.sets.enumerated()), id: \.offset) { _, set in
                                let prescription = set.text(unit: unit)
                                Text(set.role.title.map { "\($0) · \(prescription)" } ?? prescription)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LayoutMetrics.sectionSpacing)
                .powerJackGlassPanel()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutMetrics.sectionSpacing)
        }
    }

    private var subtitle: String {
        guard let week = program.weekNumber(containing: workout) else { return program.templateType.name }
        return "\(program.templateType.name) · Week \(week) · Day \(workout.order + 1)"
    }
}
