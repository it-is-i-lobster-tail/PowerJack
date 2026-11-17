//
//  PowerJackSchema.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import CoreData
import OSLog
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

    /// iCloud fails quietly, for example when a field is missing from the Production schema,
    /// so this logs every failed sync to make it show up in Console. Runs for the life of the app.
    static func logCloudKitErrors() {
        Task {
            for await notification in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                guard
                    let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                    event.endDate != nil,
                    let error = event.error
                else { continue }
                Logger.sync.error("iCloud \(Self.name(of: event.type), privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func name(of eventType: NSPersistentCloudKitContainer.EventType) -> String {
        switch eventType {
        case .setup: "setup"
        case .import: "download"
        case .export: "upload"
        @unknown default: "sync"
        }
    }
}
