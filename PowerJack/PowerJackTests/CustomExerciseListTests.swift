import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct CustomExerciseListTests {
    let container = PowerJackSeed.makeInMemoryContainer()
    let exercises: [Exercise]
    let index: ExerciseSearch.Index
    let imported: Exercise
    let madeHere: Exercise
    let importedKeys: Set<String>

    init() throws {
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        imported = Exercise(exerciseName: "Hammer Strength Row", exerciseEquipment: .machine,
                            primaryMuscleFocus: .back, userCreated: true)
        madeHere = Exercise(exerciseName: "Friday Pec Squeeze", exerciseEquipment: .machine,
                            primaryMuscleFocus: .chest, userCreated: true)
        for exercise in [imported, madeHere] {
            exercise.assignSyncID()
            context.insert(exercise)
        }
        let set = ImportedSet()
        set.sourceKey = "2025-01-02.Hammer Row.1"
        set.trainingDay = "2025-01-02"
        set.sourceExercise = "Hammer Row"
        set.exerciseKey = try #require(imported.syncKey)
        set.exerciseName = imported.exerciseName
        context.insert(set)
        try context.save()

        exercises = try context.fetch(FetchDescriptor<Exercise>())
        index = ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
        importedKeys = CustomExerciseOrigin.importedKeys(in: context)
    }

    private func shown(_ origin: CustomExerciseOrigin, _ query: String = "") -> [String] {
        CustomExerciseOrigin.shown(exercises, origin: origin, importedKeys: importedKeys, query: query, index: index)
            .map(\.exerciseName)
    }

    @Test func listsOnlyOwnExercisesByName() {
        #expect(shown(.all) == ["Friday Pec Squeeze", "Hammer Strength Row"])
    }

    @Test func filtersByImportStatus() {
        #expect(importedKeys.contains(imported.syncKey!))
        #expect(CustomExerciseOrigin.isImported(imported, importedKeys: importedKeys))
        #expect(!CustomExerciseOrigin.isImported(madeHere, importedKeys: importedKeys))
        #expect(shown(.imported) == ["Hammer Strength Row"])
        #expect(shown(.madeHere) == ["Friday Pec Squeeze"])
    }

    @Test func searchUsesTheSharedEngineAndKeepsTheFilter() {
        // Built-ins never show, however well they match.
        #expect(shown(.all, "pecs").first == "Friday Pec Squeeze")
        #expect(shown(.all, "row").first == "Hammer Strength Row")
        #expect(!shown(.all, "bench press").contains { $0.contains("Bench") })
        #expect(shown(.imported, "pec squeeze").isEmpty)
        #expect(shown(.madeHere, "pec squeeze") == ["Friday Pec Squeeze"])
    }

    @Test func searchesBeforeTheIndexIsReadyShowNothingYet() {
        let early = CustomExerciseOrigin.shown(exercises, origin: .all, importedKeys: importedKeys,
                                               query: "row", index: nil)
        #expect(early.isEmpty)
    }
}
