//
//  WorkoutDetailView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    private static let headerControlHeight: CGFloat = 45

    @Bindable var workout: Workout
    @FocusState private var focusedSetField: FocusedSetField?
    @State private var selectedExerciseIndex: Int? = 0
    @State private var isShowingWorkoutExerciseSheet = false

    private var hasNextWorkoutExercise: Bool {
        guard let index = selectedExerciseIndex else { return false }
        return index < workout.workoutExercises.count - 1
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
                    nextWorkoutExercise: pushNextWorkoutExercise
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text("Day \(workout.order + 1)")
                                .font(.headline)

                            Text("Week 1/4")
                                .font(.caption)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        WorkoutActionsMenu(
                            workout: workout,
                            selectedExerciseIndex: selectedExerciseIndex,
                            isShowingWorkoutExerciseSheet: $isShowingWorkoutExerciseSheet
                        )
                    }
                }
                .sheet(isPresented: $isShowingWorkoutExerciseSheet) {
                    if let selectedExerciseIndex {
                        ExerciseSelectionView(
                            navigationTitle: "Change Exercise",
                            onSelect: { exercise in
                                workout.workoutExercises[selectedExerciseIndex]
                                    .changeExercise(newExercise: exercise)
                            }
                        )
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    }
                }
            }
        }
    }

    private func pushNextWorkoutExercise() {
        guard hasNextWorkoutExercise,
              let index = selectedExerciseIndex
        else {
            return
        }

        selectedExerciseIndex = index + 1
    }
}

#Preview("WorkoutDetailView - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        WorkoutDetailView(workout: scenario.weekOneWorkouts[2])
    }
}

#Preview("WorkoutDetailView - Empty") {
    let scenario = PowerJackSeed.emptyWorkout()

    NavigationPreviewHost(modelContainer: scenario.container) {
        WorkoutDetailView(workout: scenario.workout)
    }
}
