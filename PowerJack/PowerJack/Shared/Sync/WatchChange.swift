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
        /// Finish Workout skipped what's still unlogged, so partly logged exercises can be rated before it finishes.
        case skipRemainingSets
        /// Weight and reps dialed in on a set not logged yet. Nil leaves that value as it was.
        case enterSet(weightTenthsPounds: Int?, reps: Int?)
    }

    enum ExerciseEdit: Codable, Equatable {
        case addSet(SetType, id: UUID)
        case removeSet(SetType, id: UUID)
        case skip
        case joinSuperset(target: RowPath, id: UUID)
        case leaveSuperset(id: UUID)
        case reorderSuperset(id: UUID, members: [UUID], source: IndexSet, destination: Int)

        /// Apply against the current workout, protecting sets or groups changed on the phone.
        func apply(to exercise: WorkoutExercise, in workout: Workout, program: Program) -> Bool {
            guard workout.status == .active, !exercise.checkInPending else { return false }
            switch self {
            case .addSet(let type, let id):
                if exercise.workoutSets.contains(where: { $0.syncID == id }) { return true }
                guard let set = exercise.addSet(type: type) else { return false }
                set.syncIDValue = id
            case .removeSet(let type, let id):
                let sets = exercise.sets(ofType: type)
                guard sets.count > 1, sets.last?.syncID == id, exercise.canRemoveSet(type: type) else { return false }
                exercise.removeLastSet(type: type)
            case .skip:
                guard exercise.status == .active, !exercise.locked, !exercise.allSetsDone() else { return false }
                exercise.skipRemainingSets()
            case .joinSuperset(let row, let id):
                guard exercise.supersetPartners.isEmpty, !exercise.isDone,
                      let target = program.workoutExercise(at: row), target.workoutValue === workout,
                      let group = workout.supersetChoices(for: exercise).first(where: { $0.contains { $0 === target } })
                else { return false }
                workout.addToSuperset(exercise, with: group, newSupersetID: id)
            case .leaveSuperset(let id):
                guard exercise.supersetID == id, !exercise.supersetPartners.isEmpty else { return false }
                workout.removeFromSuperset(exercise)
            case .reorderSuperset(let id, let members, let source, let destination):
                guard exercise.supersetID == id, let group = workout.superset(id),
                      group.compactMap(\.syncID) == members
                else { return false }
                workout.moveExercises(inSuperset: id, from: source, to: destination)
            }
            return true
        }
    }

    /// Optional so older companions can still decode mixed batches containing ordinary set logs.
    var skippedWorkout: Bool? = nil
    var exerciseEdit: ExerciseEdit? = nil

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
