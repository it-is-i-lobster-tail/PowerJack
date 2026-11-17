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
    /// True between an iCloud Backup switch and `replaceContainer()`. The screens come down first,
    /// because reading a model after its container closes crashes the app.
    private(set) var isReplacingContainer = false

    private let inMemory: Bool

    // The zone SwiftData's CloudKit mirroring writes every record to.
    private static let cloudKitZone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        let savedSetting = UserDefaults.standard.object(forKey: AppSettings.Key.iCloudBackup) as? Bool
        let syncs = !inMemory && (savedSetting ?? AppSettings.Default.iCloudBackup)
        #if DEBUG
        if !inMemory, CloudKitSchemaSetup.isRequested {
            CloudKitSchemaSetup.run()
        }
        #endif
        syncsWithICloud = syncs
        container = Self.makeContainer(inMemory: inMemory, syncsWithICloud: syncs)
        mergeDuplicatesAfterImports()
        logSyncErrors()
    }

    func turnOnICloudBackup() {
        saveBeforeSwitching()
        switchContainer(syncsWithICloud: true)
        Logger.sync.info("iCloud Backup turned on")
    }

    /// Deletes the copy in iCloud, then stops syncing. Data on this iPhone is kept.
    /// If iCloud can't be reached, nothing changes and the error is thrown.
    func turnOffICloudBackup() async throws {
        // Saved before the iCloud copy goes, so the save can't upload into it again.
        saveBeforeSwitching()
        do {
            try await CKContainer(identifier: PowerJackSchema.cloudKitContainerID)
                .privateCloudDatabase
                .deleteRecordZone(withID: Self.cloudKitZone)
        } catch let error as CKError where Self.hasNoCopyToDelete(error) {
            Logger.sync.info("No iCloud copy to delete: \(error.localizedDescription)")
        } catch {
            Logger.sync.error("Could not delete the iCloud copy: \(error.localizedDescription)")
            throw error
        }
        switchContainer(syncsWithICloud: false)
        Logger.sync.info("iCloud Backup turned off and the iCloud copy deleted")
    }

    /// Nothing was uploaded yet, or this iPhone isn't signed in to iCloud, so it backed nothing up
    /// and backup can be turned off without deleting anything.
    static func hasNoCopyToDelete(_ error: CKError) -> Bool {
        error.code == .zoneNotFound || error.code == .notAuthenticated
    }

    /// Whether this iPhone is signed in to iCloud, so backup can actually run.
    func iCloudAccountAvailable() async -> Bool {
        let status = try? await CKContainer(identifier: PowerJackSchema.cloudKitContainerID).accountStatus()
        return status == .available
    }

    /// Only asks for the switch. The root view calls `replaceContainer()` once no screen holds
    /// a model from the current container.
    private func switchContainer(syncsWithICloud: Bool) {
        self.syncsWithICloud = syncsWithICloud
        UserDefaults.standard.set(syncsWithICloud, forKey: AppSettings.Key.iCloudBackup)
        isReplacingContainer = true
    }

    /// Opens the container for the current iCloud Backup setting, after a switch. If it won't open,
    /// the current container stays and the setting goes back to match it.
    func replaceContainer() {
        guard isReplacingContainer else { return }
        defer { isReplacingContainer = false }
        do {
            let replacement = try Self.openContainer(inMemory: inMemory, syncsWithICloud: syncsWithICloud)
            // A save still scheduled on the old container would run after it closes.
            container.mainContext.autosaveEnabled = false
            container = replacement
        } catch {
            Logger.sync.error("Could not open the store after switching iCloud Backup: \(error.localizedDescription)")
            syncsWithICloud.toggle()
            UserDefaults.standard.set(syncsWithICloud, forKey: AppSettings.Key.iCloudBackup)
        }
    }

    /// The new container reads the same data, so anything not yet saved would be lost.
    private func saveBeforeSwitching() {
        do {
            try container.mainContext.save()
        } catch {
            Logger.sync.error("Could not save before switching iCloud Backup: \(error.localizedDescription)")
        }
    }

    /// A new iPhone seeds the built-in catalog before its synced data arrives, and the watch can
    /// sync the same workout through iCloud and straight from the watch, so tidy up each time
    /// iCloud changes the store.
    private func mergeDuplicatesAfterImports() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                self?.mergeCatalogDuplicates()
                self?.tidyUpAfterSync()
            }
        }
    }

    /// See `SyncTidyUp`.
    func tidyUpAfterSync() {
        do {
            try SyncTidyUp.run(in: container.mainContext)
        } catch {
            Logger.sync.error("Could not tidy up after syncing: \(error.localizedDescription)")
        }
    }

    /// iCloud fails quietly, for example when a field is missing from the Production schema,
    /// so log every failed sync to make it show up in Console.
    private func logSyncErrors() {
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

    /// PowerJack can't run without its store, so only a store that won't open stops the app.
    private static func makeContainer(inMemory: Bool, syncsWithICloud: Bool) -> ModelContainer {
        do {
            return try openContainer(inMemory: inMemory, syncsWithICloud: syncsWithICloud)
        } catch {
            fatalError("Could not create PowerJack's model container: \(error)")
        }
    }

    private static func openContainer(inMemory: Bool, syncsWithICloud: Bool) throws -> ModelContainer {
        let container = try PowerJackSchema.makeModelContainer(inMemory: inMemory, syncsWithICloud: syncsWithICloud)
        seedCatalogs(in: container.mainContext)
        return container
    }

    /// A seed that fails is undone and tried again next launch, so it never keeps the app from opening.
    private static func seedCatalogs(in context: ModelContext) {
        do {
            try ExerciseCatalog.seed(in: context)
            try TemplateCatalog.seed(in: context)
        } catch {
            context.rollback()
            Logger.persistence.error("Could not seed the built-in catalog, trying again next launch: \(error.localizedDescription)")
        }
    }
}
