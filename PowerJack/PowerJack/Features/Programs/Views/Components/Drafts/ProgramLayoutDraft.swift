//
//  ProgramLayoutDraft.swift
//  PowerJack
//
//  The exercises on each day of a running program, edited in the template builder.
//  A day not started yet this week changes now. A day already started or done keeps this week as it was
//  and changes from next week. Later weeks are built from the week before, so they follow.
//

import Foundation

struct ProgramLayoutDraft {
    /// The days, in the shape the template builder edits.
    var days: TemplateProgramDraft
    /// Days already started this week, so their edits start next week, with a note that says so.
    let dayNotes: [Int: String]
    /// Days started in the program's last week. With no next week, there's nothing left to change.
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
            if workout.status == .planned {
                for workoutExercise in workout.workoutExercises {
                    guard let exercise = workoutExercise.exercise,
                          let draft = days.templateWorkoutDraftsValue[index].addTemplateExerciseDraft(
                              exercise: exercise,
                              supersetID: workoutExercise.supersetID
                          )
                    else { continue }
                    sources[draft.id] = workoutExercise
                }
            } else if isLastWeek {
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
        self.dayNotes = dayNotes
        self.lockedDays = lockedDays
    }

    /// Writes each day's exercises: to this week's workout when it hasn't started, or else to next week's.
    mutating func apply() {
        for (index, workout) in workouts.enumerated() where lockedDays[index] == nil {
            let drafts = days.templateWorkoutDraftsValue[index].templateExerciseDrafts
            guard workout.status == .planned else {
                applyNextWeek(drafts, to: workout)
                continue
            }
            let applied = workout.applyLayout(drafts.map { (sources[$0.id], $0.exercise, $0.supersetID) })
            for (draft, workoutExercise) in zip(drafts, applied) {
                sources[draft.id] = workoutExercise
            }
        }
    }

    /// Saves a started day's edit for next week, only when it differs from what's saved.
    private func applyNextWeek(_ drafts: [TemplateExerciseDraft], to workout: Workout) {
        let layout = drafts.map { (exercise: $0.exercise, supersetID: $0.supersetID) }
        let thisWeek = workout.workoutExercises.compactMap { workoutExercise in
            workoutExercise.exercise.map { (exercise: $0, supersetID: workoutExercise.supersetID) }
        }
        if Self.same(layout, thisWeek) {
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
        return workout.workoutExercises.compactMap { workoutExercise in
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
        case .active: "Day \(day) is in progress"
        case .skipped: "Day \(day) was skipped this week"
        default: "Day \(day) is done for this week"
        }
    }
}
