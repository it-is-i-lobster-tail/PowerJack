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
    let exercises: [Exercise]
    let templateProgram: TemplateProgram
    let templatePrograms: [TemplateProgram]
    let weekOneWorkouts: [Workout]
}

struct PowerJackWorkoutSeedScenario {
    let container: ModelContainer
    let workout: Workout
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
        let exercises = makeExercises()
        let templateProgram = makeTemplateProgram(exercises: exercises)
        let accessoryTemplateProgram = TemplateProgram(
            templateName: "Upper Tune Up",
            workoutsPerWeek: 2,
            templateMuscleFocus: [.shoulders, .back]
        )

        let dayOne = makeWorkout(
            order: 0,
            exercises: [exercises[0], exercises[1]],
            sets: [
                [
                    SeedSet(reps: 8, weightTenthsPounds: 1800, status: .complete),
                    SeedSet(reps: 8, weightTenthsPounds: 1800, status: .complete),
                    SeedSet(reps: 6, weightTenthsPounds: 1850, status: .complete),
                ],
                [
                    SeedSet(reps: 8, weightTenthsPounds: 2250, status: .complete),
                    SeedSet(reps: 8, weightTenthsPounds: 2250, status: .complete),
                    SeedSet(reps: 6, weightTenthsPounds: 2300, status: .complete),
                ],
            ]
        )

        let dayTwo = makeWorkout(
            order: 1,
            exercises: [exercises[2], exercises[3]],
            sets: [
                [
                    SeedSet(reps: 10, weightTenthsPounds: nil, status: .complete),
                    SeedSet(reps: 8, weightTenthsPounds: nil, status: .skipped),
                    SeedSet(reps: 6, weightTenthsPounds: nil, status: .complete),
                ],
                [
                    SeedSet(reps: 10, weightTenthsPounds: 1200, status: .skipped),
                    SeedSet(reps: 10, weightTenthsPounds: 1200, status: .complete),
                    SeedSet(reps: 8, weightTenthsPounds: 1300, status: .active),
                ],
            ]
        )

        let dayThree = makeWorkout(
            order: 2,
            exercises: [exercises[4], exercises[5]],
            sets: [
                [
                    SeedSet(reps: 12, weightTenthsPounds: 150, status: .active),
                    SeedSet(reps: 12, weightTenthsPounds: 150, status: .active),
                    SeedSet(reps: 10, weightTenthsPounds: 150, status: .active),
                ],
                [
                    SeedSet(reps: 10, weightTenthsPounds: 3150, status: .active),
                    SeedSet(reps: 10, weightTenthsPounds: 3150, status: .active),
                    SeedSet(reps: 8, weightTenthsPounds: 3350, status: .active),
                ],
            ]
        )

        let weekOne = ProgramWeek(order: 0)
        weekOne.workoutsValue = [dayOne, dayTwo, dayThree]
        let emptyWeeks = (1..<8).map { ProgramWeek(order: $0) }

        let program = Program(programLengthWeeks: 8, templateProgram: templateProgram)
        program.programLengthWeeksValue = 8
        program.statusValue = .active
        program.programWeeksValue = [weekOne] + emptyWeeks

        for exercise in exercises {
            container.mainContext.insert(exercise)
        }
        container.mainContext.insert(templateProgram)
        container.mainContext.insert(accessoryTemplateProgram)
        container.mainContext.insert(program)

        do {
            try container.mainContext.save()
        } catch {
            fatalError("Could not save seeded in-memory data: \(error)")
        }

        return PowerJackProgramSeedScenario(
            container: container,
            program: program,
            exercises: exercises,
            templateProgram: templateProgram,
            templatePrograms: [templateProgram, accessoryTemplateProgram],
            weekOneWorkouts: [dayOne, dayTwo, dayThree]
        )
    }

    static func emptyWorkout() -> PowerJackWorkoutSeedScenario {
        let container = makeInMemoryContainer()
        let workout = Workout(order: 0)

        container.mainContext.insert(workout)

        do {
            try container.mainContext.save()
        } catch {
            fatalError("Could not save empty workout preview data: \(error)")
        }

        return PowerJackWorkoutSeedScenario(container: container, workout: workout)
    }
}

private extension PowerJackSeed {
    struct SeedSet {
        let reps: Int?
        let weightTenthsPounds: Int?
        let status: Status
    }

    static func makeExercises() -> [Exercise] {
        [
            Exercise(
                exerciseName: "Barbell Bench Press",
                exerciseEquipment: .barbell,
                primaryMuscleFocus: .chest
            ),
            Exercise(
                exerciseName: "Barbell Back Squat",
                exerciseEquipment: .barbell,
                primaryMuscleFocus: .quads
            ),
            Exercise(
                exerciseName: "Pull Up",
                exerciseEquipment: .bodyweight,
                primaryMuscleFocus: .back
            ),
            Exercise(
                exerciseName: "Lat Pulldown",
                exerciseEquipment: .cable,
                primaryMuscleFocus: .back
            ),
            Exercise(
                exerciseName: "Cable Lateral Raise",
                exerciseEquipment: .cable,
                primaryMuscleFocus: .shoulders
            ),
            Exercise(
                exerciseName: "Leg Press",
                exerciseEquipment: .legPress,
                primaryMuscleFocus: .quads
            ),
        ]
    }

    static func makeTemplateProgram(exercises: [Exercise]) -> TemplateProgram {
        let templateProgram = TemplateProgram(
            templateName: "Back In Action",
            workoutsPerWeek: 3,
            templateMuscleFocus: [.chest, .back, .quads]
        )

        let dayOne = TemplateWorkout(order: 0)
        dayOne.templateExercisesValue = [
            TemplateExercise(exercise: exercises[0], order: 0),
            TemplateExercise(exercise: exercises[1], order: 1),
        ]

        let dayTwo = TemplateWorkout(order: 1)
        dayTwo.templateExercisesValue = [
            TemplateExercise(exercise: exercises[2], order: 0),
            TemplateExercise(exercise: exercises[3], order: 1),
        ]

        let dayThree = TemplateWorkout(order: 2)
        dayThree.templateExercisesValue = [
            TemplateExercise(exercise: exercises[4], order: 0),
            TemplateExercise(exercise: exercises[5], order: 1),
        ]

        templateProgram.templateWorkoutsValue = [dayOne, dayTwo, dayThree]
        return templateProgram
    }

    static func makeWorkout(
        order: Int,
        exercises: [Exercise],
        sets: [[SeedSet]]
    ) -> Workout {
        let workout = Workout(order: order)

        for (exerciseIndex, exercise) in exercises.enumerated() {
            guard let workoutExercise = workout.addWorkoutExercise(exercise: exercise) else {
                continue
            }

            let exerciseSets = sets.indices.contains(exerciseIndex) ? sets[exerciseIndex] : []
            for seedSet in exerciseSets {
                guard let workoutSet = workoutExercise.addSet() else {
                    continue
                }

                workoutSet.reps = seedSet.reps
                workoutSet.weightTenthsPounds = seedSet.weightTenthsPounds
                apply(seedSet.status, to: workoutSet)
            }
        }

        return workout
    }

    static func apply(_ status: Status, to workoutSet: WorkoutSet) {
        switch status {
        case .complete:
            workoutSet.complete()
        case .skipped:
            workoutSet.skip()
        case .stopped:
            workoutSet.stop()
        case .active, .planned:
            break
        }
    }
}
