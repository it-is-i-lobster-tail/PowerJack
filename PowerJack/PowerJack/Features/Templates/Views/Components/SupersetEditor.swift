//
//  SupersetEditor.swift
//  PowerJack
//

import SwiftData
import SwiftUI

/// One superset's own list: drag to change the order, swipe to take an exercise out or change it.
struct SupersetEditor: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var templateWorkoutDraft: TemplateWorkoutDraft
    let supersetID: UUID
    /// Exercises with sets logged in a workout in progress. They can't be changed.
    var loggedExercises: Set<UUID> = []

    /// The exercise being swapped for another, in the same spot in the superset.
    @State private var exerciseToChange: TemplateExerciseDraft?

    private var superset: TemplateExerciseBlock? {
        templateWorkoutDraft.superset(supersetID)
    }

    private var title: String {
        guard let superset else { return "Superset" }
        return "Superset \(templateWorkoutDraft.supersetLetter(for: superset))"
    }

    var body: some View {
        // Its own stack is safe here: a sheet is a new presentation, not a push on the Programs stack.
        NavigationStack {
            List {
                Section {
                    ForEach(superset?.exercises ?? []) { templateExerciseDraft in
                        HStack {
                            TemplateExerciseLabel(exercise: templateExerciseDraft.exercise)
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 20))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                templateWorkoutDraft.removeFromSuperset(templateExerciseDraft.id)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .tint(.blue)

                            if !loggedExercises.contains(templateExerciseDraft.id) {
                                Button {
                                    exerciseToChange = templateExerciseDraft
                                } label: {
                                    Label("Change", systemImage: "slider.horizontal.3")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .onMove { source, destination in
                        templateWorkoutDraft.moveExercises(
                            inSuperset: supersetID,
                            from: source,
                            to: destination
                        )
                    }
                } footer: {
                    Text("Touch and hold to change the order. Swipe left to take an exercise out or change it. One taken out stays on the day, just below the superset.")
                }
            }
            .animation(.default, value: superset?.exercises)
            .sheet(item: $exerciseToChange) { changing in
                ChangeExercisePicker(current: changing.exercise) { exercise in
                    templateWorkoutDraft.changeExercise(changing.id, to: exercise)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if let superset {
                    Button {
                        templateWorkoutDraft.unstack(superset)
                    } label: {
                        Text("Remove Superset")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.glass)
                    .padding(.horizontal, LayoutMetrics.sectionSpacing)
                    .padding(.bottom, LayoutMetrics.compactSpacing)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        // Close the editor when the superset ends.
        .onChange(of: superset == nil) { _, isGone in
            if isGone { dismiss() }
        }
    }
}

private struct SupersetEditorPreviewContent: View {
    @State private var day: TemplateWorkoutDraft

    init(exercises: [Exercise]) {
        var day = TemplateWorkoutDraft(enabled: true, order: 0, templateExercises: nil)
        for exercise in exercises.prefix(3) {
            day.addTemplateExerciseDraft(exercise: exercise)
        }
        day.startSuperset(with: day.blocks[0])
        day.add(day.blocks[1], to: day.supersets[0])
        _day = State(initialValue: day)
    }

    var body: some View {
        if let supersetID = day.supersets.first?.exercises[0].supersetID {
            SupersetEditor(templateWorkoutDraft: $day, supersetID: supersetID)
        }
    }
}

#Preview("SupersetEditor") {
    let scenario = PowerJackSeed.exercises()

    SupersetEditorPreviewContent(exercises: scenario.exercises)
        .modelContainer(scenario.container)
}
