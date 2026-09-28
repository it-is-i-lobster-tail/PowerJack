import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ExerciseCatalogTests {
    @Test("Catalog entries have unique stable IDs and valid exercise fields")
    func catalogValidity() {
        let entries = ExerciseCatalog.entries
        #expect(entries.count == 48)
        #expect(Set(entries.map(\.id)).count == entries.count)
        #expect(Set(entries.map(\.primaryMuscle)) == Set(Muscle.allCases))
        for entry in entries {
            let exercise = entry.makeExercise()
            #expect(!entry.id.isEmpty)
            #expect(!exercise.userCreated)
            #expect(exercise.catalogID == entry.id)
            #expect(ExerciseDraft(exercise: exercise).canSave)
        }
    }

    @Test("Seeding saves the complete catalog and is idempotent")
    func seedAndRepeat() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Exercise>()) == 0)
        try ExerciseCatalog.seed(in: container.mainContext)
        let first = try container.mainContext.fetch(FetchDescriptor<Exercise>())
        let originalIDs = Set(first.map(\.persistentModelID))
        try ExerciseCatalog.seed(in: container.mainContext)

        // A new context proves that seeding explicitly saved the inserts.
        let stored = try ModelContext(container).fetch(FetchDescriptor<Exercise>())
        #expect(stored.count == 48)
        #expect(Set(stored.map(\.persistentModelID)) == originalIDs)
        #expect(Set(stored.compactMap(\.catalogID)) == Set(ExerciseCatalog.entries.map(\.id)))
        #expect(stored.allSatisfy { !$0.userCreated })
    }

    @Test("Partial catalogs are completed without overwriting existing or custom exercises")
    func partialCatalog() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let existing = ExerciseCatalog.entries[0].makeExercise()
        existing.exerciseName = "Existing Catalog Name"
        let custom = Exercise(
            exerciseName: ExerciseCatalog.entries[1].name,
            exerciseEquipment: .bodyweight,
            primaryMuscleFocus: .abs,
            userCreated: true
        )
        let legacy = Exercise(exerciseName: "Legacy Exercise", exerciseEquipment: .cable, primaryMuscleFocus: .back)
        context.insert(existing)
        context.insert(custom)
        context.insert(legacy)
        try context.save()
        let existingID = existing.persistentModelID

        try ExerciseCatalog.seed(in: context)
        try ExerciseCatalog.seed(in: context)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 50)
        #expect(existing.exerciseName == "Existing Catalog Name")
        #expect(existing.persistentModelID == existingID)
        #expect(custom.userCreated && custom.catalogID == nil)
        #expect(custom.exerciseName == ExerciseCatalog.entries[1].name)
        #expect(custom.exerciseEquipment == .bodyweight && custom.primaryMuscleFocus == .abs)
        #expect(legacy.catalogID == nil && legacy.exerciseName == "Legacy Exercise")
    }

    @Test("Exercise drafts refuse all changes to non-user-created exercises")
    func readOnlyExercises() {
        // The flag controls editing, including older records without a catalog ID.
        for exercise in [ExerciseCatalog.entries[0].makeExercise(), Exercise(
            exerciseName: "Legacy Exercise", exerciseEquipment: .barbell, primaryMuscleFocus: .chest
        )] {
            let originalName = exercise.exerciseName
            var draft = ExerciseDraft(exercise: exercise)
            draft.name = "Changed Exercise"
            draft.equipment = .cable
            draft.primaryMuscle = .back
            draft.secondaryMuscles = [.biceps]
            #expect(draft.canSave)
            #expect(!draft.apply(to: exercise))
            #expect(exercise.exerciseName == originalName)
            #expect(exercise.exerciseEquipment == .barbell)
            #expect(exercise.primaryMuscleFocus == .chest)
            #expect(exercise.secondaryMuscles.isEmpty)
        }
    }
}
