import Foundation
import SwiftData

struct ProgramExerciseHistory: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let supportsLoadEstimate: Bool
    var sets: [LoggedSet] = []

    var sessions: [Session] = []

    struct Session: Identifiable {
        let id: PersistentIdentifier
        let programName: String
        let week: Int
        let day: Int
        let date: Date?
        let firstSet: Int
        var lastSet: Int
        var ratings: [RepsInReserve?]
    }

    struct LoggedSet: Identifiable {
        let id: Int
        let sessionIndex: Int
        let targetReps: Int?
        let reps: Int?
        let targetLoad: Int?
        let load: Int?
        let repsInReserve: RepsInReserve?

        init(id: Int, sessionIndex: Int, targetReps: Int?, reps: Int?,
             targetLoad: Int?, load: Int?, repsInReserve: RepsInReserve? = nil) {
            self.id = id
            self.sessionIndex = sessionIndex
            self.targetReps = targetReps
            self.reps = reps
            self.targetLoad = targetLoad
            self.load = load
            self.repsInReserve = repsInReserve
        }
    }

    static func exercises(in programs: [Program], range: VolumeRange?, dateFilter: WorkoutDateFilter? = nil,
                          primaryMuscles: Set<Muscle> = [], search: ExerciseChartSearch? = nil,
                          now: Date = .now, calendar: Calendar = .current) -> [Self] {
        let isCurrentProgram = dateFilter == nil && range == .currentProgram
        let selected = isCurrentProgram ? programs.active.map { [$0] } ?? [] : programs
        let start = dateFilter == nil ? range?.start(before: now, calendar: calendar) : nil
        var workouts: [(workout: Workout, date: Date?, week: Int, programName: String)] = []
        for program in selected {
            for week in program.programWeeks {
                for workout in week.workouts {
                    if !isCurrentProgram && workout.status == .planned { continue }
                    // Use the same completion date as the volume log. Live sessions have only a start.
                    let date = workout.endedAt ?? workout.startedAt
                    if let start, date.map({ $0 < start }) ?? true { continue }
                    if let date, date > now { continue }
                    if let dateFilter {
                        guard let date, dateFilter.includes(date, calendar: calendar) else { continue }
                    }
                    workouts.append((workout, date, week.order + 1, program.templateName))
                }
            }
        }
        workouts.sort { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        var histories: [PersistentIdentifier: Self] = [:]
        for entry in workouts {
            for slot in entry.workout.workoutExercises {
                guard let exercise = slot.shownExercise else { continue }
                if let search, search.ranks[exercise.persistentModelID] == nil { continue }
                guard primaryMuscles.isEmpty || primaryMuscles.contains(exercise.primaryMuscleFocus) else { continue }
                let completed = slot.workingSets.filter { $0.status == .complete }
                if completed.isEmpty && !isCurrentProgram { continue }
                let feedback = slot.feedback
                let ratedSet = feedback?.completedSets ?? completed.count
                histories[exercise.persistentModelID, default: Self(
                    id: exercise.persistentModelID, name: exercise.exerciseName,
                    supportsLoadEstimate: !exercise.repsOnly && !exercise.addsToBodyweight
                )]
                    .append(completed, rating: feedback?.repsInReserve, ratedSet: ratedSet, from: entry.workout,
                            week: entry.week, programName: entry.programName, date: entry.date)
            }
        }
        return histories.values.sorted { lhs, rhs in
            if let search, let left = search.ranks[lhs.id], let right = search.ranks[rhs.id], left != right {
                return left < right
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private mutating func append(_ completed: [WorkoutSet], rating: RepsInReserve?, ratedSet: Int, from workout: Workout,
                                 week: Int, programName: String, date: Date?) {
        guard !completed.isEmpty else { return }
        if sessions.last?.id != workout.persistentModelID {
            sessions.append(Session(id: workout.persistentModelID, programName: programName, week: week, day: workout.order + 1,
                                    date: date, firstSet: sets.count + 1,
                                    lastSet: sets.count + completed.count, ratings: []))
        }
        let index = sessions.count - 1
        for (offset, set) in completed.enumerated() {
            sets.append(LoggedSet(id: sets.count + 1, sessionIndex: index,
                                  targetReps: set.repsPlanned, reps: set.reps,
                                  targetLoad: set.weightTenthsPlannedPounds, load: set.weightTenthsPounds,
                                  repsInReserve: offset + 1 == ratedSet ? rating : nil))
        }
        sessions[index].lastSet = sets.count
        sessions[index].ratings.append(rating)
    }
}
