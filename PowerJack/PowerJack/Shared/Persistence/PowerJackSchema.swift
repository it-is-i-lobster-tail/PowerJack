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

    /// The user's private iCloud database. Only they can read it.
    static let cloudKitContainerID = "iCloud.com.stanleycloud.PowerJack"

    static func makeModelContainer(inMemory: Bool = false, syncsWithICloud: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: syncsWithICloud && !inMemory ? .private(cloudKitContainerID) : .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
