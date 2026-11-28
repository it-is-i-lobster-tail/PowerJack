//
//  CustomEquipment+Delete.swift
//  PowerJack
//
//  Deleting the lifter's own equipment, moving any exercises that use it to other equipment first.
//

import OSLog
import SwiftData

extension CustomEquipment {
    /// The lifter's own exercises that use this equipment. Built-in exercises can name equipment
    /// of their own, like EZ Bar, so they never count, even when the names match.
    func exercises(in context: ModelContext) throws -> [Exercise] {
        let name: String? = self.name
        return try context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.userCreatedValue && $0.customEquipmentName == name }
        ))
    }

    /// Moves every exercise that uses this equipment to `base`, named `customName` when that's other
    /// equipment of the lifter's, then deletes this equipment and saves. Logged sets stay with their exercises.
    /// Refuses to delete equipment that exercises still use when no replacement is given.
    func delete(movingExercisesTo base: Equipment?, named customName: String? = nil, in context: ModelContext) throws {
        let users = try exercises(in: context)
        if let base {
            for exercise in users {
                exercise.equipment = base
                exercise.customEquipmentName = customName
            }
        } else if !users.isEmpty {
            Logger.persistence.warning("Refused to delete equipment that \(users.count) exercises use")
            return
        }
        context.delete(self)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
