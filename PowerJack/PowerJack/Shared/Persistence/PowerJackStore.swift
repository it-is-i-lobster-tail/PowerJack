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
    @ObservationIgnored private var scheduledTidyUp: Task<Void, Never>?
    /// What the scheduled tidy-up follows, for the trace.
    @ObservationIgnored private var tidyUpTriggers: Set<String> = []
    /// At most one tidy-up pass this often, however many changes iCloud or the watch bring.
    static let tidyUpInterval: Duration = .seconds(1.5)

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
        PowerJackSchema.logCloudKitErrors()
    }

    func turnOnICloudBackup() {
        TraceLog.record(.iCloud, "iCloud Backup: turning on")
        saveBeforeSwitching()
        switchContainer(syncsWithICloud: true)
        Logger.sync.info("iCloud Backup turned on")
    }

    /// Deletes the copy in iCloud, then stops syncing. Data on this iPhone is kept.
    /// If iCloud can't be reached, nothing changes and the error is thrown.
    func turnOffICloudBackup() async throws {
        // Saved before the iCloud copy goes, so the save can't upload into it again.
        TraceLog.record(.iCloud, "iCloud Backup: turning off, deleting the iCloud copy")
        saveBeforeSwitching()
        do {
            try await CKContainer(identifier: PowerJackSchema.cloudKitContainerID)
                .privateCloudDatabase
                .deleteRecordZone(withID: Self.cloudKitZone)
        } catch let error as CKError where Self.hasNoCopyToDelete(error) {
            Logger.sync.info("No iCloud copy to delete: \(error.localizedDescription)")
            TraceLog.record(.iCloud, "iCloud Backup: no iCloud copy to delete (\(TraceLog.describe(error)))")
        } catch {
            Logger.sync.error("Could not delete the iCloud copy: \(error.localizedDescription)")
            TraceLog.record(.iCloud, "iCloud Backup: could not delete the iCloud copy, staying on (\(TraceLog.describe(error)))")
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
        TraceLog.record(.iCloud, "iCloud Backup: screens closing to switch stores, iCloud \(syncsWithICloud ? "on" : "off")")
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
            TraceLog.record(.iCloud, "iCloud Backup: store opened after the switch (iCloud \(syncsWithICloud ? "on" : "off"))")
        } catch {
            Logger.sync.error("Could not open the store after switching iCloud Backup: \(error.localizedDescription)")
            TraceLog.record(.iCloud, "iCloud Backup: store didn't open after the switch, so the setting goes back (\(TraceLog.describe(error)))")
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
            TraceLog.record(.iCloud, "iCloud Backup: save before the switch failed (\(TraceLog.describe(error)))")
        }
    }

    /// A new iPhone seeds the built-in catalog before its synced data arrives, and the watch can
    /// sync the same workout through iCloud and straight from the watch, so tidy up each time
    /// iCloud changes the store.
    private func mergeDuplicatesAfterImports() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                self?.scheduleTidyUp(after: "iCloud import")
            }
        }
    }

    /// Tidies up once the changes coming in settle, at most once per `tidyUpInterval`: an iCloud import
    /// or a workout's worth of watch messages can bring many changes a second.
    func scheduleTidyUp(after trigger: String) {
        tidyUpTriggers.insert(trigger)
        guard scheduledTidyUp == nil else { return }
        scheduledTidyUp = Task { [weak self] in
            try? await Task.sleep(for: Self.tidyUpInterval)
            guard let self else { return }
            scheduledTidyUp = nil
            let triggers = tidyUpTriggers.sorted().joined(separator: ", ")
            tidyUpTriggers = []
            // The store being replaced can't be read; the new one tidies up after its next import.
            guard !isReplacingContainer else { return }
            mergeCatalogDuplicates()
            tidyUpAfterSync(trigger: triggers)
        }
    }

    /// See `SyncTidyUp`.
    func tidyUpAfterSync(trigger: String) {
        do {
            try SyncTidyUp.run(in: container.mainContext, trigger: trigger)
        } catch {
            Logger.sync.error("Could not tidy up after syncing: \(error.localizedDescription)")
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

    /// Fills the long history with any program that ended before it existed, or while this
    /// iPhone wasn't the one running it. A failure never stops the app opening: the export tries again.
    private static func saveEndedPrograms(in context: ModelContext) {
        do {
            try HistoryArchive.saveEndedPrograms(in: context)
        } catch {
            Logger.persistence.error("Could not save ended programs' history: \(error.localizedDescription)")
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
        saveEndedPrograms(in: container.mainContext)
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
