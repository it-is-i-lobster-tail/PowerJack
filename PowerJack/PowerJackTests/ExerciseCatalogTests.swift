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
            #expect(exercise.fatigueLevel == entry.fatigueLevel)
            #expect(ExerciseDraft(exercise: exercise).canSave)
        }
    }

    @Test("Catalog fatigue levels round borderline lifts up to the longer rest")
    func catalogFatigueLevels() {
        let fatigueByID = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ($0.id, $0.fatigueLevel) })
        #expect(fatigueByID["barbell-back-squat"] == .high)
        #expect(fatigueByID["leg-press"] == .high)
        #expect(fatigueByID["barbell-hip-thrust"] == .high)
        #expect(fatigueByID["push-up"] == .moderate)
        #expect(fatigueByID["lat-pulldown"] == .moderate)
        #expect(fatigueByID["dumbbell-curl"] == .low)

        let counts = Dictionary(grouping: ExerciseCatalog.entries, by: \.fatigueLevel).mapValues(\.count)
        #expect(counts == [.high: 10, .moderate: 11, .low: 27])
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
            let originalSecondary = exercise.secondaryMuscles
            let originalRange = exercise.repRange
            let originalFatigue = exercise.fatigueLevel
            var draft = ExerciseDraft(exercise: exercise)
            draft.name = "Changed Exercise"
            draft.equipment = .cable
            draft.primaryMuscle = .back
            draft.secondaryMuscles = [.biceps]
            draft.minReps = 3
            draft.maxReps = 4
            draft.fatigueLevel = .low
            #expect(draft.canSave)
            #expect(!draft.apply(to: exercise))
            #expect(exercise.exerciseName == originalName)
            #expect(exercise.exerciseEquipment == .barbell)
            #expect(exercise.primaryMuscleFocus == .chest)
            #expect(exercise.secondaryMuscles == originalSecondary)
            #expect(exercise.repRange == originalRange)
            #expect(exercise.fatigueLevel == originalFatigue)
        }
    }

    @Test("Catalog rep ranges stay within the app-wide limit")
    func catalogRepRanges() {
        for entry in ExerciseCatalog.entries {
            #expect(entry.minReps >= 1, "\(entry.id)")
            #expect(entry.maxReps <= Exercise.maxRepsAllowed, "\(entry.id)")
            #expect(entry.minReps <= entry.maxReps, "\(entry.id)")
            #expect(!entry.secondaryMuscles.contains(entry.primaryMuscle), "\(entry.id)")
        }
    }

    @Test("Seeding backfills progression data on existing catalog rows only")
    func backfill() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let entry = ExerciseCatalog.entries[0]
        // Simulates a row saved before rep ranges existed.
        let stale = Exercise(
            exerciseName: "Renamed Bench",
            exerciseEquipment: entry.equipment,
            primaryMuscleFocus: entry.primaryMuscle
        )
        stale.catalogID = entry.id
        let custom = Exercise(
            exerciseName: "Custom",
            exerciseEquipment: .cable,
            primaryMuscleFocus: .back,
            userCreated: true,
            minReps: 3,
            maxReps: 5,
            fatigueLevel: .low
        )
        context.insert(stale)
        context.insert(custom)
        try context.save()
        // Rows saved before fatigue levels existed migrate to the default.
        #expect(stale.fatigueLevel == Exercise.defaultFatigueLevel)

        try ExerciseCatalog.seed(in: context)

        #expect(stale.repRange == entry.minReps...entry.maxReps)
        #expect(Set(stale.secondaryMuscles) == Set(entry.secondaryMuscles))
        #expect(stale.fatigueLevel == entry.fatigueLevel)
        #expect(stale.fatigueLevel == .high)
        #expect(stale.exerciseName == "Renamed Bench")
        #expect(custom.repRange == 3...5)
        #expect(custom.fatigueLevel == .low)
    }
}
