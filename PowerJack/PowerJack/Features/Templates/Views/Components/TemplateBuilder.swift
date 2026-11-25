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
    /// Days that can't be edited, with why. Used by a running program in its last week.
    private let lockedDays: [Int: LockedDay]
    /// A line shown above a day's exercises, like why a running program's edit starts next week.
    private let dayNotes: [Int: String]
    /// Exercises with sets logged in a workout in progress. They show a check and can't be removed.
    private let loggedExercises: Set<UUID>
    /// A running program's days each keep at least one exercise, since a workout can't run empty.
    private let keepsOneExercisePerDay: Bool
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
        lockedDays: [Int: LockedDay] = [:],
        dayNotes: [Int: String] = [:],
        loggedExercises: Set<UUID> = [],
        keepsOneExercisePerDay: Bool = false
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
        self.dayNotes = dayNotes
        self.loggedExercises = loggedExercises
        self.keepsOneExercisePerDay = keepsOneExercisePerDay
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
                Picker("Workout day", selection: $selection) {
                    ForEach(options) { day in
                        Text(day.name).tag(day)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                Divider()
                    .padding(.horizontal, LayoutMetrics.sectionSpacing)

                if let hint {
                    HintView(hint)
                        .padding(.horizontal)
                }

                if let note = dayNotes[selection.index] {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LayoutMetrics.sectionSpacing)
                }

                if let lockedDay = lockedDays[selection.index] {
                    ContentUnavailableView {
                        Label(lockedDay.title, systemImage: "lock")
                    } description: {
                        if let detail = lockedDay.detail {
                            Text(detail)
                        }
                    }
                    .powerJackGlassCard()
                } else {
                    // The picker changes days, leaving horizontal swipes on exercise rows for editing.
                    TemplateWorkoutBuilder(
                        templateWorkoutDraft: $draft.templateWorkoutDraftsValue[selection.index],
                        loggedExercises: loggedExercises,
                        keepsOneExercise: keepsOneExercisePerDay,
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

            let addExercise = ToolbarItem(placement: .topBarTrailing) {
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
            #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                addExercise.visibilityPriority(.high)
            } else {
                addExercise
            }
            #else
            addExercise
            #endif
        }
    }
}

/// A day the builder shows but won't edit.
struct LockedDay {
    let title: String
    var detail: String?
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
    var loggedExercises: Set<UUID> = []
    /// The day's last exercise stays, with a note saying why.
    var keepsOneExercise = false
    
    let handleEdit: (Exercise) -> Void

    @State private var isExplainingLastExercise = false

    /// The exercise waiting to be added to a superset, once the day has one to choose from.
    @State private var exerciseToSuperset: TemplateExerciseBlock?
    /// The superset open in its own list, to reorder or take one out.
    @State private var supersetToEdit: UUID?
    
    var body: some View {
        // No NavigationStack of its own: Edit Days shows this inside the Programs stack, whose typed
        // path a nested stack breaks (a crash from a link, or a pop to the list from the router).
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
        .animation(.default, value: templateWorkoutDraft.templateExerciseDrafts)
        .powerJackGlassCard(interactive: true)
        .alert("A Day Needs an Exercise", isPresented: $isExplainingLastExercise) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add another exercise before you remove this one. To take the day off, skip its workout instead.")
        }
        .sheet(
            isPresented: Binding(
                get: { supersetToEdit != nil },
                set: { if !$0 { supersetToEdit = nil } }
            )
        ) {
            if let supersetToEdit {
                SupersetEditor(
                    templateWorkoutDraft: $templateWorkoutDraft,
                    supersetID: supersetToEdit
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func blockRow(_ block: TemplateExerciseBlock) -> some View {
        if block.isSuperset {
            // Tap to open the superset's own list. Swipe either way to unstack it,
            // so a swipe right on a superset never goes back a screen.
            Button {
                supersetToEdit = block.exercises[0].supersetID
            } label: {
                SupersetBuilder(
                    letter: templateWorkoutDraft.supersetLetter(for: block),
                    color: SupersetStyle.color(at: templateWorkoutDraft.supersetIndex(for: block)),
                    exercises: block.exercises.map(\.exercise),
                    logged: block.exercises.map { loggedExercises.contains($0.id) }
                )
                .contentShape(.rect)
            }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    unstackButton(block)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    unstackButton(block)
                }
        } else {
            let templateExerciseDraft = block.exercises[0]
            let isLogged = loggedExercises.contains(templateExerciseDraft.id)
            TemplateExerciseBuilder(exercise: templateExerciseDraft.exercise, isLogged: isLogged)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    rowActions(block, isLogged: isLogged, edge: .leading)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    rowActions(block, isLogged: isLogged, edge: .trailing)
                }
                // On the row, so the popup points at the exercise that was swiped.
                .confirmationDialog(
                    "Add to Superset",
                    isPresented: Binding(
                        get: { exerciseToSuperset?.id == block.id },
                        set: { if !$0 { exerciseToSuperset = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    supersetChoices(for: block)
                } message: {
                    if !templateWorkoutDraft.canStartSuperset {
                        Text(SupersetStyle.limitNote)
                    }
                }
        }
    }

    private func rowActions(_ block: TemplateExerciseBlock, isLogged: Bool, edge: HorizontalEdge) -> some View {
        let templateExerciseDraft = block.exercises[0]
        return ForEach(ExerciseRowAction.actions(isLogged: isLogged, from: edge), id: \.self) { action in
            switch action {
            case .superset: supersetButton(block)
            case .edit: editButton(templateExerciseDraft)
            case .trash: trashButton(templateExerciseDraft)
            }
        }
    }

    private func supersetButton(_ block: TemplateExerciseBlock) -> some View {
        Button {
            superset(block)
        } label: {
            Label("Superset", systemImage: "link")
        }
        .tint(.indigo)
    }

    private func editButton(_ templateExerciseDraft: TemplateExerciseDraft) -> some View {
        Button {
            handleEdit(templateExerciseDraft.exercise)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.blue)
    }

    private func trashButton(_ templateExerciseDraft: TemplateExerciseDraft) -> some View {
        Button {
            if keepsOneExercise && templateWorkoutDraft.templateExerciseDrafts.count == 1 {
                isExplainingLastExercise = true
            } else {
                templateWorkoutDraft.removeTemplateExercises(at: IndexSet(integer: templateExerciseDraft.order))
            }
        } label: {
            Label("Trash", systemImage: "trash")
        }
        .tint(.red)
    }

    /// The first superset starts straight away. After that, the lifter picks one to join or starts another.
    private func superset(_ block: TemplateExerciseBlock) {
        SupersetHint().invalidate(reason: .actionPerformed)
        if templateWorkoutDraft.supersets.isEmpty {
            templateWorkoutDraft.startSuperset(with: block)
        } else {
            exerciseToSuperset = block
        }
    }

    @ViewBuilder
    private func supersetChoices(for block: TemplateExerciseBlock) -> some View {
        ForEach(templateWorkoutDraft.supersets) { superset in
            Button("Add to \(templateWorkoutDraft.supersetLetter(for: superset))") {
                templateWorkoutDraft.add(block, to: superset)
            }
        }
        if templateWorkoutDraft.canStartSuperset {
            Button("New Superset") {
                templateWorkoutDraft.startSuperset(with: block)
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

/// What swiping an exercise row offers. Both swipes show the same actions in the same order,
/// Superset | Edit | Trash, so neither side has to be learned.
enum ExerciseRowAction: CaseIterable {
    case superset, edit, trash

    /// The actions a swipe from `edge` lists, from that edge inward, which is how SwiftUI lays
    /// them out. A logged exercise has no Trash, since logged sets are never thrown away.
    static func actions(isLogged: Bool, from edge: HorizontalEdge) -> [ExerciseRowAction] {
        let leftToRight = allCases.filter { $0 != .trash || !isLogged }
        return edge == .leading ? leftToRight : leftToRight.reversed()
    }
}

struct TemplateExerciseBuilder: View {
    let exercise: Exercise
    var isLogged = false

    var body: some View {
        TemplateExerciseLabel(exercise: exercise, isLogged: isLogged)
            .powerJackGlassPanel()
    }
}

/// Exercises stacked into a superset share one card, done one set of each in turn.
struct SupersetBuilder: View {
    let letter: String
    var color: Color = SupersetStyle.color(at: 0)
    let exercises: [Exercise]
    /// Whether each exercise has sets logged in a workout in progress.
    var logged: [Bool] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                Text("Superset \(letter)")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 15)
                .padding(.top, 8)

            ForEach(exercises.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                        .padding(.horizontal, 15)
                }
                TemplateExerciseLabel(exercise: exercises[index], isLogged: logged.indices.contains(index) && logged[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .powerJackGlassPanel()
    }
}

/// An exercise's name, equipment and main muscle, with a check once it has sets logged in a workout in progress.
struct TemplateExerciseLabel: View {
    let exercise: Exercise
    var isLogged = false

    var body: some View {
        HStack {
            details
            Spacer()
            if isLogged {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Logged")
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
    }

    private var details: some View {
        VStack(alignment: .leading) {
            Text(exercise.exerciseName.localizedCapitalized)
                .foregroundStyle(.blue)

            HStack {
                Text(exercise.equipmentDisplayName)
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
    }
}
