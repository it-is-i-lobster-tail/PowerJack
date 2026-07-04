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
            List(workoutExercise.workoutSets) { workoutSet in
                VStack {
                    WorkoutSetView(
                        screenWidth: screenWidth,
                        workoutSet: workoutSet,
                        focusedSetField: focusedSetField
                    )
                    .frame(width: screenWidth * 0.82, height: 45)
                    
                    Color.gray.opacity(0.2)
                        .frame(width: screenWidth * 0.75, height: 1)
                        .padding(.vertical, 8)
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
