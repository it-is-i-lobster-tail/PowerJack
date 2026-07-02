//
//  WorkoutView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Bindable var workout: Workout
    @FocusState private var focusedSetField: FocusedSetField?
    @State private var selectedExerciseIndex: Int? = 0
    @State private var showOptions = false
    
    private var orderedWorkoutExercises: [WorkoutExercise] {
        workout.workoutExercises.sorted { $0.order < $1.order}
    }

    var body: some View {
        if orderedWorkoutExercises.isEmpty {
            Text("No exercises")
        } else {
            GeometryReader { geometry in
                let screenWidth = geometry.size.width
                let screenHeight = geometry.size.height
                
                ZStack {
//                    
//                     SetView Focus
//                    
//                    if !showOptions {
//                        Rectangle()
//                            .fill(.clear)
//                            .contentShape(Rectangle())
//                            .onTapGesture {
//                                focusedSetField = nil
//                                }
//                            .border(.red)
//                    }
                    
                    VStack {
                        if let selectedExerciseIndex {
                            
                            //
                            // Header Controls
                            //
                            WorkoutHeaderControls(
                                workoutExercise: orderedWorkoutExercises[selectedExerciseIndex],
                                showOptions: $showOptions,
                            )
                            .frame(
                                width: screenWidth,
                                height: SpacingPJ.headerControlHeight
                            )
                        }

                        //
                        // Exercise Paper
                        //
                        WorkoutExercisePager(
                            screenWidth: screenWidth,
                            workoutExercises: orderedWorkoutExercises,
                            selectedExerciseIndex: $selectedExerciseIndex,
                            focusedSetField: $focusedSetField
                        )
                        .frame(
                            width: screenWidth,
                            height: (screenHeight - SpacingPJ.headerControlHeight) * 0.85
                        )

                        //
                        // Exercise Preview cards
                        //
                        ExercisePreviewStrip(
                            workoutExercises: orderedWorkoutExercises,
                            screenWidth: screenWidth,
                            selectedExerciseIndex: $selectedExerciseIndex
                        )
                        .frame(
                            width: screenWidth,
                            height: (screenHeight - SpacingPJ.headerControlHeight) * 0.1
                        )
                        
                    }
                    .onAppear{
                        workout.startAndCascade()
                    }
                    //
                    // Display Options Menu
                    //
                    if let selectedExerciseIndex {
                        FloatingMenuOverlay(
                            isPresented: $showOptions,
                            xOffset: (screenWidth / 4) - SpacingPJ.buttonStandardOffset + (SpacingPJ.buttonStandardSize / 2),
                            yOffset: (-screenHeight / 2 ) + 75 - (SpacingPJ.buttonStandardSize / 2)
                        ) {
                            WorkoutExerciseOptionsMenu(
                                screenWidth: screenWidth,
                                workoutExercise: orderedWorkoutExercises[selectedExerciseIndex],
                                showOptions: $showOptions
                            )
                        }
                    }
                }
            }
        }
    }
}

#Preview ("WorkoutView"){
    WorkoutView(workout: PreviewWorkout.workoutDay0Preview)
        .modelContainer(makeWorkoutPreviewContainer())
}
