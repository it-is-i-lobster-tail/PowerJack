//
//  PowerJackSeed.swift
//  PowerJack
//
//  Created by Codex on 7/2/26.
//

import SwiftData

enum PowerJackSeed {
    static func makeInMemoryContainer() -> ModelContainer {
        do {
            return try PowerJackSchema.makeModelContainer(inMemory: true)
        } catch {
            fatalError("Could not create in-memory ModelContainer: \(error)")
        }
    }
}
