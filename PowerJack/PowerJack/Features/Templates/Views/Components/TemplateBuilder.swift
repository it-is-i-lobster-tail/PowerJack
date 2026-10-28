//
//  TemplateBuilder.swift
//  PowerJack
//
//  Created by trogdor on 7/21/26.
//

import SwiftUI
import TipKit

struct TemplateBuilder: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding private var draft: TemplateProgramDraft
    /// Days that can't be edited, with why. Used by a running program, whose finished days stay as they were.
    private let lockedDays: [Int: String]
    @State private var options: [BrowserOption]
    @State private var selection: BrowserOption
    @State private var isShowingWorkoutExerciseSheet = false
    @State private var isShowingWorkoutExerciseEditSheet = false
    @State private var exerciseToEdit: Exercise?
    // One at a time: the superset hint waits for the first to go.
    @State private var hints = TipGroup(.ordered) {
        TemplateBuilderHint()
        SupersetHint()
    }

    init(
        draft: Binding<TemplateProgramDraft>,
        lockedDays: [Int: String] = [:]
    ) {
        let dayCount = draft.wrappedValue.workoutsPerWeek ?? 3
        let initialOptions = (1...dayCount).map { day in
            BrowserOption(
                id: UUID(),
                name: "Day \(day)",
                index: day - 1
            )
        }

        _draft = draft
        self.lockedDays = lockedDays
        _options = State(initialValue: initialOptions)
        _selection = State(initialValue: initialOptions[0])
    }
    
    private var selectedIndex: Int? {
        options.firstIndex { option in
            option.id == selection.id
        }
    }
    
    /// The superset hint needs two exercises on the day to stack.
    private var hint: (any Hint)? {
        guard let hint = hints.currentTip as? any Hint else { return nil }
        guard hint is SupersetHint else { return hint }
        return draft.templateWorkoutDraftsValue[selection.index].templateExerciseDrafts.count > 1 ? hint : nil
    }

    private func handleUpdateExercise(_: Exercise) {
        exerciseToEdit = nil
        isShowingWorkoutExerciseEditSheet = false
    }
    
    private func handleShowEditExerciseSheet(exercise: Exercise) {
        TemplateBuilderHint().invalidate(reason: .actionPerformed)
        exerciseToEdit = exercise
    }

    var body: some View {
        ZStack {
            VStack {
                SlidingGlassPicker(
                    options: options,
                    selection: $selection,
                    title: \.name
                )
                
                Divider()
                    .padding(.horizontal, LayoutMetrics.sectionSpacing)

                if let hint {
                    HintView(hint)
                        .padding(.horizontal)
                }

                if let message = lockedDays[selection.index] {
                    ContentUnavailableView(message, systemImage: "lock")
                        .powerJackGlassCard()
                } else {
                    // Days change only by tapping the picker. Horizontal swipes belong to
                    // the exercise rows, so swipe to edit or delete never flips the day.
                    TemplateWorkoutBuilder(
                        templateWorkoutDraft: $draft.templateWorkoutDraftsValue[selection.index],
                        handleEdit: handleShowEditExerciseSheet
                    )
                    .id(selection.id)
                }
                Spacer()
            }
        }
        .sheet(isPresented: $isShowingWorkoutExerciseSheet) {
            if let index = selectedIndex {
                ExerciseSelectionView(
                    navigationTitle: "Add Exercise",
                    onSelect: { exercise in
                        _ = draft.templateWorkoutDraftsValue[index]
                            .addTemplateExerciseDraft(exercise: exercise)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $exerciseToEdit) {exercise in
            ExerciseDetailView(
                exercise: exercise,
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CopyDayMenu(
                    options: options.filter { lockedDays[$0.index] == nil },
                    selection: $selection,
                    draft: $draft
                )
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    TemplateBuilderHint().invalidate(reason: .actionPerformed)
                    isShowingWorkoutExerciseSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Exercise")
                    }
                }
                .accessibilityLabel("Add")
                .disabled(lockedDays[selection.index] != nil)
            }
        }
    }
}

private struct TemplateBuilderPreviewContent: View {
    @State private var draft = TemplateProgramDraft()

    var body: some View {
        TemplateBuilder(draft: $draft)
    }
}

#Preview("TemplateBuilder") {
    let scenario = PowerJackSeed.exercises()

    NavigationPreviewHost(modelContainer: scenario.container) {
        TemplateBuilderPreviewContent()
    }
}

struct TemplateWorkoutBuilder: View {
    
    @Binding var templateWorkoutDraft: TemplateWorkoutDraft
    
    let handleEdit: (Exercise) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(templateWorkoutDraft.blocks) { block in
                    blockRow(block)
                        .padding(.horizontal, 15)
                        .listRowSeparator(.hidden, edges: .all)
                        .listRowBackground(Color.clear)
                        .listRowInsets(
                            EdgeInsets(
                                top: 4,
                                leading: 0,
                                bottom: 4,
                                trailing: 0
                            )
                        )
                }
                .onMove { source, destination in
                    templateWorkoutDraft.moveBlocks(
                        from: source,
                        to: destination
                    )
                }
            }
            .padding(.vertical, 8)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(.default, value: templateWorkoutDraft.blocks.map(\.exercises.count))
        }
        .powerJackGlassCard(interactive: true)
    }

    @ViewBuilder
    private func blockRow(_ block: TemplateExerciseBlock) -> some View {
        if block.isSuperset {
            // Either way, so a swipe right on a stack never goes back a screen.
            SupersetBuilder(exercises: block.exercises.map(\.exercise))
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    unstackButton(block)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    unstackButton(block)
                }
        } else {
            let templateExerciseDraft = block.exercises[0]
            TemplateExerciseBuilder(exercise: templateExerciseDraft.exercise)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if templateWorkoutDraft.canStack(block) {
                        Button {
                            SupersetHint().invalidate(reason: .actionPerformed)
                            templateWorkoutDraft.stack(block)
                        } label: {
                            Label("Superset", systemImage: "link")
                        }
                        .tint(.indigo)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        templateWorkoutDraft.removeTemplateExercises(at: IndexSet(integer: templateExerciseDraft.order))
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                    .tint(.red)

                    Button {
                        handleEdit(templateExerciseDraft.exercise)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
        }
    }
}

extension TemplateWorkoutBuilder {
    private func unstackButton(_ block: TemplateExerciseBlock) -> some View {
        Button {
            templateWorkoutDraft.unstack(block)
        } label: {
            Label("Unstack", systemImage: "square.split.1x2")
        }
        .tint(.gray)
    }
}

struct TemplateExerciseBuilder: View {
    let exercise: Exercise

    var body: some View {
        HStack {
            TemplateExerciseLabel(exercise: exercise)
            Spacer()
        }
        .powerJackGlassPanel()
    }
}

/// Exercises stacked into a superset share one card, done one set of each in turn.
struct SupersetBuilder: View {
    let exercises: [Exercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                Text("Superset")
            }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
                .padding(.horizontal, 15)
                .padding(.top, 8)

            ForEach(exercises.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                        .padding(.horizontal, 15)
                }
                TemplateExerciseLabel(exercise: exercises[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .powerJackGlassPanel()
    }
}

/// An exercise's name, equipment and main muscle.
private struct TemplateExerciseLabel: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading) {
            Text(exercise.exerciseName.localizedCapitalized)
                .foregroundStyle(.blue)

            HStack {
                Text(exercise.exerciseEquipment.rawValue.localizedCapitalized)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .foregroundStyle(.secondary)
                Text("|")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .foregroundStyle(.secondary)
                Text(exercise.primaryMuscleFocus.rawValue.localizedCapitalized)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
    }
}
