//
//  PowerJackStore.swift
//  PowerJack
//
//  Owns the app's model container and turns iCloud Backup on or off.
//

import CloudKit
import CoreData
import Foundation
import Observation
import OSLog
import SwiftData

@MainActor
@Observable
final class PowerJackStore {
    /// Replaced when iCloud Backup is switched, so views must rebuild from it.
    private(set) var container: ModelContainer
    private(set) var syncsWithICloud: Bool

    private let inMemory: Bool

    // The zone SwiftData's CloudKit mirroring writes every record to.
    private static let cloudKitZone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        let savedSetting = UserDefaults.standard.object(forKey: AppSettings.Key.iCloudBackup) as? Bool
        let syncs = !inMemory && (savedSetting ?? AppSettings.Default.iCloudBackup)
        syncsWithICloud = syncs
        container = Self.makeContainer(inMemory: inMemory, syncsWithICloud: syncs)
        mergeDuplicatesAfterImports()
    }

    func turnOnICloudBackup() {
        switchContainer(syncsWithICloud: true)
        Logger.sync.info("iCloud Backup turned on")
    }

    /// Deletes the copy in iCloud, then stops syncing. Data on this iPhone is kept.
    /// If iCloud can't be reached, nothing changes and the error is thrown.
    func turnOffICloudBackup() async throws {
        do {
            try await CKContainer(identifier: PowerJackSchema.cloudKitContainerID)
                .privateCloudDatabase
                .deleteRecordZone(withID: Self.cloudKitZone)
        } catch let error as CKError where error.code == .zoneNotFound {
            // Nothing was uploaded yet, so there is nothing to delete.
        } catch {
            Logger.sync.error("Could not delete the iCloud copy: \(error.localizedDescription)")
            throw error
        }
        switchContainer(syncsWithICloud: false)
        Logger.sync.info("iCloud Backup turned off and the iCloud copy deleted")
    }

    /// Whether this iPhone is signed in to iCloud, so backup can actually run.
    func iCloudAccountAvailable() async -> Bool {
        let status = try? await CKContainer(identifier: PowerJackSchema.cloudKitContainerID).accountStatus()
        return status == .available
    }

    private func switchContainer(syncsWithICloud: Bool) {
        self.syncsWithICloud = syncsWithICloud
        UserDefaults.standard.set(syncsWithICloud, forKey: AppSettings.Key.iCloudBackup)
        container = Self.makeContainer(inMemory: inMemory, syncsWithICloud: syncsWithICloud)
    }

    /// A new iPhone seeds the built-in catalog before its synced data arrives,
    /// so merge any duplicates each time iCloud changes the store.
    private func mergeDuplicatesAfterImports() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                self?.mergeCatalogDuplicates()
            }
        }
    }

    private func mergeCatalogDuplicates() {
        let context = container.mainContext
        do {
            let mergedExercises = try ExerciseCatalog.removeDuplicates(in: context)
            let mergedTemplates = try TemplateCatalog.removeDuplicates(in: context)
            guard mergedExercises || mergedTemplates else { return }
            try context.save()
            Logger.sync.info("Merged duplicate catalog rows after an iCloud import")
        } catch {
            Logger.sync.error("Could not merge duplicate catalog rows: \(error.localizedDescription)")
        }
    }

    private static func makeContainer(inMemory: Bool, syncsWithICloud: Bool) -> ModelContainer {
        do {
            let container = try PowerJackSchema.makeModelContainer(inMemory: inMemory, syncsWithICloud: syncsWithICloud)
            try ExerciseCatalog.seed(in: container.mainContext)
            try TemplateCatalog.seed(in: container.mainContext)
            return container
        } catch {
            fatalError("Could not create PowerJack's model container: \(error)")
        }
    }
}
