//
//  ExercisePreviewStrip.swift
//  PowerJack
//
//  Created by Brendon on 6/26/26.
//

import SwiftUI

struct ExercisePreviewStrip: View {
    let workoutExercises: [WorkoutExercise]
    let screenWidth: CGFloat
    @Binding var selectedExerciseIndex: Int?
    
    private func selectExercise(newIndex: Int) {
        withAnimation(.easeInOut(duration: 0.325)){
            selectedExerciseIndex = newIndex
        }
    }
    
    var body: some View {
        let cardwidth: CGFloat = 125
        let sideMargin = (screenWidth - cardwidth) / 2
        
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false){
                LazyHStack(spacing: 8) {
                    ForEach(workoutExercises.indices, id: \.self) { index in
                        Button{
                            selectExercise(newIndex: index)
                        } label: {
                            Text(workoutExercises[index].exercise.exerciseName)
                                .font(selectedExerciseIndex == index ? .default : .caption2)
                                .fontWeight(selectedExerciseIndex == index ? .medium : .thin)
                                .foregroundStyle(selectedExerciseIndex == index ? .white : .primary)
                                .frame(width: cardwidth, height: 54)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedExerciseIndex == index ? Color.accentColor : Color.gray.opacity(0.15))
                                )
                        }
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, sideMargin, for: .scrollContent)
            .onChange(of: selectedExerciseIndex) { oldValue, newValue in
                guard let newValue else { return }
                
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: 75)
    }
}
