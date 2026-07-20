//
//  TemplateProgramNew.swift
//  PowerJack
//
//  Created by trogdor on 7/19/26.
//

import SwiftData
import SwiftUI

struct TemplateProgramNew: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSave: (TemplateProgram) -> Void

    private let boxHeight: CGFloat = 72
    private let workoutsPerWeekOptions = Array(
        TemplateProgramDraft.minimumWorkoutsPerWeek...TemplateProgramDraft.maximumWorkoutsPerWeek
    )

    @FocusState private var nameIsFocused: Bool
    @State private var draft = TemplateProgramDraft()
    @State private var pendingWorkoutsPerWeek: Int?
    @State private var saveErrorMessage: String?

    private var workoutsPerWeek: Binding<Int?> {
        Binding(
            get: { draft.workoutsPerWeek },
            set: { proposedCount in
                guard let proposedCount else { return }
                requestWorkoutsPerWeek(proposedCount)
            }
        )
    }

    private var isConfirmingWorkoutRemoval: Binding<Bool> {
        Binding(
            get: { pendingWorkoutsPerWeek != nil },
            set: { isPresented in
                if !isPresented {
                    pendingWorkoutsPerWeek = nil
                }
            }
        )
    }

    var body: some View {
        GlassFormScaffold(
            navigationTitle: "New Template",
            headerSystemImage: "square.3.layers.3d.top.filled",
            headerTitle: "Build a reusable workout template"
        ) {
            ValidatedNameField(
                title: "Name",
                prompt: "Template name",
                maximumLength: TemplateProgramDraft.maximumNameLength,
                height: boxHeight,
                text: $draft.templateName,
                isFocused: $nameIsFocused
            )

            GlassPickerField(
                selection: workoutsPerWeek,
                options: workoutsPerWeekOptions,
                height: boxHeight
            ) {
                FormFieldLabel(
                    systemImage: "calendar.badge.clock",
                    title: "Workouts per Week",
                    detail: "Choose two to six workout days"
                )
            } optionLabel: { count in
                Text(count, format: .number)
            }

            TemplateFocusSelectionLink(
                boxHeight: boxHeight,
                selectedMuscles: $draft.templateMuscleFocusValue
            )

            TemplateWorkoutDayList(
                workoutDrafts: $draft.templateWorkoutDraftsValue
            )
        } footer: {
            FormSubmitButton(
                title: "Save",
                isEnabled: draft.canSave,
                action: save
            )
        }
        .alert(
            "Remove Configured Workout Days?",
            isPresented: isConfirmingWorkoutRemoval
        ) {
            Button("Remove Days", role: .destructive, action: confirmWorkoutRemoval)
            Button("Cancel", role: .cancel, action: cancelWorkoutRemoval)
        } message: {
            Text("Exercises assigned to the removed trailing days will be discarded.")
        }
        .saveErrorAlert($saveErrorMessage)
    }

    private func requestWorkoutsPerWeek(_ proposedCount: Int) {
        nameIsFocused = false

        if draft.removingConfiguredWorkouts(for: proposedCount) {
            pendingWorkoutsPerWeek = proposedCount
        } else {
            draft.setWorkoutsPerWeek(proposedCount)
        }
    }

    private func confirmWorkoutRemoval() {
        guard let pendingWorkoutsPerWeek else { return }
        draft.setWorkoutsPerWeek(pendingWorkoutsPerWeek)
        self.pendingWorkoutsPerWeek = nil
    }

    private func cancelWorkoutRemoval() {
        pendingWorkoutsPerWeek = nil
    }

    private func save() {
        guard let templateProgram = draft.makeTemplateProgram() else { return }

        do {
            try modelContext.insertAndSave(templateProgram)
            onSave(templateProgram)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private struct TemplateFocusSelectionLink: View {
    let boxHeight: CGFloat

    @Binding var selectedMuscles: [Muscle]

    var body: some View {
        NavigationLink {
            LimitedMuscleSelectionView(
                navigationTitle: "Focus Muscles",
                guidance: "Choose up to \(TemplateProgramDraft.maximumFocusMuscles)",
                maximumSelection: TemplateProgramDraft.maximumFocusMuscles,
                selectedMuscles: $selectedMuscles
            )
        } label: {
            HStack(spacing: 12) {
                FormFieldLabel(
                    systemImage: "target",
                    title: "Focus Muscles",
                    detail: "Choose one to four muscles"
                )

                if !selectedMuscles.isEmpty {
                    Text(selectedMuscles.count, format: .number)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, LayoutMetrics.sectionSpacing)
        }
        .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight)
        .powerJackGlassCard(interactive: true)
    }
}

private struct TemplateWorkoutDayList: View {
    @Binding var workoutDrafts: [TemplateWorkoutDraft]

    var body: some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            ForEach($workoutDrafts) { $workoutDraft in
                NavigationLink {
                    TemplateWorkoutDraftEditor(
                        dayNumber: (workoutDraft.order ?? 0) + 1,
                        draft: $workoutDraft
                    )
                } label: {
                    TemplateWorkoutDayLabel(draft: workoutDraft)
                        .padding(.horizontal, LayoutMetrics.sectionSpacing)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .powerJackGlassCard(interactive: true)
            }
        }
    }
}

private struct TemplateWorkoutDayLabel: View {
    let draft: TemplateWorkoutDraft

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Day \((draft.order ?? 0) + 1)")
                Text(exerciseSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var exerciseSummary: String {
        let exerciseNames = draft.templateExerciseDrafts.compactMap { $0.exercise?.exerciseName }
        return exerciseNames.isEmpty
            ? "Add at least one exercise"
            : exerciseNames.joined(separator: ", ")
    }
}

#Preview("TemplateProgramNew") {
    NavigationStack {
        TemplateProgramNew(onSave: { _ in })
    }
    .modelContainer(PowerJackSeed.weekOneProgress().container)
}
