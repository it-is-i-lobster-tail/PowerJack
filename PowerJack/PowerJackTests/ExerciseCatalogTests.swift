import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ExerciseCatalogTests {
    @Test("Catalog entries have unique stable IDs and valid exercise fields")
    func catalogValidity() {
        let entries = ExerciseCatalog.entries
        #expect(entries.count == 57)
        #expect(Set(entries.map(\.id)).count == entries.count)
        let ids = Set(entries.map(\.id))
        for id in ["dumbbell-goblet-squat", "sliding-leg-curl", "smith-machine-squat", "smith-machine-hip-thrust", "cable-hip-abduction"] {
            #expect(ids.contains(id), "\(id)")
        }
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
        #expect(fatigueByID["smith-machine-squat"] == .high)
        #expect(fatigueByID["dumbbell-goblet-squat"] == .moderate)
        #expect(fatigueByID["cable-hip-abduction"] == .low)

        let counts = Dictionary(grouping: ExerciseCatalog.entries, by: \.fatigueLevel).mapValues(\.count)
        #expect(counts == [.high: 13, .moderate: 13, .low: 31])
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
        #expect(stored.count == ExerciseCatalog.entries.count)
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
        // The renamed catalog entry is kept, and the custom and legacy exercises are extra.
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == ExerciseCatalog.entries.count + 2)
        #expect(existing.exerciseName == "Existing Catalog Name")
        #expect(existing.persistentModelID == existingID)
        #expect(custom.userCreated && custom.catalogID == nil)
        #expect(custom.exerciseName == ExerciseCatalog.entries[1].name)
        #expect(custom.exerciseEquipment == .bodyweight && custom.primaryMuscleFocus == .abs)
        #expect(legacy.catalogID == nil && legacy.exerciseName == "Legacy Exercise")
    }

    @Test("Built-in exercises only take rep range and fatigue edits")
    func builtInExerciseEdits() {
        // The flag controls editing, including older records without a catalog ID.
        for exercise in [ExerciseCatalog.entries[0].makeExercise(), Exercise(
            exerciseName: "Legacy Exercise", exerciseEquipment: .barbell, primaryMuscleFocus: .chest
        )] {
            let originalName = exercise.exerciseName
            let originalSecondary = exercise.secondaryMuscles
            var draft = ExerciseDraft(exercise: exercise)
            #expect(draft.isBuiltIn)
            draft.name = "Changed Exercise"
            draft.equipment = .cable
            draft.primaryMuscle = .back
            draft.secondaryMuscles = [.biceps]
            draft.minReps = 6
            draft.maxReps = 7
            draft.fatigueLevel = .low
            #expect(draft.apply(to: exercise))
            #expect(exercise.exerciseName == originalName)
            #expect(exercise.exerciseEquipment == .barbell)
            #expect(exercise.primaryMuscleFocus == .chest)
            #expect(exercise.secondaryMuscles == originalSecondary)
            #expect(exercise.repRange == 6...7)
            #expect(exercise.fatigueLevel == .low)
        }
    }

    @Test("Built-in exercises still refuse an invalid rep range")
    func builtInInvalidRepRange() {
        let exercise = ExerciseCatalog.entries[0].makeExercise()
        let originalRange = exercise.repRange
        var draft = ExerciseDraft(exercise: exercise)
        draft.minReps = 12
        draft.maxReps = 8
        #expect(!draft.canSave)
        #expect(!draft.apply(to: exercise))
        #expect(exercise.repRange == originalRange)
    }

    @Test("Catalog exercises use 5 reps up to their fatigue level's default max")
    func catalogRepRanges() {
        for entry in ExerciseCatalog.entries {
            let exercise = entry.makeExercise()
            #expect(exercise.repRange == 5...entry.fatigueLevel.defaultMaxReps, "\(entry.id)")
            #expect(!entry.secondaryMuscles.contains(entry.primaryMuscle), "\(entry.id)")
        }
    }

    @Test("Seeding keeps the user's rep range and fatigue on catalog rows")
    func backfill() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let entry = ExerciseCatalog.entries[0]
        // A catalog row the user renamed and tuned, with stale secondary muscles.
        let tuned = Exercise(
            exerciseName: "Renamed Bench",
            exerciseEquipment: entry.equipment,
            primaryMuscleFocus: entry.primaryMuscle,
            minReps: 8,
            maxReps: 12,
            fatigueLevel: .low
        )
        tuned.catalogID = entry.id
        context.insert(tuned)
        try context.save()

        try ExerciseCatalog.seed(in: context)

        #expect(Set(tuned.secondaryMuscles) == Set(entry.secondaryMuscles))
        #expect(tuned.exerciseName == "Renamed Bench")
        #expect(tuned.repRange == 8...12)
        #expect(tuned.fatigueLevel == .low)
    }
}
