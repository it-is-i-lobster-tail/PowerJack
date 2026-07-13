//
//  LiftView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI
import SwiftData

struct WorkoutExerciseView: View {
    let screenWidth: CGFloat
    @Environment(\.modelContext) private var modelContext
    @Bindable var workoutExercise: WorkoutExercise
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    
    var body: some View {
        VStack{
            VStack(alignment: .center) {
                Text(workoutExercise.exercise.exerciseName)
                    .font(.title)
                    .foregroundStyle(.primary)
                Text(workoutExercise.exercise.exerciseEquipment.rawValue)
                    .font(.default)
                    .foregroundStyle(.primary)
            }
            List(Array(workoutExercise.workoutSets.enumerated()), id: \.element.id) { index, workoutSet in

                VStack {
                    WorkoutSetView(
                        screenWidth: screenWidth,
                        workoutSet: workoutSet,
                        focusedSetField: focusedSetField
                    )
                    .frame(width: screenWidth * 0.88, height: 55)
                    
                    if index < (workoutExercise.workoutSets.count - 1) {
                        Color.gray.opacity(0.2)
                            .frame(width: screenWidth * 0.75, height: 1)
                            .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            
        }
    }
}
