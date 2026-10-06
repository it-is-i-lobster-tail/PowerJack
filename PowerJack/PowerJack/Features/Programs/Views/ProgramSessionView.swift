//
//  ProgramSessionView.swift
//  PowerJack
//
//  Runs the program's current workout. When it finishes (after its summary) or is skipped,
//  it returns to the program's detail page, where Start Workout begins the next one.
//

import OSLog
import SwiftData
import SwiftUI

struct ProgramSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProgramsRouter.self) private var router

    let program: Program

    /// Totals for the workout just finished, shown until the user taps Continue.
    @State private var summary: [MuscleSetCount] = []

    var body: some View {
        Group {
            if !summary.isEmpty {
                ExerciseSummaryView(setCounts: summary, onContinue: continueAfterSummary)
                    .transition(.push(from: .trailing))
            } else if let workout = program.nextWorkout {
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
        .animation(.easeInOut(duration: 0.35), value: summary.isEmpty)
    }

    private func finish(_ workout: Workout) {
        let setCounts = workout.completedSetsByMuscle
        program.finishWorkout(workout)
        save()
        if setCounts.isEmpty {
            leave()
        } else {
            summary = setCounts
        }
    }

    private func continueAfterSummary() {
        leave()
    }

    private func skip(_ workout: Workout) {
        program.skipWorkout(workout)
        save()
        leave()
    }

    /// Back to the program's detail page, or the list once the program is complete.
    private func leave() {
        if program.nextWorkout == nil {
            router.popToRoot()
        } else {
            router.showDetailOnly(program)
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
