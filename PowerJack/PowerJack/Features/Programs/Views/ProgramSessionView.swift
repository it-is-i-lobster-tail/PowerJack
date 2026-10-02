//
//  ProgramSessionView.swift
//  PowerJack
//
//  Runs a program workout-to-workout: shows the current workout and advances when it finishes.
//

import OSLog
import SwiftData
import SwiftUI

struct ProgramSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProgramsRouter.self) private var router

    let program: Program

    var body: some View {
        Group {
            if let workout = program.nextWorkout {
                WorkoutDetailView(
                    workout: workout,
                    weekNumber: program.weekNumber(containing: workout),
                    weekCount: program.programLengthWeeks,
                    onWorkoutFinished: { finish(workout) },
                    onSkipWorkout: { skip(workout) }
                )
                .id(workout.persistentModelID)
                .transition(.push(from: .trailing))
            } else {
                EmptyStateView(
                    title: "Program complete",
                    systemImage: "checkmark.seal"
                )
            }
        }
        .animation(.easeInOut(duration: 0.35), value: program.nextWorkout?.persistentModelID)
        .onAppear(perform: startCurrentWorkout)
    }

    private func startCurrentWorkout() {
        guard let workout = program.nextWorkout, workout.status == .planned else { return }
        workout.startAndCascade()
        save()
    }

    private func finish(_ workout: Workout) {
        let next = program.finishWorkout(workout)
        save()
        if next == nil {
            router.popToRoot()
        }
    }

    private func skip(_ workout: Workout) {
        let next = program.skipWorkout(workout)
        save()
        if next == nil {
            router.popToRoot()
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            Logger.ui.error("Could not save program progress: \(error.localizedDescription)")
        }
    }
}

#Preview("ProgramSessionView - Week 1") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ProgramSessionView(program: scenario.program)
    }
}

#Preview("ProgramSessionView - Week 2 Progression") {
    let scenario = PowerJackSeed.weekTwoProgression()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ProgramSessionView(program: scenario.program)
    }
}
