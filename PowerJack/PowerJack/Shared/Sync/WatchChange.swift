//
//  WatchChange.swift
//  PowerJack
//
//  Something done on the watch, sent straight to the iPhone, which referees when they're together.
//  The watch keeps each change until the iPhone says it has it (see `WatchReplica`).
//

import Foundation

struct WatchChange: Codable, Equatable, Identifiable {
    enum Action: Codable, Equatable {
        case startWorkout
        case logSet(SetLog)
        case skipWarmups
        case rateExercise(FeedbackState, topSetRepsInReserve: Int?)
        case resolveCheckIn(String)
        case finishWorkout
    }

    /// Counts up on each watch install, so the iPhone applies each change once and in order.
    var id: Int
    var install: UUID
    var date: Date
    /// Whether the watch could reach the iPhone when it made the change.
    var together: Bool
    var row: RowPath
    var action: Action
}

/// Where a row sits: its sync IDs, and its place, so the iPhone still finds it in a week the two
/// devices planned apart.
struct RowPath: Codable, Equatable {
    var program: UUID?
    var week: Int
    var workout: UUID?
    var workoutOrder: Int
    var exercise: UUID?
    var exerciseOrder: Int?
    var exerciseKey: String?
    var set: UUID?
    var setOrder: Int?
    var setType: String?
}

extension RowPath {
    init?(_ workout: Workout) {
        guard let week = workout.programWeekValue else { return nil }
        self.init(
            program: week.programValue?.syncID,
            week: week.order,
            workout: workout.syncID,
            workoutOrder: workout.order
        )
    }

    init?(_ workoutExercise: WorkoutExercise) {
        guard let workout = workoutExercise.workoutValue, var path = RowPath(workout) else { return nil }
        path.exercise = workoutExercise.syncID
        path.exerciseOrder = workoutExercise.order
        path.exerciseKey = workoutExercise.exercise?.syncKey
        self = path
    }

    init?(_ workoutSet: WorkoutSet) {
        guard let workoutExercise = workoutSet.workoutExerciseValue, var path = RowPath(workoutExercise) else { return nil }
        path.set = workoutSet.syncID
        path.setOrder = workoutSet.order
        path.setType = workoutSet.setType.rawValue
        self = path
    }
}

extension Program {
    /// The workout `path` names: by sync ID, else the day in the same place.
    func workout(at path: RowPath) -> Workout? {
        let workouts = programWeeks.flatMap(\.workouts)
        if let id = path.workout, let workout = workouts.first(where: { $0.syncID == id }) { return workout }
        return programWeeks.first { $0.order == path.week }?.workouts.first { $0.order == path.workoutOrder }
    }

    /// The exercise `path` names: by sync ID, else the same exercise in the same place.
    func workoutExercise(at path: RowPath) -> WorkoutExercise? {
        guard let workout = workout(at: path) else { return nil }
        let exercises = workout.workoutExercises
        if let id = path.exercise, let workoutExercise = exercises.first(where: { $0.syncID == id }) { return workoutExercise }
        return exercises.first { $0.order == path.exerciseOrder && $0.exercise?.syncKey == path.exerciseKey }
    }

    /// The set `path` names: by sync ID, else the set of the same kind in the same place.
    func workoutSet(at path: RowPath) -> WorkoutSet? {
        guard let workoutExercise = workoutExercise(at: path) else { return nil }
        let sets = workoutExercise.workoutSets
        if let id = path.set, let workoutSet = sets.first(where: { $0.syncID == id }) { return workoutSet }
        return sets.first { $0.order == path.setOrder && $0.setType.rawValue == path.setType }
    }
}
