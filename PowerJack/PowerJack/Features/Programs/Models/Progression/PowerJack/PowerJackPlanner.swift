//
//  PowerJackPlanner.swift
//  PowerJack
//
//  Writes PowerJack weeks into SwiftData: reads the program's logs into `PowerJackEngine` and
//  applies the plan it returns. Loads are stored in tenths of a pound.
//

import Foundation
import OSLog

enum PowerJackPlanner: WeekPlanner {
    /// Week 1 is copied from the template with 2 sets each. The engine replaces its sets.
    static func setUpFirstWeek(_ week: ProgramWeek, in program: Program) {
        let exercises = week.workouts.map { $0.workoutExercises.compactMap(\.exercise) }
        let plan = PowerJackEngine.firstWeek(
            exercises.map { $0.map { Self.exercise($0) } },
            warmupsDisabled: week.workouts.map { $0.workoutExercises.map(\.warmupsDisabled) },
            context: context(for: program, exercises: exercises.flatMap { $0 })
        )
        apply(plan, to: week)
    }

    /// Builds the empty `week` from every week before it.
    static func build(_ week: ProgramWeek, in program: Program) {
        let weeks = program.programWeeks
        guard week.workouts.isEmpty,
              let index = weeks.firstIndex(where: { $0 === week }),
              index > 0
        else {
            Logger.program.warning("Can only build an empty ProgramWeek that follows another week.")
            return
        }
        let closed = Array(weeks[..<index])
        let source = closed[index - 1]
        let exercises = source.workouts.map { $0.workoutExercises.compactMap(\.exercise) }
        let logs = weekLogs(closed, programWeeks: program.programLengthWeeks)
        guard let plan = PowerJackEngine.nextWeek(
            after: logs,
            context: context(for: program, exercises: exercises.flatMap { $0 })
        ) else { return }

        for (workoutIndex, workoutExercises) in exercises.enumerated() {
            guard let workout = week.addWorkout() else { continue }
            for (entryIndex, exercise) in workoutExercises.enumerated() {
                guard let workoutExercise = workout.addWorkoutExercise(exercise: exercise) else { continue }
                workoutExercise.inheritWarmupsDisabled(from: source.workouts[workoutIndex].workoutExercises[entryIndex])
            }
        }
        apply(plan, to: week)
        Logger.program.info("Built PowerJack week \(index + 1): \(plan.header.type.rawValue), block \(plan.header.blockNumber)")
    }

    // MARK: Writing the plan

    private static func apply(_ plan: PowerJackWeekPlan, to week: ProgramWeek) {
        week.setBlock(kind: plan.header.type == .deload ? .deload : .build, blockWeek: plan.header.blockWeek)
        for (workout, entries) in zip(week.workouts, plan.workouts) {
            for (workoutExercise, entry) in zip(workout.workoutExercises, entries) {
                workoutExercise.replacePlannedWarmups(entry.warmups.map { tenths($0) })
                workoutExercise.replacePlannedWorkingSets(entry.sets.map { tenths($0) })
                workoutExercise.setProgression(
                    // A deload aims at reps left on every set (R6.3).
                    rirTarget: plan.header.type == .deload ? PowerJackRules.deloadRIR : entry.target,
                    code: entry.reasons.last?.rawValue,
                    note: note(for: entry, in: plan.header)
                )
                workoutExercise.setPowerJackPlan(entry)
                if let pain = entry.checkInPain {
                    workoutExercise.requireCheckIn(sourcePain: pain)
                }
            }
        }
    }

    private static func tenths(_ set: PowerJackSetPlan) -> (reps: Int?, weightTenthsPounds: Int?) {
        (set.reps, set.load.map { Int(($0 * 10).rounded()) })
    }

    /// The line under the aim on the exercise screen. The aim itself covers deloads and rep-outs.
    private static func note(for entry: PowerJackEntryPlan, in header: PowerJackWeekPlanHeader) -> String? {
        if header.type == .deload { return "Deload week: don't add reps." }
        let topSet = entry.topSets > 0 ? "Set 1 is your heavy top set." : nil
        if entry.calibrating, entry.sets.first?.load == nil {
            return [topSet, "Pick weights that leave about 3 reps."].compactMap { $0 }.joined(separator: " ")
        }
        return topSet
    }

    // MARK: Reading the logs

    private static func context(for program: Program, exercises: [Exercise]) -> PowerJackContext {
        let byID = Dictionary(exercises.map { (AnyHashable(ObjectIdentifier($0)), $0) }, uniquingKeysWith: { first, _ in first })
        var cache: [AnyHashable: [PowerJackExposure]] = [:]
        return PowerJackContext(
            programWeeks: program.programLengthWeeks,
            focusMuscles: Set(program.templateMuscleFocus),
            history: { id in
                if let cached = cache[id] { return cached }
                let exposures = (byID[id]?.workoutExercisesValue ?? [])
                    .compactMap { Self.exposure($0) }
                    .sorted { $0.date < $1.date }
                cache[id] = exposures
                return exposures
            }
        )
    }

    static func exercise(_ exercise: Exercise) -> PowerJackExercise {
        let traits = PowerJackExercise.traits(
            catalogID: exercise.catalogID,
            primary: exercise.primaryMuscleFocus,
            fatigue: exercise.fatigueLevel
        )
        return PowerJackExercise(
            id: AnyHashable(ObjectIdentifier(exercise)),
            pattern: traits.0,
            multiJoint: traits.1,
            repsOnly: exercise.repsOnly,
            isBarbell: exercise.exerciseEquipment == .barbell,
            fatigue: exercise.fatigueLevel,
            primary: exercise.primaryMuscleFocus,
            secondaries: exercise.secondaryMuscles
        )
    }

    private static func exposure(_ workoutExercise: WorkoutExercise) -> PowerJackExposure? {
        guard let entry = entry(workoutExercise), let date = entry.lastCompletedAt else { return nil }
        let week = workoutExercise.workoutValue?.programWeekValue
        let isPowerJack = week?.programValue?.templateType == .powerJack
        return PowerJackExposure(
            date: date,
            entry: entry,
            weekType: isPowerJack ? (week?.weekKind == .deload ? .deload : .build) : nil,
            tag: workoutExercise.powerJackTag
        )
    }

    private static func entry(_ workoutExercise: WorkoutExercise) -> PowerJackEntryLog? {
        guard let exercise = workoutExercise.exercise else { return nil }
        let feedback = workoutExercise.feedback
        return PowerJackEntryLog(
            exercise: Self.exercise(exercise),
            sets: workoutExercise.workingSets.map { set in
                PowerJackSetLog(
                    plannedReps: set.repsPlanned,
                    plannedLoad: set.weightInPoundsPlanned,
                    reps: set.reps,
                    load: set.weightInPounds,
                    isComplete: set.status == .complete,
                    isSkipped: set.status == .skipped,
                    completedAt: set.completedAt
                )
            },
            topSets: workoutExercise.topSets,
            target: workoutExercise.rirTarget,
            loadTarget: workoutExercise.powerJackLoadTargetValue,
            topLoadTarget: workoutExercise.powerJackTopLoadTargetValue,
            calibrating: workoutExercise.calibrating,
            rir: feedback?.repsInReserve?.rawValue,
            topRIR: workoutExercise.topSetRepsInReserve?.rawValue,
            legacyEffort: feedback?.repsInReserve == nil ? feedback?.levelOfEffort : nil,
            pain: feedback?.levelOfPain,
            warmupsDisabled: workoutExercise.warmupsDisabled
        )
    }

    /// Each closed week with its block number, block week and target column replayed (R5.1).
    static func weekLogs(_ weeks: [ProgramWeek], programWeeks: Int) -> [PowerJackWeekLog] {
        var logs = weeks.map { week in
            PowerJackWeekLog(
                type: week.weekKind == .deload ? .deload : .build,
                workouts: week.workouts.map { workout in
                    PowerJackWorkoutLog(
                        entries: workout.workoutExercises.compactMap { entry($0) },
                        skipped: workout.status == .skipped && workout.completedWorkingSets == 0
                    )
                }
            )
        }
        let replayed = PowerJackCalendar.replay(logs, programWeeks: programWeeks)
        for index in logs.indices {
            (logs[index].blockNumber, logs[index].blockWeek, logs[index].column) = replayed[index]
        }
        return logs
    }
}
