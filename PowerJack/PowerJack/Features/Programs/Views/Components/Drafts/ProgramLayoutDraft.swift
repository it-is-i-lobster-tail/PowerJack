//
//  ProgramLayoutDraft.swift
//  PowerJack
//
//  The exercises on each day of a running program, edited in the template builder.
//  Only days not yet started this week change. Later weeks are built from this one, so they follow.
//

import Foundation

struct ProgramLayoutDraft {
    /// The days, in the shape the template builder edits.
    var days: TemplateProgramDraft
    /// Days that can't change this week, with why.
    let lockedDays: [Int: LockedDay]

    /// This week's workout for each day.
    private let workouts: [Workout]
    /// The workout exercise each exercise draft came from. New drafts have none until they're applied.
    private var sources: [UUID: WorkoutExercise] = [:]

    init(program: Program) {
        let week = program.nextWorkout.flatMap(program.programWeek(containing:))
        workouts = week?.workouts ?? []
        days = TemplateProgramDraft(templateType: program.templateType)
        days.workoutsPerWeek = workouts.count

        var lockedDays: [Int: LockedDay] = [:]
        for (index, workout) in workouts.enumerated() {
            guard workout.status == .planned else {
                lockedDays[index] = Self.lockedDay(workout, isLastWeek: week?.order == program.programLengthWeeks - 1)
                continue
            }
            for workoutExercise in workout.workoutExercises {
                guard let exercise = workoutExercise.exercise,
                      let draft = days.templateWorkoutDraftsValue[index].addTemplateExerciseDraft(
                          exercise: exercise,
                          supersetID: workoutExercise.supersetID
                      )
                else { continue }
                sources[draft.id] = workoutExercise
            }
        }
        self.lockedDays = lockedDays
    }

    /// Writes each open day's exercises to its workout.
    mutating func apply() {
        for (index, workout) in workouts.enumerated() where lockedDays[index] == nil {
            let drafts = days.templateWorkoutDraftsValue[index].templateExerciseDrafts
            let applied = workout.applyLayout(drafts.map { (sources[$0.id], $0.exercise, $0.supersetID) })
            for (draft, workoutExercise) in zip(drafts, applied) {
                sources[draft.id] = workoutExercise
            }
        }
    }

    private static func lockedDay(_ workout: Workout, isLastWeek: Bool) -> LockedDay {
        let state = workout.status == .active ? "in progress" : "done for this week"
        return LockedDay(
            title: "Day \(workout.order + 1) is \(state)",
            detail: isLastWeek ? nil : "You can change it once next week starts."
        )
    }
}
