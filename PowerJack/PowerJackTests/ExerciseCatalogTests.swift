import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ExerciseCatalogTests {
    @Test("Catalog entries have unique stable IDs and valid exercise fields")
    func catalogValidity() {
        let entries = ExerciseCatalog.entries
        #expect(entries.count == 63)
        #expect(Set(entries.map(\.id)).count == entries.count)
        let ids = Set(entries.map(\.id))
        for id in ["dumbbell-goblet-squat", "sliding-leg-curl", "smith-machine-squat", "smith-machine-hip-thrust", "cable-hip-abduction",
                   "hack-squat", "chest-supported-dumbbell-row", "dip", "close-grip-bench-press", "incline-dumbbell-curl", "hanging-leg-raise"] {
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

    @Test("Catalog keeps High fatigue for big lower-body lifts")
    func catalogFatigueLevels() {
        let fatigueByID = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ($0.id, $0.fatigueLevel) })
        let high = ExerciseCatalog.entries.filter { $0.fatigueLevel == .high }.map(\.id)
        #expect(Set(high) == [
            "barbell-back-squat", "barbell-front-squat", "smith-machine-squat", "hack-squat",
            "leg-press", "barbell-deadlift", "barbell-romanian-deadlift",
            "dumbbell-bulgarian-split-squat", "dumbbell-walking-lunge", "barbell-hip-thrust", "smith-machine-hip-thrust",
        ])
        #expect(fatigueByID["barbell-bench-press"] == .moderate)
        #expect(fatigueByID["barbell-overhead-press"] == .moderate)
        #expect(fatigueByID["close-grip-bench-press"] == .moderate)
        #expect(fatigueByID["push-up"] == .moderate)
        #expect(fatigueByID["lat-pulldown"] == .moderate)
        #expect(fatigueByID["dumbbell-curl"] == .low)
        #expect(fatigueByID["dumbbell-goblet-squat"] == .moderate)
        #expect(fatigueByID["cable-hip-abduction"] == .low)

        let counts = Dictionary(grouping: ExerciseCatalog.entries, by: \.fatigueLevel).mapValues(\.count)
        #expect(counts == [.high: 11, .moderate: 19, .low: 33])
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

    @Test("An upgrade moves built-in rows off a fatigue level that changed, once, and keeps the user's picks")
    func fatigueLevelUpgrade() throws {
        let suite = "ExerciseCatalogTests.fatigueLevelUpgrade"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let context = try PowerJackSchema.makeModelContainer(inMemory: true).mainContext

        // Rows as an older version seeded them, when bench, row and press were High.
        func oldRow(_ id: String, _ fatigueLevel: FatigueLevel, maxReps: Int) throws -> Exercise {
            let exercise = try #require(ExerciseCatalog.entries.first(where: { $0.id == id })).makeExercise()
            exercise.fatigueLevel = fatigueLevel
            exercise.maxReps = maxReps
            context.insert(exercise)
            return exercise
        }
        let bench = try oldRow("barbell-bench-press", .high, maxReps: 12)
        let row = try oldRow("barbell-row", .high, maxReps: 8)
        let press = try oldRow("barbell-overhead-press", .low, maxReps: 20)
        let squat = try oldRow("barbell-back-squat", .high, maxReps: 12)
        let lunge = try oldRow("dumbbell-walking-lunge", .moderate, maxReps: 15)
        try context.save()

        try ExerciseCatalog.seed(in: context, defaults: defaults)
        #expect(bench.fatigueLevel == .moderate && bench.repRange == 5...15)
        #expect(bench.restDuration == RestLength.standard.duration)
        // The user's own max reps and fatigue level stay.
        #expect(row.fatigueLevel == .moderate && row.repRange == 5...8)
        #expect(press.fatigueLevel == .low && press.repRange == 5...20)
        #expect(squat.fatigueLevel == .high && squat.repRange == 5...12)
        // Lunges moved up to High.
        #expect(lunge.fatigueLevel == .high && lunge.repRange == 5...12)

        // After the move, a level the user picks again stays.
        bench.fatigueLevel = .high
        try ExerciseCatalog.seed(in: context, defaults: defaults)
        #expect(bench.fatigueLevel == .high)
    }

    @Test("A new device moves rows iCloud brings in from an older version on its next launch")
    func fatigueLevelUpgradeAfterSync() throws {
        let suite = "ExerciseCatalogTests.fatigueLevelUpgradeAfterSync"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let context = try PowerJackSchema.makeModelContainer(inMemory: true).mainContext

        // First launch seeds an empty store.
        try ExerciseCatalog.seed(in: context, defaults: defaults)
        #expect(defaults.object(forKey: ExerciseCatalog.fatigueLevelsRevisionKey) == nil)

        // The older version's bench syncs in. It's older, so it survives the dedupe.
        let synced = ExerciseCatalog.entries[0].makeExercise()
        synced.fatigueLevel = .high
        synced.maxReps = 12
        synced.createdAtValue = .distantPast
        context.insert(synced)
        try context.save()

        try ExerciseCatalog.seed(in: context, defaults: defaults)
        let benches = try context.fetch(FetchDescriptor<Exercise>()).filter { $0.catalogID == "barbell-bench-press" }
        #expect(benches.count == 1)
        #expect(benches.first?.fatigueLevel == .moderate)
        #expect(defaults.integer(forKey: ExerciseCatalog.fatigueLevelsRevisionKey) == ExerciseCatalog.fatigueLevelsRevision)
    }
}
