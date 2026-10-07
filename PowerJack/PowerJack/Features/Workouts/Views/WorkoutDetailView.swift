//
//  WorkoutDetailView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftData
import SwiftUI

/// Sheets the workout presents for the selected exercise.
private enum WorkoutSheet: Identifiable, Hashable {
    case feedback(WorkoutExercise)
    case checkIn(WorkoutExercise)

    // Models hash by their persistent ID, so each exercise gets its own sheet identity.
    var id: Self { self }
}

extension EnvironmentValues {
    /// Set by `WorkoutDetailView` when it shows a finished workout.
    @Entry var workoutIsReadOnly = false
}

struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var modelContext
    // Optional so the view still works outside the Programs navigation stack.
    @Environment(ProgramsRouter.self) private var router: ProgramsRouter?

    @Bindable var workout: Workout
    let weekNumber: Int?
    let weekCount: Int?
    let onWorkoutFinished: () -> Void
    let onSkipWorkout: (() -> Void)?
    /// A finished workout opens read-only: nothing can be logged, changed or skipped.
    let isReadOnly: Bool

    @FocusState private var focusedSetField: FocusedSetField?
    @State private var selectedExerciseIndex: Int?
    @State private var isShowingWorkoutExerciseSheet = false
    @State private var presentedSheet: WorkoutSheet?
    @State private var exerciseToEdit: Exercise?

    init(
        workout: Workout,
        weekNumber: Int? = nil,
        weekCount: Int? = nil,
        onWorkoutFinished: @escaping () -> Void = {},
        onSkipWorkout: (() -> Void)? = nil,
        isReadOnly: Bool = false
    ) {
        self.workout = workout
        self.weekNumber = weekNumber
        self.weekCount = weekCount
        self.onWorkoutFinished = onWorkoutFinished
        self.onSkipWorkout = onSkipWorkout
        self.isReadOnly = isReadOnly
        // A finished workout opens on its first exercise; a live one on where the user left off.
        _selectedExerciseIndex = State(initialValue: isReadOnly ? 0 : workout.currentExerciseIndex)
    }

    private var selectedWorkoutExercise: WorkoutExercise? {
        guard let selectedExerciseIndex,
              workout.workoutExercises.indices.contains(selectedExerciseIndex)
        else {
            return nil
        }
        return workout.workoutExercises[selectedExerciseIndex]
    }

    /// Until the first set is done, a hint explains how sets get logged.
    private var logSetHint: LogSetHint? {
        guard !isReadOnly,
              workout.getCountCompletedSets() == 0,
              let occasion = HintOccasion(weekNumber: weekNumber, workout: workout)
        else {
            return nil
        }
        return LogSetHint(occasion: occasion)
    }

    private var weekLabel: String? {
        guard let weekNumber else { return nil }
        guard let weekCount else { return "Week \(weekNumber)" }
        return "Week \(weekNumber)/\(weekCount)"
    }

    var body: some View {
        if workout.workoutExercises.isEmpty {
            EmptyStateView(
                title: "No exercises",
                systemImage: "dumbbell"
            )
        } else {
            GeometryReader { geometry in
                WorkoutDetailContent(
                    screenWidth: geometry.size.width,
                    workoutExercises: workout.workoutExercises,
                    selectedExerciseIndex: $selectedExerciseIndex,
                    focusedSetField: $focusedSetField,
                    onExerciseSetsDone: handleSetsDone
                )
                .environment(\.logSetHint, logSetHint)
                .environment(\.workoutIsReadOnly, isReadOnly)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text("Day \(workout.order + 1)")
                                .font(.headline)

                            if let weekLabel {
                                Text(weekLabel)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                    }

                    if !isReadOnly {
                        ToolbarItem(placement: .topBarTrailing) {
                            WorkoutActionsMenu(
                                workout: workout,
                                selectedExerciseIndex: selectedExerciseIndex,
                                isShowingWorkoutExerciseSheet: $isShowingWorkoutExerciseSheet,
                                onEditExercise: editExercise,
                                onSkipWorkout: onSkipWorkout
                            )
                        }
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
                .navigationDestination(item: $exerciseToEdit) { exercise in
                    ExerciseDetailView(exercise: exercise)
                }
            }
            // The number pad covers the exercise strip instead of pushing it up.
            .keyboardSlidesOver()
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .feedback(let workoutExercise):
                    Feedback(
                        workoutExercise: workoutExercise,
                        onFinished: { advance() }
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
            .onAppear(perform: presentSheetIfNeeded)
            .onChange(of: selectedExerciseIndex) {
                presentSheetIfNeeded()
            }
            .onChange(of: router?.currentExerciseRequest) {
                showCurrentExercise()
            }
        }
    }

    private func editExercise(_ exercise: Exercise) {
        focusedSetField = nil
        exerciseToEdit = exercise
    }

    /// Scrolls back to the exercise the user should be doing, e.g. after tapping the rest timer.
    private func showCurrentExercise() {
        withAnimation(.easeInOut(duration: 0.325)) {
            selectedExerciseIndex = workout.currentExerciseIndex
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
            presentedSheet = .feedback(workoutExercise)
        } else if workoutExercise.isFinished {
            advance()
        }
    }

    private func handleCheckInResolved(_ workoutExercise: WorkoutExercise) {
        save()
        if workoutExercise.isFinished {
            advance()
        }
    }

    /// Moves to the next unfinished exercise, or finishes the workout.
    private func advance() {
        guard !workout.allExercisesFinished else {
            focusedSetField = nil
            onWorkoutFinished()
            return
        }

        withAnimation(.easeInOut(duration: 0.325)) {
            selectedExerciseIndex = workout.currentExerciseIndex
        }
    }

    private func save() {
        try? modelContext.save()
    }
}

#Preview("WorkoutDetailView - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        WorkoutDetailView(
            workout: scenario.weekOneWorkouts[2],
            weekNumber: 1,
            weekCount: scenario.program.programLengthWeeks
        )
    }
}

#Preview("WorkoutDetailView - Week 2") {
    let scenario = PowerJackSeed.weekTwoProgression()

    NavigationPreviewHost(modelContainer: scenario.container) {
        WorkoutDetailView(
            workout: scenario.weekTwoWorkouts[0],
            weekNumber: 2,
            weekCount: scenario.program.programLengthWeeks
        )
    }
}

#Preview("WorkoutDetailView - Read Only") {
    let scenario = PowerJackSeed.weekTwoProgression()

    NavigationPreviewHost(modelContainer: scenario.container) {
        WorkoutDetailView(
            workout: scenario.weekOneWorkouts[0],
            weekNumber: 1,
            weekCount: scenario.program.programLengthWeeks,
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
