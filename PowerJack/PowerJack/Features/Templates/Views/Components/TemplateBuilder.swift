//
//  TemplateBuilder.swift
//  PowerJack
//
//  Created by trogdor on 7/21/26.
//

import SwiftUI

struct TemplateBuilder: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding private var draft: TemplateProgramDraft
    @State private var options: [BrowserOption]
    @State private var selection: BrowserOption
    @State private var isShowingWorkoutExerciseSheet = false
    @State private var isShowingWorkoutExerciseEditSheet = false
    @State private var exerciseToEdit: Exercise?

    init(
        draft: Binding<TemplateProgramDraft>
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
        _options = State(initialValue: initialOptions)
        _selection = State(initialValue: initialOptions[0])
    }
    
    private var selectedIndex: Int? {
        options.firstIndex { option in
            option.id == selection.id
        }
    }
    
    private var selectionID: Binding<BrowserOption?> {
        Binding(
            get: {
                selection
            },
            set: { newSelection in
                guard let newSelection else { return }
                selection = newSelection
            }
        )
    }

    private func handleUpdateExercise(_: Exercise) {
        exerciseToEdit = nil
        isShowingWorkoutExerciseEditSheet = false
    }
    
    private func handleShowEditExerciseSheet(exercise: Exercise) {
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

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(options, id: \.self) {option in
                            TemplateWorkoutBuilder(
                                templateWorkoutDraft: $draft.templateWorkoutDraftsValue[option.index],
                                handleEdit: handleShowEditExerciseSheet
                            )
                             .containerRelativeFrame(.horizontal)
                             .id(option.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                .scrollPosition(id: selectionID)
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
                Button {
                    isShowingWorkoutExerciseSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Exercise")
                    }
                }
                .accessibilityLabel("Add")
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
                ForEach(templateWorkoutDraft.templateExerciseDrafts) {
                    templateExerciseDraft in

                    TemplateExerciseBuilder(
                        exercise: templateExerciseDraft.exercise
                    )
                    .padding(.horizontal, 15)
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
                    templateWorkoutDraft.moveTemplateExercises(
                        from: source,
                        to: destination
                    )
                }
            }
            .padding(.vertical, 8)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .powerJackGlassCard(interactive: true)
    }
}

struct TemplateExerciseBuilder: View {
    let exercise: Exercise

    var body: some View {
        HStack {
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

            Spacer()
        }
        .powerJackGlassPanel()
    }
}
