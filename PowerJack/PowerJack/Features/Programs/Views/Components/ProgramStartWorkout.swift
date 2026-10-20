//
//  ProgramStartWorkout.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftData
import SwiftUI

struct ProgramStartWorkout: View {
    let program: Program
    let workout: Workout

    @Environment(\.modelContext) private var modelContext
    @Environment(ProgramsRouter.self) private var router

    var body: some View {
        Button(action: startWorkout) {
            Text(workout.status == .active ? "Resume" : "Start Workout")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.glassProminent)
    }

    private func startWorkout() {
        if workout.status == .planned && workout.locked {
            HintOccasion.workoutStarted(weekNumber: program.weekNumber(containing: workout), workout: workout)
            program.prepareToStart(workout)
            workout.startAndCascade()
            try? modelContext.save()
        }
        router.showSession(program)
    }
}
