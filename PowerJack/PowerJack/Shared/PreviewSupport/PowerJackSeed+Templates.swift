//
//  PowerJackSeed+Templates.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

extension PowerJackSeed {
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
}
