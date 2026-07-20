//
//  ModelContext+Save.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftData

extension ModelContext {
    func insertAndSave<Model: PersistentModel>(_ model: Model) throws {
        insert(model)

        do {
            try save()
        } catch {
            delete(model)
            throw error
        }
    }
}
