//
//  HistoryChangesWait.swift
//  PowerJackTests
//
//  `HistoryChanges` counts a burst of saves once the store has been quiet for `HistoryChanges.settle`.
//  A fixed sleep of a few settles is often not enough on a busy CI runner, so tests wait for the count.
//

import Foundation
@testable import PowerJack

@MainActor
enum HistoryChangesWait {
    /// Waits until the saves just made have been counted, or `timeout` passes. Call it right after saving.
    static func counted(timeout: Duration = .seconds(10)) async {
        let before = HistoryChanges.shared.count
        let deadline = ContinuousClock.now + timeout
        while HistoryChanges.shared.count == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
