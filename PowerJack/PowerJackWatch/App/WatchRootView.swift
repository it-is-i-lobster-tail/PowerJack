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
    @State private var previewsExercises = false

    /// The workout on screen. Syncing can swap the watch's copy of it for the iPhone's own,
    /// which is then found by its sync ID.
    private var shownWorkout: Binding<Workout?> {
        Binding {
            guard let openedWorkout else { return nil }
            if openedWorkout.modelContext != nil, !openedWorkout.isDeleted {
                return openedWorkout.status == .active ? openedWorkout : nil
            }
            return openedWorkoutID.flatMap { id in
                program.programWeeks.flatMap(\.workouts).first { $0.syncID == id && $0.status == .active }
            }
        } set: {
            openedWorkout = $0
            openedWorkoutID = $0?.syncID
        }
    }

    var body: some View {
        Group {
            if let workout = program.nextWorkout {
                VStack(spacing: 4) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(program.activityTitle(for: workout))
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .accessibilityAddTraits(.isHeader)

                            Text(program.templateName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            let exercises = workout.workoutExercises
                            if !workout.allExercisesFinished,
                               exercises.indices.contains(workout.currentExerciseIndex),
                               let exercise = exercises[workout.currentExerciseIndex].shownExercise {
                                Text(exercise.exerciseName)
                                    .font(.headline)
                                    .accessibilityLabel("Next exercise, \(exercise.exerciseName)")
                            }
                            if let device = workout.inProgressElsewhere {
                                Text("In progress on \(device)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                previewsExercises = true
                            } label: {
                                HStack {
                                    Text("View exercises")
                                    Spacer()
                                    Text("\(exercises.count)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.forward")
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: 32)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .font(.footnote)
                            .accessibilityLabel("View \(exercises.count) exercises")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollEdgeEffectHidden(true, for: .top)
                    .padding(.top, -8)

                    Button {
                        start(workout)
                    } label: {
                        Text(workout.status == .active ? "Resume" : "Start Workout")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .sheet(isPresented: $previewsExercises) {
                    NavigationStack {
                        List(workout.workoutExercises) { exercise in
                            WatchExerciseProgressRow(exercise: exercise)
                        }
                        .navigationTitle("Exercises")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close", systemImage: "xmark") { previewsExercises = false }
                            }
                        }
                    }
                }
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
        previewsExercises = false
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
