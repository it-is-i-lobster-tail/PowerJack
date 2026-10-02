//
//  ProgramStartWorkout.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftData
import SwiftUI

struct ProgramStartWorkout: View {
    let screenWidth: CGFloat
    let height: CGFloat
    let program: Program
    let workout: Workout

    @Environment(\.modelContext) private var modelContext
    @Environment(ProgramsRouter.self) private var router

    var body: some View {
        Button(action: startWorkout) {
            if workout.status == .active {
                workoutNavigationLabel("Resume")
            } else {
                workoutNavigationLabel("Start Workout")
            }
        }
        .buttonStyle(.glassProminent)
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
            try? modelContext.save()
        }
        router.showSession(program)
    }
}
