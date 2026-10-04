//
//  ProgressionPlanner.swift
//  PowerJack
//
//  Builds a program week from the week before it, using `ProgressionEngine`.
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
        let olderWeeks = weeks[..<(weekIndex - 1)].reversed().prefix(2).map { $0 }
        let credits = muscleSetCredits(in: sourceWeek)
        let focusMuscles = Set(program.templateMuscleFocus)

        for sourceWorkout in sourceWeek.workouts {
            guard let workout = week.addWorkout() else { continue }

            for sourceExercise in sourceWorkout.workoutExercises {
                guard
                    let exercise = sourceExercise.exercise,
                    let workoutExercise = workout.addWorkoutExercise(exercise: exercise)
                else {
                    continue
                }

                let matches = olderWeeks.map {
                    matchingExercise(for: sourceExercise, in: sourceWorkout, week: $0)
                }
                let prescription = ProgressionEngine.nextPrescription(
                    ProgressionInput(
                        current: history(sourceExercise, programWeek: weekIndex),
                        previous: matches.first.flatMap { $0 }.map { history($0, programWeek: weekIndex - 1) },
                        twoWeeksAgo: matches.dropFirst().first.flatMap { $0 }.map {
                            history($0, programWeek: weekIndex - 2)
                        },
                        exercise: info(exercise),
                        focusMuscles: focusMuscles,
                        programLengthWeeks: program.programLengthWeeks,
                        currentWeekMuscleSetCredits: credits
                    )
                )

                for set in prescription.sets.prefix(WorkoutExercise.maxSets) {
                    workoutExercise.addPlannedSet(
                        plannedReps: set.plannedReps,
                        plannedWeightTenthsPounds: set.plannedWeightTenthsPounds
                    )
                }
                if let sourcePain = prescription.checkInSourcePain {
                    workoutExercise.requireCheckIn(sourcePain: sourcePain)
                }
            }
        }
        Logger.program.info("Built ProgramWeek \(weekIndex + 1) from week \(weekIndex)")
    }

    /// Completed set credits per muscle for one week (primary 1, secondary 0.5).
    static func muscleSetCredits(in week: ProgramWeek) -> [Muscle: Double] {
        var credits: [Muscle: Double] = [:]
        for workout in week.workouts {
            for workoutExercise in workout.workoutExercises {
                let completed = Double(workoutExercise.getCountCompletedSets())
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

    static func history(_ workoutExercise: WorkoutExercise, programWeek: Int) -> ProgressionHistory {
        ProgressionHistory(
            programWeek: programWeek,
            status: workoutExercise.status,
            pain: workoutExercise.feedback?.levelOfPain,
            effort: workoutExercise.feedback?.levelOfEffort,
            checkIn: workoutExercise.checkIn,
            checkInSourcePain: workoutExercise.checkInSourcePain,
            sets: workoutExercise.workoutSets.map {
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
