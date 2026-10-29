//
//  Workout+Summary.swift
//  PowerJack
//
//  Totals shown on the summary screen after a workout is finished.
//

import Foundation

/// Completed sets for one muscle in a workout.
struct MuscleSetCount: Identifiable, Equatable {
    let muscle: Muscle
    let sets: Double

    var id: Muscle { muscle }
}

extension Workout {
    /// Completed working sets per muscle, most sets first, counted like the Volume tab:
    /// 1 for the primary muscle and 0.5 for each secondary.
    /// Warmups and muscles with no completed sets are left out.
    var completedSetsByMuscle: [MuscleSetCount] {
        loggedSetsByMuscle
            .filter { $0.value > 0 }
            .map { MuscleSetCount(muscle: $0.key, sets: $0.value) }
            .sorted { lhs, rhs in
                if lhs.sets != rhs.sets { return lhs.sets > rhs.sets }
                // Ties keep the catalog's muscle order so the list doesn't shuffle.
                return Muscle.allCases.firstIndex(of: lhs.muscle)! < Muscle.allCases.firstIndex(of: rhs.muscle)!
            }
    }
}
