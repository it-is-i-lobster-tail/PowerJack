//
//  WatchWorkoutView.swift
//  PowerJackWatch
//
//  One page per exercise, then the finish page. Scrolling the pages moves between exercises;
//  logging an exercise's last set asks for its feedback, then moves on to the next one.
//

import SwiftData
import SwiftUI

/// Sheets the workout presents for the exercise on screen.
private enum WorkoutSheet: Identifiable, Hashable {
    case feedback(WorkoutExercise)
    case checkIn(WorkoutExercise)

    var id: Self { self }
}

struct WatchWorkoutView: View {
    @Environment(\.modelContext) private var modelContext

    let program: Program
    @Bindable var workout: Workout
    let onFinished: () -> Void

    @State private var page: Int
    @State private var sheet: WorkoutSheet?

    init(program: Program, workout: Workout, onFinished: @escaping () -> Void) {
        self.program = program
        self.workout = workout
        self.onFinished = onFinished
        _page = State(initialValue: Self.nextPage(in: workout))
    }

    /// The first exercise still waiting, or the finish page once every exercise is done.
    private static func nextPage(in workout: Workout) -> Int {
        workout.allExercisesFinished ? workout.workoutExercises.count : workout.currentExerciseIndex
    }

    private var exercises: [WorkoutExercise] { workout.workoutExercises }

    private var exerciseOnScreen: WorkoutExercise? {
        exercises.indices.contains(page) ? exercises[page] : nil
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, workoutExercise in
                WatchExerciseView(workoutExercise: workoutExercise, onSetLogged: { setLogged(on: workoutExercise) })
                    .tag(index)
            }

            WatchFinishView(workout: workout, onSelectExercise: { page = $0 }, onFinish: finish)
                .tag(exercises.count)
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle("Day \(workout.order + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .feedback(let workoutExercise):
                WatchFeedbackView(workoutExercise: workoutExercise) { finishedSheet() }
            case .checkIn(let workoutExercise):
                WatchCheckInView(workoutExercise: workoutExercise) { finishedSheet() }
            }
        }
        .onAppear(perform: presentSheetIfNeeded)
        .onChange(of: page) { presentSheetIfNeeded() }
        .task(id: workout.currentRest?.endsAt) {
            await RestAlert.schedule(for: workout.currentRest)
        }
    }

    private func setLogged(on workoutExercise: WorkoutExercise) {
        save()
        if workoutExercise.needsFeedback {
            sheet = .feedback(workoutExercise)
        } else if workoutExercise.isDone {
            advance()
        }
    }

    /// Feedback or a check-in waits on the exercise on screen, e.g. after relaunching mid-workout.
    private func presentSheetIfNeeded() {
        guard sheet == nil, let exerciseOnScreen else { return }
        if exerciseOnScreen.needsFeedback {
            sheet = .feedback(exerciseOnScreen)
        } else if exerciseOnScreen.checkInPending {
            sheet = .checkIn(exerciseOnScreen)
        }
    }

    private func finishedSheet() {
        save()
        sheet = nil
        if exerciseOnScreen?.isDone == true {
            advance()
        }
    }

    private func advance() {
        withAnimation {
            page = Self.nextPage(in: workout)
        }
    }

    /// Skips anything still unlogged, then moves the program on. Finishing a week plans the next one.
    private func finish() {
        workout.skipRemainingSets()
        program.finishWorkout(workout)
        save()
        Task { await RestAlert.schedule(for: nil) }
        onFinished()
    }

    private func save() {
        try? modelContext.save()
    }
}
