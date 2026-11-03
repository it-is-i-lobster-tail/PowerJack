//
//  TemplateBuilder.swift
//  PowerJack
//
//  Created by trogdor on 7/21/26.
//

import SwiftUI
import TipKit
import UniformTypeIdentifiers

struct TemplateBuilder: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding private var draft: TemplateProgramDraft
    /// Days that can't be edited, with why. Used by a running program in its last week.
    private let lockedDays: [Int: LockedDay]
    /// A line shown above a day's exercises, like why a running program's edit starts next week.
    private let dayNotes: [Int: String]
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
        dayNotes: [Int: String] = [:]
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
                    // Days change only by tapping the picker, so dragging a card sideways never flips the day.
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
    
    let handleEdit: (Exercise) -> Void

    /// The exercises being dragged: a whole card, or one exercise lifted out of a superset.
    @State private var draggedIDs: [UUID] = []
    @State private var dropTarget: StackDropTarget?
    @State private var cardHeights: [UUID: CGFloat] = [:]
    
    var body: some View {
        NavigationStack {
            // A plain scroll view, not a List: a List takes every drop itself, so a card never sees one land on it.
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(templateWorkoutDraft.blocks) { block in
                        blockRow(block)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeights[block.id] = $0 }
                            .overlay { dropIndicator(on: block) }
                            .onDrop(
                                of: [.text],
                                delegate: StackDropDelegate(
                                    block: block,
                                    height: cardHeights[block.id] ?? 0,
                                    draft: $templateWorkoutDraft,
                                    draggedIDs: $draggedIDs,
                                    target: $dropTarget
                                )
                            )
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
            }
            .animation(.default, value: templateWorkoutDraft.templateExerciseDrafts)
            .animation(.snappy(duration: 0.2), value: dropTarget)
            .sensoryFeedback(.selection, trigger: dropTarget)
        }
        .powerJackGlassCard(interactive: true)
    }

    /// Touch and hold a card to drag it, or to open its menu without moving.
    @ViewBuilder
    private func blockRow(_ block: TemplateExerciseBlock) -> some View {
        if block.isSuperset {
            SupersetBuilder(
                exercises: block.exercises,
                drag: startDrag,
                unstack: { templateWorkoutDraft.unstack(block) },
                exerciseMenu: exerciseMenu
            )
            .accessibilityActions { supersetWithNextAction(block) }
        } else {
            TemplateExerciseBuilder(exercise: block.exercises[0].exercise)
                .contentShape(.rect)
                .onDrag {
                    startDrag(block.exercises)
                } preview: {
                    DragPreview(exercises: block.exercises)
                }
                .contextMenu { exerciseMenu(block.exercises[0]) }
                .accessibilityActions { supersetWithNextAction(block) }
        }
    }

    @ViewBuilder
    private func exerciseMenu(_ templateExerciseDraft: TemplateExerciseDraft) -> some View {
        Button("Edit", systemImage: "pencil") {
            handleEdit(templateExerciseDraft.exercise)
        }
        Button("Remove", systemImage: "trash", role: .destructive) {
            templateWorkoutDraft.removeTemplateExercises(at: IndexSet(integer: templateExerciseDraft.order))
        }
    }

    /// Remembers what's being dragged, so the cards it passes over can show where it would land.
    private func startDrag(_ exercises: [TemplateExerciseDraft]) -> NSItemProvider {
        draggedIDs = exercises.map(\.id)
        return NSItemProvider(object: exercises.map(\.exercise.exerciseName).joined(separator: ", ") as NSString)
    }

    /// An outline when the drag would stack onto this card, or a line on the edge it would move to.
    @ViewBuilder
    private func dropIndicator(on block: TemplateExerciseBlock) -> some View {
        if let dropTarget, dropTarget.blockID == block.id {
            Group {
                switch dropTarget.placement {
                case .onto:
                    RoundedRectangle(cornerRadius: LayoutMetrics.panelCornerRadius)
                        .strokeBorder(.indigo, lineWidth: 2)
                case .before:
                    insertionLine
                        .frame(maxHeight: .infinity, alignment: .top)
                case .after:
                    insertionLine
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var insertionLine: some View {
        Capsule()
            .fill(.indigo)
            .frame(height: 3)
            .padding(.horizontal, 8)
    }
}

extension TemplateWorkoutBuilder {
    /// Drag and drop for VoiceOver: stacks the next card onto this one.
    @ViewBuilder
    private func supersetWithNextAction(_ block: TemplateExerciseBlock) -> some View {
        let blocks = templateWorkoutDraft.blocks
        if let index = blocks.firstIndex(where: { $0.id == block.id }), blocks.indices.contains(index + 1) {
            Button("Superset With Next") {
                templateWorkoutDraft.drop(blocks[index + 1].exercises.map(\.id), on: block, at: .onto)
            }
        }
    }
}

/// The card a drag is over, and where on it the dragged exercises would land.
private struct StackDropTarget: Equatable {
    let blockID: UUID
    let placement: StackPlacement
}

/// Drops dragged exercises on a card. Near its top or bottom edge they move above or below it;
/// anywhere else they stack onto it.
private struct StackDropDelegate: DropDelegate {
    /// How close to a card's top or bottom a drop moves the exercises instead of stacking them.
    private static let edgeHeight: CGFloat = 22

    let block: TemplateExerciseBlock
    let height: CGFloat
    @Binding var draft: TemplateWorkoutDraft
    @Binding var draggedIDs: [UUID]
    @Binding var target: StackDropTarget?

    func validateDrop(info: DropInfo) -> Bool {
        !draggedIDs.isEmpty
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let placement = placement(at: info.location)
        // Nothing to show where a drop would change nothing, like a card over itself.
        let changes = draft.dropping(draggedIDs, on: block, at: placement) != nil
        let newTarget = changes ? StackDropTarget(blockID: block.id, placement: placement) : nil
        if target != newTarget {
            target = newTarget
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if target?.blockID == block.id {
            target = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let placement = placement(at: info.location)
        if placement == .onto {
            SupersetHint().invalidate(reason: .actionPerformed)
        }
        draft.drop(draggedIDs, on: block, at: placement)
        target = nil
        draggedIDs = []
        return true
    }

    private func placement(at location: CGPoint) -> StackPlacement {
        let edge = min(Self.edgeHeight, height / 3)
        if location.y < edge { return .before }
        if location.y > height - edge { return .after }
        return .onto
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
/// Drag the header to move the whole superset, or an exercise to lift it out.
struct SupersetBuilder<ExerciseMenu: View>: View {
    let exercises: [TemplateExerciseDraft]
    let drag: ([TemplateExerciseDraft]) -> NSItemProvider
    let unstack: () -> Void
    @ViewBuilder let exerciseMenu: (TemplateExerciseDraft) -> ExerciseMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                Text("Superset")
                Spacer()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.indigo)
            .padding(.horizontal, 15)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(.rect)
            .onDrag {
                drag(exercises)
            } preview: {
                DragPreview(exercises: exercises)
            }
            .contextMenu {
                Button("Unstack", systemImage: "square.split.1x2", action: unstack)
            }

            ForEach(exercises) { templateExerciseDraft in
                if templateExerciseDraft.id != exercises.first?.id {
                    Divider()
                        .padding(.horizontal, 15)
                }
                TemplateExerciseLabel(exercise: templateExerciseDraft.exercise)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onDrag {
                        drag([templateExerciseDraft])
                    } preview: {
                        DragPreview(exercises: [templateExerciseDraft])
                    }
                    .contextMenu { exerciseMenu(templateExerciseDraft) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .powerJackGlassPanel()
    }
}

/// What follows a finger while dragging: the whole card, on a solid background so it stands out over the list.
private struct DragPreview: View {
    let exercises: [TemplateExerciseDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(exercises) { templateExerciseDraft in
                if templateExerciseDraft.id != exercises.first?.id {
                    Divider()
                        .padding(.horizontal, 15)
                }
                TemplateExerciseLabel(exercise: templateExerciseDraft.exercise)
            }
        }
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: LayoutMetrics.panelCornerRadius))
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
