//
//  WatchStore.swift
//  PowerJackWatch
//
//  The watch's copy of the user's data. `WatchSync` keeps it in step with the iPhone directly,
//  and when iCloud Backup is on it also syncs through iCloud. Follows the iPhone's iCloud Backup
//  setting, which `DeviceLink` brings over; with it off the store stays on the watch.
//

import CoreData
import Foundation
import Observation
import OSLog
import SwiftData

@MainActor
@Observable
final class WatchStore {
    /// Replaced when iCloud Backup is switched on the iPhone, so views must rebuild from it.
    private(set) var container: ModelContainer
    private(set) var syncsWithICloud: Bool

    private static var runsInPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static var iCloudBackupSetting: Bool {
        UserDefaults.standard.object(forKey: AppSettings.Key.iCloudBackup) as? Bool ?? AppSettings.Default.iCloudBackup
    }

    init() {
        #if DEBUG
        if let demoType = WatchDemo.requestedType {
            syncsWithICloud = true
            container = WatchDemo.makeContainer(type: demoType)
            return
        }
        #endif
        let syncs = !Self.runsInPreviews && Self.iCloudBackupSetting
        syncsWithICloud = syncs
        container = Self.makeContainer(syncsWithICloud: syncs)
        followICloudBackupSetting()
        tidyUpAfterImports()
        logSyncErrors()
    }

    private func followICloudBackupSetting() {
        guard !Self.runsInPreviews else { return }
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                guard let self, Self.iCloudBackupSetting != syncsWithICloud else { continue }
                syncsWithICloud = Self.iCloudBackupSetting
                container = Self.makeContainer(syncsWithICloud: syncsWithICloud)
                Logger.sync.info("iCloud Backup turned \(self.syncsWithICloud ? "on" : "off") from iPhone")
            }
        }
    }

    /// iCloud can bring the iPhone's own copy of rows the watch already copied from it directly,
    /// so tidy up each time iCloud changes the store (see `SyncTidyUp`).
    private func tidyUpAfterImports() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                guard let context = self?.container.mainContext else { continue }
                do {
                    if try ExerciseCatalog.removeDuplicates(in: context) { try context.save() }
                    try SyncTidyUp.run(in: context, running: WatchReplica().runningOnIPhone)
                } catch {
                    Logger.sync.error("Could not tidy up after an iCloud import: \(error.localizedDescription)")
                }
            }
        }
    }

    /// iCloud fails quietly, so log every failed sync to make it show up in Console.
    private func logSyncErrors() {
        Task {
            for await notification in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                guard
                    let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                    event.endDate != nil,
                    let error = event.error
                else { continue }
                Logger.sync.error("iCloud sync failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The catalog isn't seeded here: everything the watch shows comes from the iPhone.
    private static func makeContainer(syncsWithICloud: Bool) -> ModelContainer {
        do {
            return try PowerJackSchema.makeModelContainer(inMemory: runsInPreviews, syncsWithICloud: syncsWithICloud)
        } catch {
            fatalError("Could not create PowerJack's model container: \(error)")
        }
    }
}
