//
//  WorkoutUnlocks.swift
//  PowerJack
//
//  Completed workouts the lifter unlocked to fix what they logged. Kept in memory only, so
//  closing the app locks them all again. Nothing here is saved or synced.
//

import Observation
import OSLog
import SwiftData

@Observable
final class WorkoutUnlocks {
    /// The app's one list, so an unlock lasts until the app closes.
    static let shared = WorkoutUnlocks()

    private var unlockedIDs: Set<PersistentIdentifier> = []

    /// Unlocked and still complete, so its logged sets can be fixed.
    func isUnlocked(_ workout: Workout) -> Bool {
        workout.status == .complete && unlockedIDs.contains(workout.persistentModelID)
    }

    /// Only a completed workout can be unlocked. It stays complete.
    func unlock(_ workout: Workout) {
        guard workout.status == .complete else {
            Logger.workout.warning("Can only unlock a completed Workout.")
            return
        }
        unlockedIDs.insert(workout.persistentModelID)
    }

    func lock(_ workout: Workout) {
        unlockedIDs.remove(workout.persistentModelID)
    }
}
