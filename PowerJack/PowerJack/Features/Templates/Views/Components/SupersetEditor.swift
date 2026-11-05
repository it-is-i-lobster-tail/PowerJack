//
//  SupersetEditor.swift
//  PowerJack
//

import SwiftUI

/// One superset's own list: drag to change the order, swipe to take an exercise out.
struct SupersetEditor: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var templateWorkoutDraft: TemplateWorkoutDraft
    let supersetID: UUID

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
                            .tint(.red)
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
                    Text("Touch and hold to change the order. Swipe left to take an exercise out. It stays on the day, just below the superset.")
                }
            }
            .animation(.default, value: superset?.exercises)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        // Taking the last exercise out ends the superset, so there's nothing left to show.
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
