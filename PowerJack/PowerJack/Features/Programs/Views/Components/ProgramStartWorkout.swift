//
//  ProgramStartWorkout.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftUI

struct ProgramStartWorkout: View {
    let screenWidth: CGFloat
    let height: CGFloat
    let workout: Workout

    @State private var showWorkout = false

    var body: some View {
        Button(action: startWorkout) {
            if workout.status == .active {
                workoutNavigationLabel("Resume")
            } else {
                workoutNavigationLabel("Start Workout")
            }
        }
        .buttonStyle(.glassProminent)
        .navigationDestination(isPresented: $showWorkout) {
            WorkoutDetailView(workout: workout)
        }
        .frame(
            width: screenWidth,
            height: height
        )
    }

    private func workoutNavigationLabel(_ label: String) -> some View {
        Text(label)
            .font(.title3)
            .frame(
                width: screenWidth * 0.8,
                height: 48
            )
    }

    private func startWorkout() {
        if workout.status == .planned && workout.locked {
            workout.startAndCascade()
        }
        showWorkout = true
    }
}
