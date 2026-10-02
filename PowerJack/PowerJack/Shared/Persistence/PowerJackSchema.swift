//
//  PowerJackSchema.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftData

enum PowerJackSchema {
    static let schema = Schema([
        Program.self,
        ProgramWeek.self,
        Workout.self,
        WorkoutExercise.self,
        WorkoutSet.self,
        ExerciseFeedback.self,
        Exercise.self,
        TemplateProgram.self,
        TemplateWorkout.self,
        TemplateExercise.self,
    ])

    static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
