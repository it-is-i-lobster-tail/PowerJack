//
//  CloudKitSchemaSetup.swift
//  PowerJack
//
//  CI prepares the CloudKit Development schema from the merged model on main.
//  For local troubleshooting, a signed-in debug build can initialize Development
//  with the `-initCloudKitSchema` launch argument.
//

#if DEBUG
import CoreData
import Foundation
import OSLog
import SwiftData

enum CloudKitSchemaSetup {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-initCloudKitSchema")
    }

    /// Uses a throwaway store, so the user's data is never touched.
    static func run() {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: PowerJackSchema.modelTypes) else {
            Logger.sync.error("Could not build the model for the CloudKit schema")
            return
        }

        let storeURL = URL.temporaryDirectory.appending(path: "CloudKitSchemaSetup.store")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: PowerJackSchema.cloudKitContainerID
        )
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "CloudKitSchemaSetup", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }

        do {
            if let loadError { throw loadError }
            try container.initializeCloudKitSchema()
            Logger.sync.info("Wrote every field to the CloudKit Development schema")
        } catch {
            Logger.sync.error("Could not write the CloudKit schema: \(String(describing: error), privacy: .public)")
        }

        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        try? coordinator.destroyPersistentStore(at: storeURL, type: .sqlite)
    }
}
#endif
