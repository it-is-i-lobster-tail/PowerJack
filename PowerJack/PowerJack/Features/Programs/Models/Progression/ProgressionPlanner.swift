//
//  ProgressionPlanner.swift
//  PowerJack
//
//  Builds a program week from the week before it, using its template type's progression rules.
//

import Foundation
import OSLog

enum ProgressionPlanner {
    /// Fills an empty `week` by copying the previous week's structure and progressing every exercise.
    static func build(_ week: ProgramWeek, in program: Program) {
        let weeks = program.programWeeks
        guard
            week.workouts.isEmpty,
            let weekIndex = weeks.firstIndex(where: { $0 === week }),
            weekIndex > 0
        else {
            Logger.program.warning("Can only build an empty ProgramWeek that follows another week.")
            return
        }

        let sourceWeek = weeks[weekIndex - 1]
        let credits = muscleSetCredits(in: sourceWeek)

        for sourceWorkout in sourceWeek.workouts {
            guard let workout = week.addWorkout() else { continue }

            for sourceExercise in sourceWorkout.workoutExercises {
                guard
                    let exercise = sourceExercise.exercise,
                    let workoutExercise = workout.addWorkoutExercise(exercise: exercise)
                else {
                    continue
                }
                // An exercise with warmups disabled on this day gets none (see `WorkoutExercise.canAddSet`).
                workoutExercise.inheritWarmupsDisabled(from: sourceExercise)
                workoutExercise.inheritSuperset(from: sourceExercise)
                plan(workoutExercise, from: sourceExercise, in: sourceWorkout, weekIndex: weekIndex, credits: credits, program: program)
            }
        }
        Logger.program.info("Built ProgramWeek \(weekIndex + 1) from week \(weekIndex)")
    }

    /// Week 1 is copied from the template, so there's no week before it to progress from.
    static func canReplan(_ week: ProgramWeek, in program: Program) -> Bool {
        week.order > 0
    }

    /// Plans each of `workouts` again from the same day of the week before, as `build` would now.
    /// Exercises that day didn't have keep their sets.
    static func replan(_ workouts: [Workout], of week: ProgramWeek, in program: Program) {
        let weeks = program.programWeeks
        guard let weekIndex = weeks.firstIndex(where: { $0 === week }), weekIndex > 0 else {
            Logger.program.warning("Can only replan a ProgramWeek that follows another week.")
            return
        }
        let sourceWeek = weeks[weekIndex - 1]
        let credits = muscleSetCredits(in: sourceWeek)
        // These rules don't use blocks, so a week the Build engine wrote drops its block.
        week.clearBlock()

        for workout in workouts {
            guard let sourceWorkout = sourceWeek.workouts.first(where: { $0.order == workout.order }) else { continue }
            for (workoutExercise, sourceExercise) in workout.slotPairs(with: sourceWorkout) {
                workoutExercise.clearPlannedProgression()
                plan(workoutExercise, from: sourceExercise, in: sourceWorkout, weekIndex: weekIndex, credits: credits, program: program)
            }
        }
        Logger.program.info("Replanned \(workouts.count) workouts of ProgramWeek \(weekIndex + 1)")
    }

    /// Writes the planned sets of `workoutExercise` from `sourceExercise`, the same slot the week before.
    private static func plan(
        _ workoutExercise: WorkoutExercise,
        from sourceExercise: WorkoutExercise,
        in sourceWorkout: Workout,
        weekIndex: Int,
        credits: [Muscle: Double],
        program: Program
    ) {
        guard let exercise = sourceExercise.exercise else { return }
        let weeks = program.programWeeks
        let olderWeeks = weeks[..<(weekIndex - 1)].reversed().prefix(2).map { $0 }
        let matches = olderWeeks.map {
            matchingExercise(for: sourceExercise, in: sourceWorkout, week: $0)
        }
        let prescription = program.templateType.progressionRules(
            ProgressionInput(
                current: history(sourceExercise, programWeek: weekIndex),
                previous: matches.first.flatMap { $0 }.map { history($0, programWeek: weekIndex - 1) },
                twoWeeksAgo: matches.dropFirst().first.flatMap { $0 }.map {
                    history($0, programWeek: weekIndex - 2)
                },
                exercise: info(exercise),
                focusMuscles: Set(program.templateMuscleFocus),
                programLengthWeeks: program.programLengthWeeks,
                currentWeekMuscleSetCredits: credits
            )
        )

        // Warmups repeat what was logged last week, including how many. They never progress.
        let sourceWarmups = sourceExercise.warmupSets
        let warmupCount = sourceWarmups.isEmpty ? WorkoutExercise.initialWarmupSets : sourceWarmups.count
        workoutExercise.replacePlannedWarmups((0..<warmupCount).map { index in
            let warmup = sourceWarmups.indices.contains(index) ? sourceWarmups[index] : nil
            return (
                reps: warmup.flatMap { $0.reps ?? $0.repsPlanned },
                weightTenthsPounds: warmup.flatMap { $0.weightTenthsPounds ?? $0.weightTenthsPlannedPounds }
            )
        })
        workoutExercise.replacePlannedWorkingSets(prescription.sets.prefix(WorkoutExercise.maxSets).map {
            (reps: $0.plannedReps, weightTenthsPounds: $0.plannedWeightTenthsPounds)
        })
        let checkInPain = prescription.checkInSourcePain ?? unresolvedCheckInPain(
            for: sourceExercise,
            in: sourceWorkout,
            earlierWeeks: weeks[..<(weekIndex - 1)].reversed()
        )
        if let sourcePain = checkInPain {
            workoutExercise.requireCheckIn(sourcePain: sourcePain)
        }
    }

    /// Completed working set credits per muscle for one week (primary 1, secondary 0.5).
    static func muscleSetCredits(in week: ProgramWeek) -> [Muscle: Double] {
        var credits: [Muscle: Double] = [:]
        for workout in week.workouts {
            for workoutExercise in workout.workoutExercises {
                let completed = Double(workoutExercise.completedWorkingSets)
                guard completed > 0, let exercise = workoutExercise.exercise else { continue }
                let perSet = ProgressionEngine.setCredits(
                    primary: exercise.primaryMuscleFocus,
                    secondary: exercise.secondaryMuscles
                )
                for (muscle, credit) in perSet {
                    credits[muscle, default: 0] += credit * completed
                }
            }
        }
        return credits
    }

    /// Only working sets count toward progression.
    static func history(_ workoutExercise: WorkoutExercise, programWeek: Int) -> ProgressionHistory {
        ProgressionHistory(
            programWeek: programWeek,
            status: workoutExercise.status,
            pain: workoutExercise.feedback?.levelOfPain,
            effort: workoutExercise.feedback?.levelOfEffort,
            checkIn: workoutExercise.checkIn,
            checkInSourcePain: workoutExercise.checkInSourcePain,
            sets: workoutExercise.workingSets.map {
                ProgressionSet(
                    plannedReps: $0.repsPlanned,
                    plannedWeightTenthsPounds: $0.weightTenthsPlannedPounds,
                    actualReps: $0.reps,
                    actualWeightTenthsPounds: $0.weightTenthsPounds,
                    status: $0.status
                )
            }
        )
    }

    static func info(_ exercise: Exercise) -> ProgressionExerciseInfo {
        ProgressionExerciseInfo(
            minReps: exercise.repRange.lowerBound,
            maxReps: exercise.repRange.upperBound,
            primaryMuscle: exercise.primaryMuscleFocus,
            secondaryMuscles: exercise.secondaryMuscles,
            repsOnly: exercise.repsOnly
        )
    }

    /// Severe pain from the last time this exercise was completed, when every run since was skipped.
    /// Skipping a workout must not erase a check-in.
    static func unresolvedCheckInPain(
        for sourceExercise: WorkoutExercise,
        in sourceWorkout: Workout,
        earlierWeeks: some Sequence<ProgramWeek>
    ) -> LevelOfPain? {
        var candidate = sourceExercise
        var olderWeeks = earlierWeeks.makeIterator()
        while candidate.status != .complete {
            guard
                let week = olderWeeks.next(),
                let older = matchingExercise(for: sourceExercise, in: sourceWorkout, week: week)
            else {
                return nil
            }
            candidate = older
        }
        guard
            candidate !== sourceExercise,
            let pain = candidate.feedback?.levelOfPain,
            pain.rawValue >= LevelOfPain.severe.rawValue
        else {
            return nil
        }
        return pain
    }

    /// The same exercise at the same workout and exercise position in an earlier week.
    private static func matchingExercise(
        for workoutExercise: WorkoutExercise,
        in workout: Workout,
        week: ProgramWeek
    ) -> WorkoutExercise? {
        guard
            let olderWorkout = week.workouts.first(where: { $0.order == workout.order }),
            let olderExercise = olderWorkout.workoutExercises.first(where: { $0.order == workoutExercise.order }),
            olderExercise.exercise === workoutExercise.exercise
        else {
            return nil
        }
        return olderExercise
    }
}
