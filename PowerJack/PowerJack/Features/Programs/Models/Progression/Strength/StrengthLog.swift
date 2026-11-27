//
//  StrengthLog.swift
//  PowerJack
//
//  One row per finished strength week holding the engine's state after it, like `WorkoutLog`
//  it has no relationship to a program, so lift records outlive the programs that made them.
//  Rows are only ever added, so iCloud copies from two devices never conflict: the newest wins.
//  Only the newest is read, so older rows are rotated out once there are more than `keptLogs`.
//

import Foundation
import OSLog
import SwiftData

@Model
final class StrengthLog {
    // Speeds up fetches that filter or sort by these. Local store only: iCloud records carry no indexes.
    // Indexes alone don't change the model's hash, so the hash modifier below makes existing stores migrate and build them.
    #Index<StrengthLog>([\.dateValue], [\.sessionIDValue])

    @Attribute(hashModifier: "indexes-1")
    private var dateValue: Date = Date.now
    private var versionValue: String = ""
    private var stateValue: Data = Data()
    // The week's sync ID, so a week closed on two devices keeps one log.
    private var sessionIDValue: UUID?

    @MainActor
    init(date: Date, state: StrengthState, sessionID: UUID? = nil) {
        self.dateValue = date
        self.versionValue = StrengthRules.version
        self.stateValue = (try? JSONEncoder().encode(state)) ?? Data()
        self.sessionIDValue = sessionID
    }

    /// The watch's copy of the iPhone's latest log, so it plans strength weeks from the same records.
    init(snapshot state: StrengthLogState) {
        self.dateValue = state.date
        self.versionValue = state.version
        self.stateValue = state.state
        self.sessionIDValue = state.sessionID
    }
}

extension StrengthLog {
    var date: Date { dateValue }
    var sessionID: UUID? { sessionIDValue }

    var syncState: StrengthLogState {
        StrengthLogState(date: dateValue, version: versionValue, state: stateValue, sessionID: sessionIDValue)
    }

    /// The newest log, or nil before the first strength week closed.
    static func latest(in context: ModelContext) throws -> StrengthLog? {
        var descriptor = FetchDescriptor<StrengthLog>(sortBy: [SortDescriptor(\.dateValue, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// How many logs to keep. Only the newest is read; a few more cover a sync that lands out of order.
    static let keptLogs = 8

    /// Deletes all but the newest `keptLogs` logs. Sorted here rather than with a fetch offset, so logs
    /// inserted but not saved yet count too.
    static func rotate(in context: ModelContext) throws {
        let logs = try context.fetch(FetchDescriptor<StrengthLog>()).sorted { $0.dateValue > $1.dateValue }
        for log in logs.dropFirst(keptLogs) {
            context.delete(log)
        }
    }

    /// Logs written since `date` that name the week they came from. Older logs don't, and are never merged.
    static func withSession(since date: Date = .distantPast, in context: ModelContext) throws -> [StrengthLog] {
        try context.fetch(FetchDescriptor<StrengthLog>(predicate: #Predicate { $0.sessionIDValue != nil && $0.dateValue >= date }))
    }

    @MainActor
    var state: StrengthState? {
        try? JSONDecoder().decode(StrengthState.self, from: stateValue)
    }

    /// The state after the latest strength week, or a fresh one before the first.
    @MainActor
    static func latestState(in context: ModelContext?) -> StrengthState {
        guard let context else { return StrengthState() }
        var descriptor = FetchDescriptor<StrengthLog>(sortBy: [SortDescriptor(\.dateValue, order: .reverse)])
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first?.state ?? StrengthState()
        } catch {
            Logger.program.error("Could not read the strength log: \(error.localizedDescription)")
            return StrengthState()
        }
    }
}
