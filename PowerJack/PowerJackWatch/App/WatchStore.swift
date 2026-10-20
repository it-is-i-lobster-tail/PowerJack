//
//  WatchStore.swift
//  PowerJackWatch
//
//  The watch's copy of the user's data, synced with the iPhone through iCloud.
//  Follows the iPhone's iCloud Backup setting, which `SettingsSync` brings over.
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
