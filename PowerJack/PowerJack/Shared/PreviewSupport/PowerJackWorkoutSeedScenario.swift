//
//  PowerJackWorkoutSeedScenario.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftData

struct PowerJackWorkoutSeedScenario {
    let container: ModelContainer
    let workout: Workout
}

extension PowerJackSeed {
    static func emptyWorkout() -> PowerJackWorkoutSeedScenario {
        let container = makeInMemoryContainer()
        let workout = Workout(order: 0)

        container.mainContext.insert(workout)

        do {
            try container.mainContext.save()
        } catch {
            fatalError("Could not save empty workout preview data: \(error)")
        }

        return PowerJackWorkoutSeedScenario(container: container, workout: workout)
    }
}
