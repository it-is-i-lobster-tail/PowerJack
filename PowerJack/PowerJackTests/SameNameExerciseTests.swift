//
//  SameNameExerciseTests.swift
//  PowerJackTests
//
//  Built-in machines show their name ("Smith Machine"), and the lifter's own exercise named exactly
//  like a built-in one becomes it without losing a set, an import, saved history or a chart.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct SameNameExerciseTests {
    /// A context must not outlive its container.
    private static var kept: [ModelContainer] = []

    private func freshDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "SameNameExerciseTests-\(UUID().uuidString)"))
    }

    private func memoryContext() -> ModelContext {
        let container = PowerJackSeed.makeInMemoryContainer()
        Self.kept.append(container)
        return container.mainContext
    }

    private func catalog(_ id: String, in context: ModelContext) throws -> [Exercise] {
        try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == id }))
    }

    private func own(_ name: String, in context: ModelContext, createdAt: Date = Date(timeIntervalSinceReferenceDate: 600_000_000)) -> Exercise {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: .barbell, primaryMuscleFocus: .back,
                                userCreated: true, minReps: 7, maxReps: 11, fatigueLevel: .low)
        exercise.customRestTime = 95
        exercise.createdAtValue = createdAt
        exercise.assignSyncID()
        context.insert(exercise)
        return exercise
    }

    /// A program workout with `count` logged sets of `exercise`.
    private func logSets(_ count: Int, of exercise: Exercise, in context: ModelContext) throws -> [WorkoutSet] {
        let workout = Workout(order: 0)
        let row = try #require(workout.addWorkoutExercise(exercise: exercise))
        for index in 0..<count {
            _ = row.addSet(plannedReps: 8, plannedWeightTenthsPounds: 1350 + index * 50)
        }
        context.insert(workout)
        workout.startAndCascade()
        let sets = row.workoutSets
        for (index, set) in sets.enumerated() {
            set.weightTenthsPounds = 1350 + index * 50
            set.reps = 8
            set.complete()
        }
        try context.save()
        return sets
    }

    // MARK: Equipment names

    @Test("Built-in rows seeded before their machine had a name get it, unless the type changed, once")
    func fillsEquipmentNames() throws {
        let context = memoryContext()
        try ExerciseCatalog.seed(in: context)
        let squat = try #require(try catalog("smith-machine-squat", in: context).first)
        let legCurl = try #require(try catalog("seated-leg-curl", in: context).first)
        let lying = try #require(try catalog("lying-leg-curl", in: context).first)
        #expect(squat.equipmentDisplayName == "Smith Machine")
        #expect(legCurl.equipmentDisplayName == "Seated Leg Curl" && lying.equipmentDisplayName == "Lying Leg Curl")

        // Rows an older version seeded have no name; one of them the lifter moved to another type.
        squat.customEquipmentName = nil
        legCurl.customEquipmentName = nil
        legCurl.equipment = .cable
        let sets = try logSets(3, of: squat, in: context)
        let restBefore = squat.restDuration

        #expect(try ExerciseCatalog.removeDuplicates(in: context))
        #expect(squat.customEquipmentName == "Smith Machine" && squat.equipment == .machine)
        #expect(legCurl.customEquipmentName == nil && legCurl.equipmentDisplayName == "Cable")
        #expect(sets.allSatisfy { $0.status == .complete && $0.reps == 8 })
        #expect(squat.restDuration == restBefore && squat.repRange == Exercise.defaultMinReps...squat.fatigueLevel.defaultMaxReps)

        try context.save()
        #expect(try !ExerciseCatalog.removeDuplicates(in: context))
    }

    @Test("Every catalog name fits the equipment name limit and no two built-ins read as the same name")
    func catalogNames() {
        for entry in ExerciseCatalog.entries {
            if let name = entry.equipmentName { #expect(name.count <= CustomEquipment.nameLimit, "\(name)") }
        }
        #expect(ExerciseCatalog.entriesByMatchingName.count == ExerciseCatalog.entries.count)
    }

    @Test("The equipment list groups built-in equipment by type, plain type first")
    func equipmentByType() throws {
        let machine = try #require(ExerciseCatalog.equipmentOptionsByType.first { $0.base == .machine })
        #expect(machine.options.first?.name == nil)
        let names = Set(machine.options.compactMap(\.name))
        #expect(names.isSuperset(of: ["Smith Machine", "Hack Squat", "Leg Extension", "Seated Leg Curl", "Lying Leg Curl", "Pec Deck",
                                      "Belt Squat", "Landmine", "Hip Adduction"]))
        #expect(ExerciseCatalog.equipmentOptionsByType.map(\.base) == Equipment.allCases)
        #expect(ExerciseCatalog.equipmentOptionsByType.flatMap(\.options).count == ExerciseCatalog.equipmentOptions.count)
    }

    @Test("Searching smith finds the Smith machine lifts")
    func smithSearch() throws {
        let context = memoryContext()
        try ExerciseCatalog.seed(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let index = ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
        let results = ExercisePickerResults(exercises: exercises, index: index, query: "smith", muscles: [], mode: .add)
        let names = Set(results.matches.map(\.exerciseName))
        #expect(names.isSuperset(of: ["Smith Machine Squat", "Smith Machine Hip Thrust"]))
    }

    // MARK: Own copies

    @Test("An own exercise named like a built-in becomes it in place, keeping its sets and settings")
    func ownCopyBecomesBuiltIn() throws {
        let context = memoryContext()
        let mine = own("smith machine squat", in: context)
        let template = TemplateExercise(exercise: mine, order: 0)
        context.insert(template)
        let sets = try logSets(4, of: mine, in: context)
        let id = mine.persistentModelID
        let defaults = try freshDefaults()

        #expect(try ExerciseCatalog.adoptSameNameCopies(in: context, defaults: defaults) == ["Smith Machine Squat"])
        try ExerciseCatalog.seed(in: context)

        let squats = try catalog("smith-machine-squat", in: context)
        #expect(squats.count == 1 && squats.first?.persistentModelID == id)
        #expect(mine.exerciseName == "Smith Machine Squat" && !mine.userCreated && mine.equipment == .machine)
        #expect(mine.customEquipmentName == "Smith Machine" && mine.primaryMuscleFocus == .quads)
        #expect(mine.repRange == 7...11 && mine.fatigueLevel == .low && mine.customRestTime == 95)
        #expect(template.exercise === mine)
        #expect(sets.allSatisfy { $0.workoutExerciseValue?.exercise === mine && $0.status == .complete })
        #expect(sets.map(\.weightTenthsPounds) == [1350, 1400, 1450, 1500])

        // Once per device: an own lift made under a built-in name afterwards stays the lifter's.
        let later = own("Hack Squat", in: context)
        try context.save()
        #expect(try ExerciseCatalog.adoptSameNameCopies(in: context, defaults: defaults).isEmpty)
        try ExerciseCatalog.seed(in: context)
        #expect(later.catalogID == nil && later.userCreated)
    }

    @Test("With the built-in there too, the own copy merges into one row and no set is lost")
    func bothMerge() throws {
        let context = memoryContext()
        try ExerciseCatalog.seed(in: context)
        let builtIn = try #require(try catalog("pec-deck", in: context).first)
        let builtInSets = try logSets(2, of: builtIn, in: context)
        // Made before this version seeded Pec Deck, so it is the older row.
        let mine = own("PEC DECK", in: context)
        let mySets = try logSets(3, of: mine, in: context)
        let notIt = own("Pec Deck Reverse", in: context)
        try context.save()

        try ExerciseCatalog.adoptSameNameCopies(in: context, defaults: try freshDefaults())
        try ExerciseCatalog.seed(in: context)

        let rows = try catalog("pec-deck", in: context)
        #expect(rows.count == 1)
        let survivor = try #require(rows.first)
        #expect(survivor === mine && survivor.exerciseName == "Pec Deck" && survivor.customEquipmentName == "Pec Deck")
        #expect((builtInSets + mySets).allSatisfy { $0.workoutExerciseValue?.exercise === survivor && $0.status == .complete })
        #expect(try context.fetch(FetchDescriptor<WorkoutExercise>()).allSatisfy { $0.exercise != nil })
        #expect(notIt.catalogID == nil && notIt.userCreated)
        let own = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.userCreatedValue }))
        #expect(own.map(\.exerciseName) == ["Pec Deck Reverse"])
    }

    @Test("An own Smith Machine Row from before the Smith lifts were built in becomes the new built-in")
    func newSmithBuiltInAbsorbsOwnCopy() throws {
        let context = memoryContext()
        let defaults = try freshDefaults()
        // The device already ran the first pass, before the Smith lifts shipped.
        defaults.set(1, forKey: ExerciseCatalog.sameNameRevisionKey)
        let mine = own("Smith Machine Row", in: context)
        let sets = try logSets(3, of: mine, in: context)

        #expect(try ExerciseCatalog.adoptSameNameCopies(in: context, defaults: defaults) == ["Smith Machine Row"])
        try ExerciseCatalog.seed(in: context)

        let rows = try catalog("smith-machine-row", in: context)
        #expect(rows.count == 1 && rows.first === mine)
        #expect(mine.customEquipmentName == "Smith Machine" && mine.equipment == .machine && mine.repRange == 7...11)
        #expect(sets.allSatisfy { $0.workoutExerciseValue?.exercise === mine && $0.status == .complete })
    }

    @Test("Searching smith bench finds the Smith bench press first")
    func smithBenchSearch() throws {
        let context = memoryContext()
        try ExerciseCatalog.seed(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let index = ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
        let results = ExercisePickerResults(exercises: exercises, index: index, query: "smith bench", muscles: [], mode: .add)
        #expect(results.matches.first?.catalogID == "smith-machine-bench-press")
        #expect(Set(results.matches.prefix(4).compactMap(\.catalogID)).isSuperset(of: ["smith-machine-bench-press", "smith-machine-incline-bench-press"]))
    }

    @Test("An own T-Bar Row from before it was built in becomes the built-in on the landmine")
    func newTBarRowAbsorbsOwnCopy() throws {
        let context = memoryContext()
        let defaults = try freshDefaults()
        defaults.set(2, forKey: ExerciseCatalog.sameNameRevisionKey)
        let mine = own("t-bar row", in: context)
        let sets = try logSets(2, of: mine, in: context)

        #expect(try ExerciseCatalog.adoptSameNameCopies(in: context, defaults: defaults) == ["T-Bar Row"])
        try ExerciseCatalog.seed(in: context)

        #expect(try catalog("t-bar-row", in: context).count == 1)
        #expect(mine.catalogID == "t-bar-row" && mine.customEquipmentName == "Landmine" && mine.equipment == .machine)
        #expect(sets.allSatisfy { $0.workoutExerciseValue?.exercise === mine && $0.status == .complete })
    }

    @Test("Lifter shorthand finds the new lifts", arguments: [
        ("t bar row", "t-bar-row"), ("tbar row", "t-bar-row"), ("landmine press", "landmine-press"),
        ("ssb squat", "safety-squat-bar-squat"), ("belt squat", "belt-squat"), ("ghr", "glute-ham-raise"),
        ("pallof", "pallof-press"), ("seal row", "barbell-seal-row"),
    ])
    func newLiftSearch(query: String, id: String) throws {
        let context = memoryContext()
        try ExerciseCatalog.seed(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let index = ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
        let results = ExercisePickerResults(exercises: exercises, index: index, query: query, muscles: [], mode: .add)
        #expect(results.matches.first?.catalogID == id, "\(query): \(results.matches.prefix(3).map(\.exerciseName))")
    }

    @Test("A built-in the lifter renamed keeps their own lift under its old name apart")
    func renamedBuiltInStaysApart() throws {
        let context = memoryContext()
        try ExerciseCatalog.seed(in: context)
        let builtIn = try #require(try catalog("hack-squat", in: context).first)
        builtIn.exerciseName = "Sled Squat"
        let mine = own("Hack Squat", in: context)
        try context.save()

        #expect(try ExerciseCatalog.adoptSameNameCopies(in: context, defaults: try freshDefaults()).isEmpty)
        #expect(mine.catalogID == nil && mine.userCreated)
    }

    @Test("The watch leaves own copies to the iPhone")
    func watchDoesNothing() throws {
        let context = memoryContext()
        let mine = own("Pec Deck", in: context)
        try context.save()
        let previous = SyncDevice.current
        SyncDevice.current = SyncDevice.watch
        defer { SyncDevice.current = previous }
        #expect(try ExerciseCatalog.adoptSameNameCopies(in: context, defaults: try freshDefaults()).isEmpty)
        #expect(mine.catalogID == nil)
    }

    @Test("Two copies saved at the same moment: every device keeps the same one, whatever order it reads them in")
    func tieBreakIsTheSameEverywhere() {
        let date = Date.distantPast
        let seeded = Exercise(exerciseName: "Pec Deck", exerciseEquipment: .machine, primaryMuscleFocus: .chest)
        let adoptedA = Exercise(exerciseName: "Pec Deck", exerciseEquipment: .machine, primaryMuscleFocus: .chest)
        let adoptedB = Exercise(exerciseName: "Pec Deck", exerciseEquipment: .machine, primaryMuscleFocus: .chest)
        adoptedA.syncIDValue = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")
        adoptedB.syncIDValue = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")
        for row in [seeded, adoptedA, adoptedB] { row.createdAtValue = date }
        let orders = [[seeded, adoptedA, adoptedB], [adoptedB, adoptedA, seeded], [adoptedA, seeded, adoptedB]]
        for order in orders {
            #expect(order.sorted(by: ExerciseCatalog.survivesBefore).map(\.syncIDValue) == [nil, adoptedA.syncIDValue, adoptedB.syncIDValue])
        }
    }

    @Test("History, imports, the lift record and charts follow an own copy to its built-in")
    func historyFollows() throws {
        let url = URL.temporaryDirectory.appending(path: "SameName-\(UUID().uuidString).store")
        let configuration = ModelConfiguration(schema: PowerJackSchema.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: PowerJackSchema.schema, configurations: [configuration])
        Self.kept.append(container)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)
        try SimulatorTrainingHistory.populate(in: context, now: ChartSearchFixture.today)
        try HistoryArchive.saveEndedPrograms(in: context)
        try context.save()

        // The training history's own lift, as if the lifter had named it like a built-in.
        let mine = try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.userCreatedValue })).first)
        mine.exerciseName = "Lateral Lunge"
        mine.assignSyncID()
        let oldKey = try #require(mine.syncKey)
        let builtIn = try #require(try catalog("lateral-lunge", in: context).first)
        let newKey = try #require(builtIn.syncKey)

        let imported = ImportedSet()
        imported.sourceKey = "b.1"
        imported.trainingDay = "2024-03-04"
        imported.exerciseKey = oldKey
        imported.exerciseName = mine.exerciseName
        imported.reps = 10
        imported.weightTenthsPounds = 950
        context.insert(imported)
        let deleted = try #require(try context.fetch(FetchDescriptor<Program>()).first { $0.status != .active && $0.programWeeks.contains {
            $0.workouts.contains { $0.workoutExercises.contains { $0.exercise === mine } }
        } })
        try HistoryArchive.programWillBeDeleted(deleted, in: context)
        context.delete(deleted)
        var state = StrengthState()
        state.lifts[StrengthLifts.key(for: mine)] = StrengthLiftRecord(e1rmKg: 70)
        context.insert(StrengthLog(date: .now.addingTimeInterval(-60), state: state))
        try context.save()

        let defaults = try freshDefaults()
        var options = StudyOptions()
        options.exerciseKeys = [oldKey]
        let study = TrainingStudy.allCases[0]
        defaults.set(try FavoriteCharts(data: Data()).toggling(study, options: options, name: "Lunge"), forKey: FavoriteCharts.storageKey)

        let before = StudyHistory(context: context, unit: .pounds, today: ChartSearchFixture.today)
        let mySets = logged(oldKey, in: before)
        let builtInSets = logged(newKey, in: before)
        #expect(mySets > 0)

        #expect(try ExerciseCatalog.adoptSameNameCopies(in: context, defaults: defaults) == ["Lateral Lunge"])
        try ExerciseCatalog.seed(in: context)

        #expect(try catalog("lateral-lunge", in: context).count == 1)
        #expect(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.userCreatedValue })).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutExercise>()).allSatisfy { $0.exercise != nil })
        #expect(imported.exerciseKey == newKey && imported.exerciseName == "Lateral Lunge")
        let saved = try HistoryArchive.records(in: context)
        #expect(!saved.contains { $0.row.exerciseKey == oldKey })
        #expect(saved.contains { $0.row.exerciseKey == newKey && $0.row.programID == deleted.syncID })
        let record = try #require(try StrengthLog.latest(in: context)?.state)
        #expect(record.lifts["lateral-lunge"]?.e1rmKg == 70)

        let after = StudyHistory(context: context, unit: .pounds, today: ChartSearchFixture.today)
        #expect(logged(oldKey, in: after) == 0)
        #expect(logged(newKey, in: after) == mySets + builtInSets)
        let favorites = try #require(defaults.data(forKey: FavoriteCharts.storageKey))
        let favorite = try #require(FavoriteCharts(data: favorites).charts.first)
        #expect(favorite.options.exerciseKeys == [newKey])
    }

    private func logged(_ key: String, in history: StudyHistory) -> Int {
        history.sessions.filter { $0.key == key }.reduce(0) { total, session in
            total + (session.sets + session.warmups).count { $0.status == .complete }
        }
    }
}
