//
//  PowerJackProgramSeedScenario.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
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

extension PowerJackSeed {
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
                    SeedSet(
                        plannedReps: 8,
                        plannedWeightTenthsPounds: 1800,
                        actualReps: 8,
                        actualWeightTenthsPounds: 1800,
                        status: .complete
                    ),
                    SeedSet(
                        plannedReps: 8,
                        plannedWeightTenthsPounds: 1800,
                        actualReps: 8,
                        actualWeightTenthsPounds: 1800,
                        status: .complete
                    ),
                    SeedSet(
                        plannedReps: 8,
                        plannedWeightTenthsPounds: 1800,
                        actualReps: 6,
                        actualWeightTenthsPounds: 1850,
                        status: .complete
                    ),
                ],
                [
                    SeedSet(
                        plannedReps: 8,
                        plannedWeightTenthsPounds: 2250,
                        actualReps: 8,
                        actualWeightTenthsPounds: 2250,
                        status: .complete
                    ),
                    SeedSet(
                        plannedReps: 8,
                        plannedWeightTenthsPounds: 2250,
                        actualReps: 8,
                        actualWeightTenthsPounds: 2250,
                        status: .complete
                    ),
                    SeedSet(
                        plannedReps: 8,
                        plannedWeightTenthsPounds: 2250,
                        actualReps: 6,
                        actualWeightTenthsPounds: 2300,
                        status: .complete
                    ),
                ],
            ]
        )

        let dayTwo = makeWorkout(
            order: 1,
            exercises: [exercises[2], exercises[3]],
            sets: [
                [
                    SeedSet(
                        plannedReps: 10,
                        plannedWeightTenthsPounds: nil,
                        actualReps: 10,
                        actualWeightTenthsPounds: nil,
                        status: .complete
                    ),
                    SeedSet(
                        plannedReps: 10,
                        plannedWeightTenthsPounds: nil,
                        actualReps: 8,
                        actualWeightTenthsPounds: nil,
                        status: .skipped
                    ),
                    SeedSet(
                        plannedReps: 8,
                        plannedWeightTenthsPounds: nil,
                        actualReps: 6,
                        actualWeightTenthsPounds: nil,
                        status: .complete
                    ),
                ],
                [
                    SeedSet(
                        plannedReps: 10,
                        plannedWeightTenthsPounds: 1200,
                        actualReps: 10,
                        actualWeightTenthsPounds: 1200,
                        status: .skipped
                    ),
                    SeedSet(
                        plannedReps: 10,
                        plannedWeightTenthsPounds: 1200,
                        actualReps: 10,
                        actualWeightTenthsPounds: 1200,
                        status: .complete
                    ),
                    SeedSet(
                        plannedReps: 10,
                        plannedWeightTenthsPounds: 1200,
                        actualReps: 8,
                        actualWeightTenthsPounds: 1300,
                        status: .active
                    ),
                ],
            ]
        )

        let dayThree = makeWorkout(
            order: 2,
            exercises: [exercises[4], exercises[5]],
            sets: [
                [
                    SeedSet(
                        plannedReps: 12,
                        plannedWeightTenthsPounds: 150,
                        actualReps: nil,
                        actualWeightTenthsPounds: nil,
                        status: .active
                    ),
                    SeedSet(
                        plannedReps: 12,
                        plannedWeightTenthsPounds: 150,
                        actualReps: nil,
                        actualWeightTenthsPounds: nil,
                        status: .active
                    ),
                    SeedSet(
                        plannedReps: 10,
                        plannedWeightTenthsPounds: 150,
                        actualReps: nil,
                        actualWeightTenthsPounds: nil,
                        status: .active
                    ),
                ],
                [
                    SeedSet(
                        plannedReps: 10,
                        plannedWeightTenthsPounds: 3150,
                        actualReps: nil,
                        actualWeightTenthsPounds: nil,
                        status: .active
                    ),
                    SeedSet(
                        plannedReps: 10,
                        plannedWeightTenthsPounds: 3150,
                        actualReps: nil,
                        actualWeightTenthsPounds: nil,
                        status: .active
                    ),
                    SeedSet(
                        plannedReps: 8,
                        plannedWeightTenthsPounds: 3350,
                        actualReps: nil,
                        actualWeightTenthsPounds: nil,
                        status: .active
                    ),
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
}
