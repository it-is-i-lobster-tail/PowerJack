//
//  WorkoutDetailView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftData
import SwiftUI

/// Sheets the workout presents for the selected exercise.
private enum WorkoutSheet: Identifiable {
    case feedback(WorkoutExercise)
    case checkIn(WorkoutExercise)

    var id: String {
        switch self {
        case .feedback(let workoutExercise): "feedback-\(workoutExercise.persistentModelID.hashValue)"
        case .checkIn(let workoutExercise): "checkIn-\(workoutExercise.persistentModelID.hashValue)"
        }
    }
}

struct WorkoutDetailView: View {
    private static let headerControlHeight: CGFloat = 45

    @Environment(\.modelContext) private var modelContext
    // Optional so the view still works outside the Programs navigation stack.
    @Environment(ProgramsRouter.self) private var router: ProgramsRouter?

    @Bindable var workout: Workout
    let weekNumber: Int?
    let weekCount: Int?
    let onWorkoutFinished: () -> Void
    let onSkipWorkout: (() -> Void)?

    @FocusState private var focusedSetField: FocusedSetField?
    @State private var selectedExerciseIndex: Int?
    @State private var isShowingWorkoutExerciseSheet = false
    @State private var presentedSheet: WorkoutSheet?

    init(
        workout: Workout,
        weekNumber: Int? = nil,
        weekCount: Int? = nil,
        onWorkoutFinished: @escaping () -> Void = {},
        onSkipWorkout: (() -> Void)? = nil
    ) {
        self.workout = workout
        self.weekNumber = weekNumber
        self.weekCount = weekCount
        self.onWorkoutFinished = onWorkoutFinished
        self.onSkipWorkout = onSkipWorkout
        _selectedExerciseIndex = State(initialValue: workout.currentExerciseIndex)
    }

    private var selectedWorkoutExercise: WorkoutExercise? {
        guard let selectedExerciseIndex,
              workout.workoutExercises.indices.contains(selectedExerciseIndex)
        else {
            return nil
        }
        return workout.workoutExercises[selectedExerciseIndex]
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
                let screenWidth = geometry.size.width
                let screenHeight = geometry.size.height
                let contentHeight = max(0, screenHeight - Self.headerControlHeight)

                WorkoutDetailContent(
                    screenWidth: screenWidth,
                    contentHeight: contentHeight,
                    workoutExercises: workout.workoutExercises,
                    selectedExerciseIndex: $selectedExerciseIndex,
                    focusedSetField: $focusedSetField,
                    onExerciseSetsDone: handleSetsDone
                )
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

                    ToolbarItem(placement: .topBarTrailing) {
                        WorkoutActionsMenu(
                            workout: workout,
                            selectedExerciseIndex: selectedExerciseIndex,
                            isShowingWorkoutExerciseSheet: $isShowingWorkoutExerciseSheet,
                            onSkipWorkout: onSkipWorkout
                        )
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
            }
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

    /// Scrolls back to the exercise the user should be doing, e.g. after tapping the rest timer.
    private func showCurrentExercise() {
        withAnimation(.easeInOut(duration: 0.325)) {
            selectedExerciseIndex = workout.currentExerciseIndex
        }
    }

    /// Shows feedback or a manual check-in when the selected exercise is waiting on one.
    /// Runs on appear too, so a relaunch mid-feedback resumes where the user left off.
    private func presentSheetIfNeeded() {
        guard presentedSheet == nil, let selectedWorkoutExercise else { return }

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

#Preview("WorkoutDetailView - Empty") {
    let scenario = PowerJackSeed.emptyWorkout()

    NavigationPreviewHost(modelContainer: scenario.container) {
        WorkoutDetailView(workout: scenario.workout)
    }
}
