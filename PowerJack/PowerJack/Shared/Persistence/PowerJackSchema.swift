//
//  PowerJackSchema.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftData

enum PowerJackSchema {
    static let modelTypes: [any PersistentModel.Type] = [
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
        WorkoutLog.self,
        StrengthLog.self,
        SetReceipt.self,
        HistoryRecord.self,
    ]

    static let schema = Schema(modelTypes)

    /// The user's private iCloud database. Only they can read it.
    static let cloudKitContainerID = "iCloud.com.stanleycloud.PowerJack"

    static func makeModelContainer(inMemory: Bool = false, syncsWithICloud: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: syncsWithICloud && !inMemory ? .private(cloudKitContainerID) : .none
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            // Written straight to disk: the app usually stops right after a store fails to open.
            TraceLog.recordNow(
                .data,
                "Store didn't open: \(TraceLog.describe(error)), iCloud \(syncsWithICloud ? "on" : "off"), in memory \(inMemory), version \(TraceLog.appVersion), last launched \(TraceLog.previousAppVersion)"
            )
            throw error
        }
    }
}
