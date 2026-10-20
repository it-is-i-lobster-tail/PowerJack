//
//  StrengthLog.swift
//  PowerJack
//
//  One row per finished strength week holding the engine's state after it, like `WorkoutLog`
//  it has no relationship to a program, so lift records outlive the programs that made them.
//  Rows are only ever added, so iCloud copies from two devices never conflict: the newest wins.
//

import Foundation
import OSLog
import SwiftData

@Model
final class StrengthLog {
    private var dateValue: Date = Date.now
    private var versionValue: String = ""
    private var stateValue: Data = Data()

    @MainActor
    init(date: Date, state: StrengthState) {
        self.dateValue = date
        self.versionValue = StrengthRules.version
        self.stateValue = (try? JSONEncoder().encode(state)) ?? Data()
    }
}

extension StrengthLog {
    var date: Date { dateValue }

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
