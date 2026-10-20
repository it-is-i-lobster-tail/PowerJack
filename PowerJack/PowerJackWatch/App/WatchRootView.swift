//
//  WatchRootView.swift
//  PowerJackWatch
//
//  The program running on the iPhone and its next workout, ready to start or resume.
//

import SwiftData
import SwiftUI

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @Query private var programs: [Program]

    var body: some View {
        NavigationStack {
            if !store.syncsWithICloud {
                ContentUnavailableView(
                    "iCloud Backup is off",
                    systemImage: "icloud.slash",
                    description: Text("Turn it on in PowerJack's settings on your iPhone to work out from your watch.")
                )
            } else if let program = programs.active {
                ProgramHomeView(program: program)
            } else {
                ContentUnavailableView(
                    "No program running",
                    systemImage: "dumbbell",
                    description: Text("Start a program on your iPhone.")
                )
            }
        }
    }
}

private struct ProgramHomeView: View {
    @Environment(\.modelContext) private var modelContext

    let program: Program

    @State private var shownWorkout: Workout?

    var body: some View {
        Group {
            if let workout = program.nextWorkout {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(workout.status == .active ? "Resume" : "Start Workout") {
                            start(workout)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 4)

                        Text(program.templateName)
                            .font(.headline)

                        ForEach(workout.workoutExercises) { workoutExercise in
                            Text(workoutExercise.exercise?.exerciseName ?? "")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(program.activityTitle(for: workout))
            } else {
                ContentUnavailableView("Program complete", systemImage: "checkmark.seal")
            }
        }
        .navigationDestination(item: $shownWorkout) { workout in
            WatchWorkoutView(program: program, workout: workout) {
                shownWorkout = nil
            }
        }
    }

    /// Starts the workout the same way the iPhone does, then opens it.
    private func start(_ workout: Workout) {
        if workout.status == .planned && workout.locked {
            program.prepareToStart(workout)
            workout.startAndCascade()
            try? modelContext.save()
        }
        shownWorkout = workout
    }
}
