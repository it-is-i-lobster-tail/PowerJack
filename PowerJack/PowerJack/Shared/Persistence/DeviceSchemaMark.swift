//
//  DeviceSchemaMark.swift
//  PowerJack
//
//  One row per device (iPhone or watch) saying which shape of the long history it reads, updated
//  at every launch. Old history rows can only go once every device still in use reads the new shape.
//

import Foundation
import OSLog
import SwiftData

@Model
final class DeviceSchemaMark {
    var deviceIDValue: UUID?
    /// `SyncDevice.iPhone` or `.watch`, for the trace.
    var deviceValue: String = ""
    /// The `DeviceSchemaMark.historyShapeVersion` of the app that launched last on the device.
    var historyShapeVersionValue: Int = 0
    var lastSeenValue: Date?

    init(deviceID: UUID) {
        deviceIDValue = deviceID
    }
}

extension DeviceSchemaMark {
    /// 1: reads `HistoryProgram` and `HistoryExercise`, falling back to `HistoryRecord`.
    static let historyShapeVersion = 1
    /// A device not seen for this long no longer holds back the trim.
    static let activeWindow: TimeInterval = 90 * 24 * 60 * 60

    private static let deviceIDKey = "deviceSchemaMark.deviceID"

    /// This install's own ID, made once and kept on the device only.
    static func currentDeviceID(in defaults: UserDefaults = .standard) -> UUID {
        if let saved = defaults.string(forKey: deviceIDKey).flatMap(UUID.init(uuidString:)) { return saved }
        let id = UUID()
        defaults.set(id.uuidString, forKey: deviceIDKey)
        return id
    }

    var historyShapeVersion: Int { historyShapeVersionValue }
    var lastSeen: Date { lastSeenValue ?? .distantPast }

    /// Records that this device launched now with this version, then saves.
    static func update(in context: ModelContext, deviceID: UUID = currentDeviceID(), device: String = SyncDevice.current, now: Date = .now) throws {
        let id: UUID? = deviceID
        let mark = try context.fetch(FetchDescriptor<DeviceSchemaMark>(predicate: #Predicate { $0.deviceIDValue == id })).first
            ?? {
                let new = DeviceSchemaMark(deviceID: deviceID)
                context.insert(new)
                return new
            }()
        mark.deviceValue = device
        mark.historyShapeVersionValue = historyShapeVersion
        mark.lastSeenValue = now
        try context.save()
    }

    /// Whether every device seen in the last `activeWindow` reads the new history shape, so the
    /// old `HistoryRecord` rows can go. False until at least one device has said so.
    static func canTrimLegacyHistory(in context: ModelContext, now: Date = .now) throws -> Bool {
        let since = now.addingTimeInterval(-activeWindow)
        let recent = try context.fetch(FetchDescriptor<DeviceSchemaMark>()).filter { $0.lastSeen >= since }
        return !recent.isEmpty && recent.allSatisfy { $0.historyShapeVersion >= 1 }
    }

    /// Never stops a launch: the next one tries again.
    static func updateAtLaunch(in context: ModelContext) {
        do {
            try update(in: context)
        } catch {
            context.rollback()
            Logger.persistence.error("Could not update this device's schema mark: \(error.localizedDescription)")
        }
    }
}
