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
    let sets: Int

    var id: Muscle { muscle }
}

extension Workout {
    /// Completed working sets per primary muscle, most sets first.
    /// Warmups and muscles with no completed sets are left out.
    var completedSetsByMuscle: [MuscleSetCount] {
        var setsByMuscle: [Muscle: Int] = [:]
        for workoutExercise in workoutExercises {
            guard let muscle = workoutExercise.exercise?.primaryMuscleFocus else { continue }
            setsByMuscle[muscle, default: 0] += workoutExercise.completedWorkingSets
        }

        return setsByMuscle
            .filter { $0.value > 0 }
            .map { MuscleSetCount(muscle: $0.key, sets: $0.value) }
            .sorted { lhs, rhs in
                if lhs.sets != rhs.sets { return lhs.sets > rhs.sets }
                // Ties keep the catalog's muscle order so the list doesn't shuffle.
                return Muscle.allCases.firstIndex(of: lhs.muscle)! < Muscle.allCases.firstIndex(of: rhs.muscle)!
            }
    }
}
