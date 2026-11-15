//
//  WatchRootView.swift
//  PowerJackWatch
//
//  The program running on the iPhone and its next workout, ready to start or resume.
//

import SwiftData
import SwiftUI
import WidgetKit

struct WatchRootView: View {
    @Environment(WatchSync.self) private var sync
    @Query private var programs: [Program]

    var body: some View {
        NavigationStack {
            if let program = programs.active {
                ProgramHomeView(program: program)
            } else if sync.heardFromIPhone {
                ContentUnavailableView(
                    "No program running",
                    systemImage: "dumbbell",
                    description: Text("Start a program on your iPhone.")
                )
            } else {
                ContentUnavailableView {
                    Label("Waiting for iPhone", systemImage: "iphone")
                } description: {
                    Text("Keep your iPhone nearby to get your program.")
                } actions: {
                    Button("Try Again") { sync.push() }
                }
            }
        }
        // Tapping the iPhone's workout Live Activity in the Smart Stack opens the workout here.
        .onContinueUserActivity(NSUserActivityTypeLiveActivity) { _ in
            WorkoutLaunch.shared.opensActiveWorkout = true
        }
    }
}

private struct ProgramHomeView: View {
    @Environment(WatchSync.self) private var sync

    let program: Program

    @State private var openedWorkout: Workout?
    @State private var openedWorkoutID: UUID?

    /// The workout on screen. Syncing can swap the watch's copy of it for the iPhone's own,
    /// which is then found by its sync ID.
    private var shownWorkout: Binding<Workout?> {
        Binding {
            guard let openedWorkout else { return nil }
            if openedWorkout.modelContext != nil, !openedWorkout.isDeleted { return openedWorkout }
            return openedWorkoutID.flatMap { id in program.programWeeks.flatMap(\.workouts).first { $0.syncID == id } }
        } set: {
            openedWorkout = $0
            openedWorkoutID = $0?.syncID
        }
    }

    var body: some View {
        Group {
            if let workout = program.nextWorkout {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(workout.status == .active ? "Resume" : "Start Workout") {
                            start(workout)
                        }
                        .buttonStyle(.borderedProminent)

                        if let device = workout.inProgressElsewhere {
                            Text("In progress on \(device)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Text(program.templateName)
                            .font(.headline)
                            .padding(.top, 4)

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
        .onChange(of: WorkoutLaunch.shared.opensActiveWorkout, initial: true) { openActiveWorkoutIfAsked() }
        .onChange(of: program.nextWorkout?.status, initial: true) { openActiveWorkoutIfAsked() }
        .navigationDestination(item: shownWorkout) { workout in
            WatchWorkoutView(program: program, workout: workout) {
                shownWorkout.wrappedValue = nil
            }
            // A new copy of the workout starts the screen over, from where its sets say the lifter is.
            .id(workout.persistentModelID)
        }
    }

    /// Opens the workout in progress when the iPhone or its Live Activity asked for it,
    /// as soon as the watch has it from the iPhone.
    private func openActiveWorkoutIfAsked() {
        guard WorkoutLaunch.shared.opensActiveWorkout, let workout = program.nextWorkout, workout.status == .active else { return }
        WorkoutLaunch.shared.opensActiveWorkout = false
        if shownWorkout.wrappedValue == nil {
            shownWorkout.wrappedValue = workout
        }
    }

    /// Starts the workout the same way the iPhone does, then opens it.
    private func start(_ workout: Workout) {
        sync.perform { $0.start(workout, in: program) }
        shownWorkout.wrappedValue = workout
    }
}
