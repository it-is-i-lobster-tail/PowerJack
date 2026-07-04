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
    @State private var showOptions = false

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

                    if let selectedExerciseIndex,
                       workout.workoutExercises.indices.contains(selectedExerciseIndex) {
                        FloatingMenuOverlay(
                            isPresented: $showOptions,
                            xOffset: (screenWidth / 4) - SpacingPJ.buttonStandardOffset + (SpacingPJ.buttonStandardSize / 2),
                            yOffset: (-screenHeight / 2) + 75 - (SpacingPJ.buttonStandardSize / 2)
                        ) {
                            WorkoutExerciseOptionsMenu(
                                screenWidth: screenWidth,
                                workoutExercise: workout.workoutExercises[selectedExerciseIndex],
                                showOptions: $showOptions
                            )
                        }
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
                                Button("Add Set") {
                                    workout.workoutExercises[selectedExerciseIndex].addSet()
                                }

                                Button("Remove Last Set", role: .destructive) {
                                    _ = workout.workoutExercises[selectedExerciseIndex].removeLastSet()
                                }
                            }

                            Button("Skip Workout", role: .destructive) {
                                workout.skipAndCascade()
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
            }
        }
    }
}
