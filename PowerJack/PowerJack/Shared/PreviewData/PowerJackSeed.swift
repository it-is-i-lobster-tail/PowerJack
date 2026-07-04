//
//  PowerJackSeed.swift
//  PowerJack
//
//  Created by Codex on 7/2/26.
//

import SwiftData

struct PowerJackProgramSeedScenario {
    let container: ModelContainer
    let program: Program
    let weekOneWorkouts: [Workout]
}

enum PowerJackSeed {
    static let schema = Schema([
        Program.self,
        ProgramWeek.self,
        Workout.self,
        WorkoutExercise.self,
        WorkoutSet.self,
        Exercise.self,
        TemplateProgram.self,
        TemplateWorkout.self,
        TemplateExercise.self,
    ])

    static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create in-memory ModelContainer: \(error)")
        }
    }

    static func weekOneProgress() -> PowerJackProgramSeedScenario {
        let container = makeInMemoryContainer()

        let benchPress = Exercise(
            exerciseName: "Barbell Bench Press",
            exerciseEquipment: .Barbell,
            primaryMuscleFocus: .chest
        )
        let backSquat = Exercise(
            exerciseName: "Barbell Back Squat",
            exerciseEquipment: .Barbell,
            primaryMuscleFocus: .quads
        )
        let pullUp = Exercise(
            exerciseName: "Pull Up",
            exerciseEquipment: .Body,
            primaryMuscleFocus: .back
        )
        let latPulldown = Exercise(
            exerciseName: "Lat Pulldown",
            exerciseEquipment: .Cable,
            primaryMuscleFocus: .back
        )
        let lateralRaise = Exercise(
            exerciseName: "Cable Lateral Raise",
            exerciseEquipment: .Cable,
            primaryMuscleFocus: .shoulders
        )
        let legPress = Exercise(
            exerciseName: "Leg Press",
            exerciseEquipment: .LegPress,
            primaryMuscleFocus: .quads
        )

        let templateProgram = TemplateProgram(
            templateName: "Back In Action",
            workoutsPerWeek: 3,
            templateMuscleFocus: [.chest, .back, .quads]
        )
        templateProgram.templateWorkoutsValue = [
            TemplateWorkout(order: 0, templateExercises: [
                TemplateExercise(templateExercise: benchPress, order: 0),
                TemplateExercise(templateExercise: backSquat, order: 1),
            ]),
            TemplateWorkout(order: 1, templateExercises: [
                TemplateExercise(templateExercise: pullUp, order: 0),
                TemplateExercise(templateExercise: latPulldown, order: 1),
            ]),
            TemplateWorkout(order: 2, templateExercises: [
                TemplateExercise(templateExercise: lateralRaise, order: 0),
                TemplateExercise(templateExercise: legPress, order: 1),
            ]),
        ]

        let dayOne = Workout(
            order: 0,
            workoutExercises: [
                workoutExercise(exercise: benchPress, order: 0, sets: [
                    WorkoutSet(order: 0, reps: 8, weightTenthsPounds: 1800),
                    WorkoutSet(order: 1, reps: 8, weightTenthsPounds: 1800),
                    WorkoutSet(order: 2, reps: 6, weightTenthsPounds: 1850),
                ]),
                workoutExercise(exercise: backSquat, order: 1, sets: [
                    WorkoutSet(order: 0, reps: 8, weightTenthsPounds: 2250),
                    WorkoutSet(order: 1, reps: 8, weightTenthsPounds: 2250),
                    WorkoutSet(order: 2, reps: 6, weightTenthsPounds: 2300),
                ]),
            ]
        )
        completeWorkout(dayOne)

        let dayTwo = Workout(
            order: 1,
            workoutExercises: [
                workoutExercise(exercise: pullUp, order: 0, sets: [
                    WorkoutSet(order: 0, reps: 10, weightTenthsPounds: 0),
                    WorkoutSet(order: 1, reps: 8, weightTenthsPounds: 0),
                    WorkoutSet(order: 2, reps: 6, weightTenthsPounds: 0),
                ]),
                workoutExercise(exercise: latPulldown, order: 1, sets: [
                    WorkoutSet(order: 0, reps: 10, weightTenthsPounds: 1200),
                    WorkoutSet(order: 1, reps: 10, weightTenthsPounds: 1200),
                    WorkoutSet(order: 2, reps: 8, weightTenthsPounds: 1300),
                ]),
            ]
        )
        finishWorkout(dayTwo, setStatuses: [
            [.complete, .skipped, .complete],
            [.skipped, .complete, .complete],
        ])

        let dayThree = Workout(
            order: 2,
            workoutExercises: [
                workoutExercise(exercise: lateralRaise, order: 0, sets: [
                    WorkoutSet(order: 0, reps: 12, weightTenthsPounds: 150),
                    WorkoutSet(order: 1, reps: 12, weightTenthsPounds: 150),
                    WorkoutSet(order: 2, reps: 10, weightTenthsPounds: 150),
                ]),
                workoutExercise(exercise: legPress, order: 1, sets: [
                    WorkoutSet(order: 0, reps: 10, weightTenthsPounds: 3150),
                    WorkoutSet(order: 1, reps: 10, weightTenthsPounds: 3150),
                    WorkoutSet(order: 2, reps: 8, weightTenthsPounds: 3350),
                ]),
            ]
        )

        let weekOne = ProgramWeek(order: 0, workouts: [dayOne, dayTwo, dayThree])
        let emptyWeeks = (1..<8).map { ProgramWeek(order: $0, workouts: []) }
        let program = Program(
            programLengthWeeks: 8,
            status: .active,
            templateProgram: templateProgram,
            programWeeks: [weekOne] + emptyWeeks
        )

        container.mainContext.insert(program)

        do {
            try container.mainContext.save()
        } catch {
            fatalError("Could not save seeded in-memory data: \(error)")
        }

        return PowerJackProgramSeedScenario(
            container: container,
            program: program,
            weekOneWorkouts: [dayOne, dayTwo, dayThree]
        )
    }
}

private extension PowerJackSeed {
    static func workoutExercise(
        exercise: Exercise,
        order: Int,
        sets: [WorkoutSet]
    ) -> WorkoutExercise {
        WorkoutExercise(
            exercise: exercise,
            order: order,
            workoutSets: sets
        )
    }

    static func completeWorkout(_ workout: Workout) {
        workout.startAndCascade()
        workout.completeAndCascade()
    }

    static func finishWorkout(_ workout: Workout, setStatuses: [[Status]]) {
        workout.startAndCascade()

        let orderedWorkoutExercises = workout.workoutExercises.sorted { $0.order < $1.order }
        for (workoutExercise, statuses) in zip(orderedWorkoutExercises, setStatuses) {
            let orderedSets = workoutExercise.workoutSets.sorted { $0.order < $1.order }
            for (workoutSet, status) in zip(orderedSets, statuses) {
                switch status {
                case .complete:
                    workoutSet.complete()
                case .skipped:
                    workoutSet.skip()
                case .stopped:
                    workoutSet.stop()
                case .planned, .active:
                    break
                }
            }
            workoutExercise.complete()
        }

        workout.complete()
    }
}
