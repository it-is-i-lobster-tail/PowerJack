//
//  ProgramLayoutDraft.swift
//  PowerJack
//
//  The exercises on each day of a running program, edited in the template builder.
//  A day not started yet this week, and the day in progress, change now. In the day in progress, an exercise
//  with anything logged stays. A day already done or skipped keeps this week as it was and changes from
//  next week. Later weeks are built from the week before, so they follow.
//

import Foundation

struct ProgramLayoutDraft {
    /// The days, in the shape the template builder edits.
    var days: TemplateProgramDraft
    /// Why a day's edit works the way it does: now for the day in progress, next week for a day already done.
    let dayNotes: [Int: String]
    /// Days done or skipped in the program's last week. With no next week, there's nothing left to change.
    let lockedDays: [Int: LockedDay]

    /// This week's workout for each day.
    private let workouts: [Workout]
    /// The workout exercise each exercise draft came from. New drafts have none until they're applied.
    private var sources: [UUID: WorkoutExercise] = [:]

    init(program: Program) {
        let week = program.nextWorkout.flatMap(program.programWeek(containing:))
        let isLastWeek = week?.order == program.programLengthWeeks - 1
        workouts = week?.workouts ?? []
        days = TemplateProgramDraft(templateType: program.templateType)
        days.workoutsPerWeek = workouts.count

        var dayNotes: [Int: String] = [:]
        var lockedDays: [Int: LockedDay] = [:]
        for (index, workout) in workouts.enumerated() {
            switch workout.status {
            case .planned, .active:
                for workoutExercise in workout.workoutExercises {
                    guard let exercise = workoutExercise.exercise,
                          let draft = days.templateWorkoutDraftsValue[index].addTemplateExerciseDraft(
                              exercise: exercise,
                              supersetID: workoutExercise.supersetID
                          )
                    else { continue }
                    sources[draft.id] = workoutExercise
                }
                if workout.status == .active {
                    dayNotes[index] = "Day \(index + 1) is in progress. Changes start now, and logged exercises stay."
                }
            default:
                if isLastWeek {
                    lockedDays[index] = LockedDay(title: Self.status(of: workout, day: index + 1))
                } else {
                    for entry in Self.nextWeekLayout(of: workout) {
                        days.templateWorkoutDraftsValue[index].addTemplateExerciseDraft(
                            exercise: entry.exercise,
                            supersetID: entry.supersetID
                        )
                    }
                    dayNotes[index] = "\(Self.status(of: workout, day: index + 1)). Changes start next week."
                }
            }
        }
        self.dayNotes = dayNotes
        self.lockedDays = lockedDays
        if !lockedDays.isEmpty {
            TraceLog.record(.workout, "Edit Days: days \(lockedDays.keys.sorted().map { String($0 + 1) }.joined(separator: ", ")) locked")
        }
    }

    /// Exercises in the day in progress with something logged. They can't be removed.
    var loggedExercises: Set<UUID> {
        // Only drafts still shown: a removed one's exercise may be deleted.
        let shown = days.templateWorkoutDraftsValue.flatMap(\.templateExerciseDrafts)
        return Set(shown.filter { sources[$0.id]?.hasLoggedWork == true }.map(\.id))
    }

    /// Writes each day's exercises: to this week's workout when it hasn't started or is in progress,
    /// or else to next week's.
    mutating func apply() {
        for (index, workout) in workouts.enumerated() where lockedDays[index] == nil {
            let drafts = days.templateWorkoutDraftsValue[index].templateExerciseDrafts
            // A workout can't run empty, so a day keeps its exercises until it has another.
            // Logged exercises always stay, so an edit that leaves only those is fine.
            guard !drafts.isEmpty || workout.workoutExercises.contains(where: \.hasLoggedWork) else { continue }
            guard workout.status == .planned || workout.status == .active else {
                applyNextWeek(drafts, to: workout)
                continue
            }
            let before = Self.layout(of: workout)
            let applied = workout.applyLayout(drafts.map { (sources[$0.id], $0.exercise, $0.supersetID) })
            if !Self.same(before, Self.layout(of: workout)) {
                TraceLog.record(.workout, "Edit Days: day \(index + 1) changes now: \(workout.traceLayout)")
            }
            // A day changed in progress follows this week's edit, not one saved before it started.
            if workout.nextWeekLayout != nil, !Self.same(before, Self.layout(of: workout)) {
                workout.clearNextWeekLayout()
            }
            if applied.count == drafts.count {
                for (draft, workoutExercise) in zip(drafts, applied) {
                    sources[draft.id] = workoutExercise
                }
            } else {
                // A logged exercise was put back, so the day shows what the workout has.
                reload(day: index, from: applied)
            }
        }
    }

    private mutating func reload(day index: Int, from workoutExercises: [WorkoutExercise]) {
        var day = days.templateWorkoutDraftsValue[index]
        for draft in day.templateExerciseDrafts {
            sources[draft.id] = nil
        }
        day.removeTemplateExercises(at: IndexSet(day.templateExerciseDrafts.indices))
        for workoutExercise in workoutExercises {
            guard let exercise = workoutExercise.exercise,
                  let draft = day.addTemplateExerciseDraft(exercise: exercise, supersetID: workoutExercise.supersetID)
            else { continue }
            sources[draft.id] = workoutExercise
        }
        days.templateWorkoutDraftsValue[index] = day
    }

    /// Saves a started day's edit for next week, only when it differs from what's saved.
    private func applyNextWeek(_ drafts: [TemplateExerciseDraft], to workout: Workout) {
        let layout = drafts.map { (exercise: $0.exercise, supersetID: $0.supersetID) }
        if Self.same(layout, Self.layout(of: workout)) {
            if workout.nextWeekLayout != nil {
                workout.clearNextWeekLayout()
            }
        } else if !Self.same(layout, Self.nextWeekLayout(of: workout)) {
            workout.setNextWeekLayout(layout)
        }
    }

    /// The exercises a started day will have next week: its saved edit, or else this week's.
    private static func nextWeekLayout(of workout: Workout) -> [(exercise: Exercise, supersetID: UUID?)] {
        if let rows = workout.nextWeekLayout {
            return rows.compactMap { row in row.exercise.map { (exercise: $0, supersetID: row.supersetID) } }
        }
        return layout(of: workout)
    }

    /// The exercises a day has this week.
    private static func layout(of workout: Workout) -> [(exercise: Exercise, supersetID: UUID?)] {
        workout.workoutExercises.compactMap { workoutExercise in
            workoutExercise.exercise.map { (exercise: $0, supersetID: workoutExercise.supersetID) }
        }
    }

    private static func same(
        _ lhs: [(exercise: Exercise, supersetID: UUID?)],
        _ rhs: [(exercise: Exercise, supersetID: UUID?)]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { pair in
            pair.0.exercise === pair.1.exercise && pair.0.supersetID == pair.1.supersetID
        }
    }

    private static func status(of workout: Workout, day: Int) -> String {
        switch workout.status {
        case .skipped: "Day \(day) was skipped this week"
        default: "Day \(day) is done for this week"
        }
    }
}
