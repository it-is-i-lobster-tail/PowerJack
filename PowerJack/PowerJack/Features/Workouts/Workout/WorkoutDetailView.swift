//
//  WorkoutView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    @Bindable var workout: Workout
    @FocusState private var focusedSetField: FocusedSetField?
    @State private var selectedExerciseIndex: Int? = 0
    @State private var isShowingWorkoutExerciseSheet = false
    
    func canAddSet() -> Bool {
        if let selectedExerciseIndex {
            let canAdd =
            workout.workoutExercises[selectedExerciseIndex].totalSets < WorkoutExercise.maxSets &&
            !workout.workoutExercises[selectedExerciseIndex].locked
            
            return canAdd
        } else {
            return false
        }
    }
    
    func canChangeExercise() -> Bool {
        if let selectedExerciseIndex {
            let canChange =
            !workout.workoutExercises[selectedExerciseIndex].locked
            return canChange
        } else {
            return false
        }
    }
    
    func canRemoveLastSet() -> Bool {
        if let selectedExerciseIndex {
            let canChange =
            !workout.workoutExercises[selectedExerciseIndex].locked
            return canChange
        } else {
            return false
        }
    }
    
    func canSkipRemainingSets() -> Bool {
        if let selectedExerciseIndex {
            let canChange =
            !workout.workoutExercises[selectedExerciseIndex].locked
            return canChange
        } else {
            return false
        }
    }
    
    func canSkipWorkout() -> Bool {
        let canChange =
        !workout.locked
        return canChange
    }

    var body: some View {
        if workout.workoutExercises.isEmpty {
            Text("No exercises")
        } else {
            GeometryReader { geometry in
                let screenWidth = geometry.size.width
                let screenHeight = geometry.size.height
                let contentHeight = max(0, screenHeight - SpacingPJ.headerControlHeight)

                ZStack {
                    VStack {
                        WorkoutExercisePager(
                            screenWidth: screenWidth,
                            workoutExercises: workout.workoutExercises,
                            selectedExerciseIndex: $selectedExerciseIndex,
                            focusedSetField: $focusedSetField
                        )
                        .frame(
                            width: screenWidth,
                            height: contentHeight * 0.85
                        )

                        ExercisePreviewStrip(
                            workoutExercises: workout.workoutExercises,
                            screenWidth: screenWidth,
                            selectedExerciseIndex: $selectedExerciseIndex
                        )
                        .frame(
                            width: screenWidth,
                            height: contentHeight * 0.1
                        )
                    }
                }
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
                        .background(.regularMaterial, in: Capsule())
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let selectedExerciseIndex {
                                Button {
                                    _ = workout.workoutExercises[selectedExerciseIndex].addSet()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                        Text("Add Set")
                                    }
                                }
                                .disabled(!canAddSet())
     
                                
                                Button {
                                    isShowingWorkoutExerciseSheet.toggle()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "slider.horizontal.3")
                                        Text("Change Exercise")
                                    }
                                }
                                .disabled(!canChangeExercise())
                                
                                Button() {
                                    _ = workout.workoutExercises[selectedExerciseIndex].removeLastSet()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                        Text("Remove Last Set")
                                    }
                                }
                                .disabled(!canRemoveLastSet())
                                
                                Divider()
                                
                                Button() {
                                    workout.workoutExercises[selectedExerciseIndex].skipAndCascade()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "forward")
                                        Text("Skip Remaining Sets")
                                    }
                                }
                                .disabled(!canSkipRemainingSets())
                                
                            }
                            
                            Button() {
                                workout.skipAndCascade()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "forward.end")
                                    Text("Skip Workout")
                                }
                            }
                            .disabled(!canSkipWorkout())

                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
                .sheet(isPresented: $isShowingWorkoutExerciseSheet) {
                    if let selectedExerciseIndex {
                        ExerciseSelection(
                            workoutExerciseToChange: workout.workoutExercises[selectedExerciseIndex],
                            navigationTitle: "Change Exercise"
                        )
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    }
                }
            }
        }
    }
}

#Preview("WorkoutDetailView - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        WorkoutDetailView(workout: scenario.weekOneWorkouts[2])
    }
    .modelContainer(scenario.container)
}

#Preview("WorkoutDetailView - Empty") {
    let scenario = PowerJackSeed.emptyWorkout()

    NavigationStack {
        WorkoutDetailView(workout: scenario.workout)
    }
    .modelContainer(scenario.container)
}
