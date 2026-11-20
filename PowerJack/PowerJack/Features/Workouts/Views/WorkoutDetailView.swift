//
//  WorkoutDetailView.swift
//  PowerJack
//
//  Created on 6/24/26.
//

import SwiftData
import SwiftUI

/// Sheets the workout presents for the selected exercise.
private enum WorkoutSheet: Identifiable, Hashable {
    case feedback(WorkoutExercise)
    case checkIn(WorkoutExercise)

    // Models hash by their persistent ID, so each exercise gets its own sheet identity.
    var id: Self { self }

    var workoutExercise: WorkoutExercise {
        switch self {
        case .feedback(let workoutExercise), .checkIn(let workoutExercise): workoutExercise
        }
    }

    /// Answered already, here or on the watch, so the sheet has nothing left to ask.
    var isAnswered: Bool {
        switch self {
        case .feedback(let workoutExercise): !workoutExercise.needsFeedback
        case .checkIn(let workoutExercise): !workoutExercise.checkInPending
        }
    }
}

/// The superset sheets opened from the ••• menu.
private enum SupersetSheet: Identifiable, Hashable {
    case add(WorkoutExercise)
    case edit(UUID)

    var id: Self { self }
}

extension EnvironmentValues {
    /// Set by `WorkoutDetailView` when it shows a finished workout.
    @Entry var workoutIsReadOnly = false
    /// Set by `WorkoutDetailView` when a finished workout is unlocked, so its logged sets can be fixed.
    @Entry var workoutAllowsCorrections = false
    @Entry var workoutUnlocks = WorkoutUnlocks.shared
}

struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // Optional so the view still works outside the Programs navigation stack.
    @Environment(ProgramsRouter.self) private var router: ProgramsRouter?
    @Environment(\.workoutUnlocks) private var unlocks
    @Environment(IdleControls.self) private var idleControls: IdleControls?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @Bindable var workout: Workout
    let onWorkoutFinished: () -> Void
    let onSkipWorkout: (() -> Void)?
    /// A finished workout opens read-only: nothing can be logged, changed or skipped.
    let isReadOnly: Bool

    @FocusState private var focusedSetField: FocusedSetField?
    @State private var selectedExerciseIndex: Int?
    @State private var isShowingWorkoutExerciseSheet = false
    @State private var presentedSheet: WorkoutSheet?
    @State private var exerciseToEdit: Exercise?
    @State private var supersetSheet: SupersetSheet?
    /// Finish Workout is asking partly logged exercises for feedback, one at a time, before it finishes.
    @State private var finishesAfterFeedback = false
    /// Where the pages are scrolled to. The strip and the header follow it.
    @State private var pageScroll = ExercisePageScroll()

    /// Lets a set's check draw in before scrolling to the next superset member.
    private static let supersetSlideDelay = 0.35

    init(
        workout: Workout,
        initialExerciseIndex: Int? = nil,
        onWorkoutFinished: @escaping () -> Void = {},
        onSkipWorkout: (() -> Void)? = nil,
        isReadOnly: Bool = false
    ) {
        self.workout = workout
        self.onWorkoutFinished = onWorkoutFinished
        self.onSkipWorkout = onSkipWorkout
        self.isReadOnly = isReadOnly
        // A finished workout opens on its first exercise; a live one on where the user left off.
        _selectedExerciseIndex = State(initialValue: isReadOnly ? 0 : initialExerciseIndex ?? Self.nextIndex(in: workout))
    }

    /// The first exercise still waiting, or the Review page once every exercise is done.
    private static func nextIndex(in workout: Workout) -> Int {
        workout.allExercisesFinished ? workout.workoutExercises.count : workout.currentExerciseIndex
    }

    /// A finished workout the lifter unlocked to fix the weight and reps they logged.
    private var isUnlocked: Bool {
        isReadOnly && unlocks.isUnlocked(workout)
    }

    private var isOnReview: Bool {
        !isReadOnly && selectedExerciseIndex == workout.workoutExercises.count
    }

    /// The bars fade while a live workout sits idle. VoiceOver needs them in place.
    private var fadesIdleControls: Bool {
        !isReadOnly && !voiceOverEnabled
    }

    private var controlsHidden: Bool {
        idleControls?.isHidden == true
    }

    private var selectedWorkoutExercise: WorkoutExercise? {
        guard let selectedExerciseIndex,
              workout.workoutExercises.indices.contains(selectedExerciseIndex)
        else {
            return nil
        }
        return workout.workoutExercises[selectedExerciseIndex]
    }

    var body: some View {
        let pages = WorkoutPage.pages(for: workout)
        if pages.isEmpty {
            // Nothing to log, so skipping is the way on to the next workout.
            ContentUnavailableView {
                Label("No exercises", systemImage: "dumbbell")
            } description: {
                if !isReadOnly {
                    Text("This day has no exercises left.")
                }
            } actions: {
                if !isReadOnly {
                    Button("Skip Workout", action: skipEmptyWorkout)
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            GeometryReader { geometry in
                WorkoutDetailContent(
                    screenWidth: geometry.size.width,
                    topInset: geometry.safeAreaInsets.top,
                    pages: pages,
                    selectedExerciseIndex: $selectedExerciseIndex,
                    focusedSetField: $focusedSetField,
                    onExerciseSetsDone: handleSetsDone,
                    review: isReadOnly ? nil : WorkoutReviewView(
                        workout: workout,
                        onSelectExercise: selectExercise,
                        onSkipRemainingSets: skipRemainingSets,
                        onFinish: finishWorkout
                    ),
                    pageScroll: pageScroll
                )
                // The sets scroll up under the navigation bar. The reader still measures the bar,
                // so the content can add room for it.
                .ignoresSafeArea(.container, edges: .top)
                .environment(\.workoutIsReadOnly, isReadOnly)
                .environment(\.workoutAllowsCorrections, isUnlocked)
                .navigationBarTitleDisplayMode(.inline)
                // The system Back button also enables swipe-to-pop. On Review the pager owns that swipe.
                .navigationBarBackButtonHidden(controlsHidden || isOnReview)
                .toolbar {
                    if isOnReview && !controlsHidden {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Back", systemImage: "chevron.backward") { dismiss() }
                                .labelStyle(.iconOnly)
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        WorkoutHeader(
                            pages: pages.map(\.header) + (isReadOnly ? [] : [.review]),
                            controlsHidden: controlsHidden,
                            pageScroll: pageScroll,
                            idleWidth: max(0, geometry.size.width - 2 * LayoutMetrics.sectionSpacing)
                        )
                    }

                    if isReadOnly {
                        ToolbarItem(placement: .topBarTrailing) {
                            completedWorkoutMenu
                        }
                    } else {
                        ToolbarItem(placement: .topBarTrailing) {
                            WorkoutActionsMenu(
                                workout: workout,
                                selectedExerciseIndex: $selectedExerciseIndex,
                                isShowingWorkoutExerciseSheet: $isShowingWorkoutExerciseSheet,
                                onEditExercise: editExercise,
                                onSkipWorkout: onSkipWorkout,
                                onAddToSuperset: { showSupersetSheet(.add($0)) },
                                onEditSuperset: { showSupersetSheet(.edit($0)) }
                            )
                            // Faded rather than removed, so an open menu isn't torn down with it.
                            .fadesWhenIdle(idleControls)
                        }
                        .sharedBackgroundVisibility(controlsHidden ? .hidden : .visible)
                    }
                }
                .sheet(isPresented: $isShowingWorkoutExerciseSheet) {
                    if let selectedWorkoutExercise {
                        ExerciseSelectionView(
                            navigationTitle: "Change Exercise",
                            onSelect: { exercise in
                                selectedWorkoutExercise.changeExercise(newExercise: exercise)
                                save()
                            }
                        )
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    }
                }
                .sheet(item: $supersetSheet) { sheet in
                    switch sheet {
                    case .add(let workoutExercise):
                        SupersetPicker(workout: workout, workoutExercise: workoutExercise) { choice in
                            workout.addToSuperset(workoutExercise, with: choice)
                            save()
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    case .edit(let supersetID):
                        WorkoutSupersetEditor(workout: workout, supersetID: supersetID)
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                    }
                }
                .navigationDestination(isPresented: isEditingExercise) {
                    if let exerciseToEdit {
                        ExerciseDetailView(exercise: exerciseToEdit)
                    }
                }
            }
            // Keep the workout layout steady as the number pad slides over the bottom tabs.
            .keyboardSlidesOver()
            .sheet(item: $presentedSheet, onDismiss: continueFinishing) { sheet in
                switch sheet {
                case .feedback(let workoutExercise):
                    Feedback(
                        workoutExercise: workoutExercise,
                        onFinished: { if !finishesAfterFeedback { advance() } }
                    )
                    .padding(.horizontal, LayoutMetrics.sectionSpacing)
                    .interactiveDismissDisabled()
                    .presentationDragIndicator(.hidden)
                case .checkIn(let workoutExercise):
                    ManualCheckInSheet(
                        workoutExercise: workoutExercise,
                        onResolved: { handleCheckInResolved(workoutExercise) }
                    )
                    .padding(.horizontal, LayoutMetrics.sectionSpacing)
                    .interactiveDismissDisabled()
                    .presentationDragIndicator(.hidden)
                }
            }
            .onAppear {
                showRequestedExercise()
                presentSheetIfNeeded()
            }
            .onChange(of: selectedExerciseIndex) { previous, selected in
                presentSheetIfNeeded()
                // Logging a set within the same page keeps the bars in their current idle state.
                if !pages.contains(where: { $0.indices.contains(previous ?? -1) && $0.indices.contains(selected ?? -1) }) {
                    idleControls?.show()
                }
            }
            // Keep the strip available through a long scrub and while the number pad is open.
            .onChange(of: focusedSetField != nil || pageScroll.stripPhase.isScrolling || pageScroll.swipeStartPage != nil) { _, interacting in
                idleControls?.pause(interacting)
            }
            .onChange(of: fadesIdleControls, initial: true) { _, fades in
                fades ? idleControls?.turnOn() : idleControls?.turnOff()
            }
            .onDisappear { idleControls?.turnOff() }
            .onChange(of: presentedSheet?.isAnswered == true) { _, isAnswered in
                if isAnswered { closeAnsweredSheet() }
            }
            .onChange(of: router?.currentExerciseRequest) {
                showRequestedExercise()
            }
            .onChange(of: workout.currentSet?.workoutSet.id) { previousSetID, _ in
                followSuperset(after: previousSetID)
            }
            .onChange(of: workout.workoutExercises.map(ObjectIdentifier.init)) { before, after in
                keepSelection(from: before, to: after)
            }
        }
    }

    /// A finished workout's one action: unlocking it to fix what was logged, then locking it again.
    private var completedWorkoutMenu: some View {
        Menu {
            if isUnlocked {
                Button {
                    focusedSetField = nil
                    unlocks.lock(workout)
                } label: {
                    Label("Lock workout", systemImage: "lock")
                }
            } else {
                Button {
                    unlocks.unlock(workout)
                } label: {
                    Label("Unlock completed workout", systemImage: "lock.open")
                    Text("Allows edits until app closes.")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    private func editExercise(_ exercise: Exercise) {
        focusedSetField = nil
        exerciseToEdit = exercise
    }

    /// A timer tap follows the same set as the countdown, even when earlier exercises are unfinished.
    private func showRequestedExercise() {
        guard !isReadOnly, let router, let index = router.requestedExerciseIndex(in: workout) else { return }
        router.didShowRequestedExercise()
        selectExercise(index)
    }

    /// Shows the exercise opened from the ••• menu. A Bool binding rather than `item:`, because the compiler can
    /// lose track of `Exercise` being Hashable in this file when it's built alongside some other files.
    private var isEditingExercise: Binding<Bool> {
        Binding(
            get: { exerciseToEdit != nil },
            set: { if !$0 { exerciseToEdit = nil } }
        )
    }

    private func showSupersetSheet(_ sheet: SupersetSheet) {
        focusedSetField = nil
        supersetSheet = sheet
    }

    /// Exercises moved, e.g. into or out of a superset: stays on the exercise the user was looking at.
    private func keepSelection(from before: [ObjectIdentifier], to after: [ObjectIdentifier]) {
        guard let selectedExerciseIndex else { return }
        if selectedExerciseIndex == before.count {
            self.selectedExerciseIndex = after.count
        } else if before.indices.contains(selectedExerciseIndex),
                  let index = after.firstIndex(of: before[selectedExerciseIndex]),
                  index != selectedExerciseIndex {
            self.selectedExerciseIndex = index
        }
    }

    /// In a superset, slides to the exercise whose turn it is once a set is checked off.
    /// Waits for the check to draw in first. A superset changed from the menu changes whose turn
    /// it is without a set being checked off, and the user stays where they are.
    private func followSuperset(after previousSetID: PersistentIdentifier?) {
        guard
            !isReadOnly,
            presentedSheet == nil,
            let previousSetID,
            workout.workoutExercises.contains(where: { workoutExercise in
                workoutExercise.workoutSets.contains { $0.id == previousSetID && $0.isDone }
            }),
            let selectedWorkoutExercise,
            let next = workout.currentSet?.workoutExercise,
            selectedWorkoutExercise.supersetPartners.contains(where: { $0 === next }),
            let index = workout.workoutExercises.firstIndex(where: { $0 === next })
        else {
            return
        }
        focusedSetField = nil
        withAnimation(.easeInOut(duration: 0.325).delay(Self.supersetSlideDelay)) {
            selectedExerciseIndex = index
        }
    }

    private func selectExercise(_ index: Int) {
        withAnimation(.easeInOut(duration: 0.325)) {
            selectedExerciseIndex = index
        }
    }

    /// Skipped from the Review page, which stays put; feedback still opens if sets were logged.
    private func skipRemainingSets(_ workoutExercise: WorkoutExercise) {
        workoutExercise.skipRemainingSets()
        save()
        if workoutExercise.needsFeedback, presentedSheet == nil {
            presentedSheet = .feedback(workoutExercise)
        }
    }

    private func skipEmptyWorkout() {
        if let onSkipWorkout {
            onSkipWorkout()
        } else {
            workout.skipAndCascade()
            save()
        }
    }

    /// Only the Finish Workout button ends the workout. Anything still unlogged is skipped, and an
    /// exercise that was only partly logged is rated first, so next week's plan counts it.
    private func finishWorkout() {
        focusedSetField = nil
        workout.skipRemainingSets()
        save()
        finishesAfterFeedback = true
        askFeedbackOrFinish()
    }

    /// Runs as each sheet closes, to ask the next question while Finish Workout is waiting on feedback.
    private func continueFinishing() {
        if finishesAfterFeedback { askFeedbackOrFinish() }
    }

    /// Asks the next unrated exercise's feedback, and finishes once none is left.
    private func askFeedbackOrFinish() {
        guard let unrated = workout.workoutExercises.first(where: \.needsFeedback) else {
            finishesAfterFeedback = false
            onWorkoutFinished()
            return
        }
        // A sheet still closing comes back here when it's gone.
        if presentedSheet == nil {
            presentedSheet = .feedback(unrated)
        }
    }

    /// Shows feedback or a manual check-in when the selected exercise is waiting on one.
    /// Runs on appear too, so a relaunch mid-feedback resumes where the user left off.
    private func presentSheetIfNeeded() {
        guard !isReadOnly, presentedSheet == nil, let selectedWorkoutExercise else { return }

        if selectedWorkoutExercise.needsFeedback {
            focusedSetField = nil
            presentedSheet = .feedback(selectedWorkoutExercise)
        } else if selectedWorkoutExercise.checkInPending {
            focusedSetField = nil
            presentedSheet = .checkIn(selectedWorkoutExercise)
        }
    }

    private func handleSetsDone(_ workoutExercise: WorkoutExercise) {
        save()
        if workoutExercise.needsFeedback {
            focusedSetField = nil
            if presentedSheet == nil {
                presentedSheet = .feedback(workoutExercise)
            }
        } else if workoutExercise.isDone {
            advance()
        }
    }

    /// The watch answered the open sheet first. Close it and move on, as if it was answered here.
    private func closeAnsweredSheet() {
        guard let workoutExercise = presentedSheet?.workoutExercise else { return }
        presentedSheet = nil
        if workoutExercise.isDone {
            advance()
        }
    }

    private func handleCheckInResolved(_ workoutExercise: WorkoutExercise) {
        save()
        if workoutExercise.isDone {
            advance()
        }
    }

    /// Moves to the next unfinished exercise, or the Review page once every exercise is done.
    /// Changes made from the Review page keep the user there.
    private func advance() {
        guard !isOnReview else { return }
        focusedSetField = nil
        withAnimation(.easeInOut(duration: 0.325)) {
            selectedExerciseIndex = Self.nextIndex(in: workout)
        }
    }

    private func save() {
        modelContext.saveTraced("workout")
    }
}

#Preview("WorkoutDetailView - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        WorkoutDetailView(workout: scenario.weekOneWorkouts[2])
    }
}

#Preview("WorkoutDetailView - Week 2") {
    let scenario = PowerJackSeed.weekTwoProgression()

    NavigationPreviewHost(modelContainer: scenario.container) {
        WorkoutDetailView(workout: scenario.weekTwoWorkouts[0])
    }
}

#Preview("WorkoutDetailView - Read Only") {
    let scenario = PowerJackSeed.weekTwoProgression()

    NavigationPreviewHost(modelContainer: scenario.container) {
        WorkoutDetailView(
            workout: scenario.weekOneWorkouts[0],
            isReadOnly: true
        )
    }
}

#Preview("WorkoutDetailView - Empty") {
    let scenario = PowerJackSeed.emptyWorkout()

    NavigationPreviewHost(modelContainer: scenario.container) {
        WorkoutDetailView(workout: scenario.workout)
    }
}
