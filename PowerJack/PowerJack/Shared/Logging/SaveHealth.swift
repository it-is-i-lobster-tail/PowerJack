//
//  SaveHealth.swift
//  PowerJack
//
//  Counts saves that fail in a row, so the app can say when the lifter's changes aren't saved.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SaveHealth {
    static let shared = SaveHealth()

    /// Failed saves since the last one that worked.
    private(set) var failuresInARow = 0
    /// The container whose saves are failing. Any save of it that works clears the warning.
    @ObservationIgnored private weak var failingContainer: ModelContainer?

    /// One failure can be a passing clash with a sync. Two in a row are worth telling the lifter about.
    var changesAreUnsaved: Bool { failuresInARow >= 2 }

    private init() {
        Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                guard let self, let context = notification.object as? ModelContext else { continue }
                if context.container === failingContainer { recordSuccess() }
            }
        }
    }

    func recordFailure(in context: ModelContext) {
        failingContainer = context.container
        failuresInARow += 1
    }

    private func recordSuccess() {
        guard failuresInARow > 0 else { return }
        failuresInARow = 0
        failingContainer = nil
    }
}
