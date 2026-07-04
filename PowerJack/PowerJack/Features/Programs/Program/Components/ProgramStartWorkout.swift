//
//  ProgramStartWorkout.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftData
import SwiftUI
import OSLog

struct ProgramStartWorkout: View {
    let screenWidth: CGFloat
    let hight: CGFloat
    let workout: Workout

    @State private var showWorkout = false
    
    private func workoutNavText(buttonLabel: String) -> some View {
        Text("\(buttonLabel)")
            .font(.title3)
            .frame(
                width: screenWidth * 0.8,
                height: 48
            )
    }
    
    var body: some View {
        Button {
            if workout.status == .planned && workout.locked {
                workout.startAndCascade()
            }
            showWorkout = true
        } label: {
            if workout.status == .active {
                workoutNavText(buttonLabel: "Resume")
            } else {
                workoutNavText(buttonLabel: "Start Workout")
            }
        }
        .buttonStyle(GlassPressButtonStyle())
                .navigationDestination(isPresented: $showWorkout) {
                    WorkoutDetailView(workout: workout)
                }
                .frame(
                    width: screenWidth,
                    height: hight
                )
                .glassEffect(
                    .regular.tint(.white.opacity(OpacityPJ.focusThin)),
                    in: .rect(cornerRadius: 14)
                )
    }
}
