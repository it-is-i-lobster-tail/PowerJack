import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ExerciseQueryModelTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try PowerJackSchema.makeModelContainer(inMemory: true)
        context = container.mainContext
        try ExerciseCatalog.seed(in: context)
    }

    /// Stands in for the on-device model with a fixed reading.
    private struct StubReader: ExerciseFiltersReading {
        let reading: ExerciseFilters?
        func filters(for text: String) async -> ExerciseFilters? { reading }
    }

    private func results(_ query: String, filters: ExerciseFilters? = nil) throws -> ExercisePickerResults {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let index = ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
        return ExercisePickerResults(exercises: exercises, index: index, query: query, filters: filters, muscles: [], mode: .add)
    }

    @Test("A stubbed reading of rear delts with no bench leaves bench lifts out and ranks reverse flies and face pulls first")
    func rearDeltsNoBench() async throws {
        let reader = StubReader(reading: ExerciseFilters(muscles: [.shoulders], movements: ["shoulder.horizontalAbduction"],
                                                         excludeSetups: [.bench]))
        let filters = try #require(await reader.filters(for: "something for rear delts that doesn't need a bench"))
        let shown = try results("something for rear delts that doesn't need a bench", filters: filters).matches

        #expect(Set(shown.prefix(2).compactMap(\.catalogID)) == ["dumbbell-reverse-fly", "cable-face-pull"])
        #expect(!shown.contains { ExerciseFilters.Setup.bench.isUsed(by: ExerciseQuery.words($0.exerciseName)) })
        #expect(filters.summary == "shoulders, rear delt, no bench")
    }

    @Test("Excluded equipment is a hard filter, and covers weighted bodyweight work and the leg press")
    func excludedEquipment() throws {
        let noBodyweight = try results("bodyweight back exercises at home", filters: ExerciseFilters(muscles: [.back], excludeEquipment: [.bodyweight]))
        #expect(!noBodyweight.matches.isEmpty)
        #expect(!noBodyweight.matches.contains { $0.equipment == .bodyweight || $0.equipment == .loadableBodyweight })

        let noMachines = try results("quads but not on a machine", filters: ExerciseFilters(muscles: [.quads], excludeEquipment: [.machine]))
        #expect(noMachines.matches.contains { $0.catalogID == "barbell-back-squat" })
        #expect(!noMachines.matches.contains { $0.catalogID == "leg-press" || $0.catalogID == "leg-extension" })
    }

    @Test("Values outside the app's lists are dropped, and a reading with nothing left is no reading")
    func unknownValuesDropped() throws {
        let filters = try #require(ExerciseFilters(
            muscles: ["shoulders", "wings"], movements: ["shoulder.horizontalAbduction", "shoulder.flap"],
            includeEquipment: ["sled", "cable"], excludeEquipment: ["barbell", "rope"], excludeSetups: ["bench", "rack"]))
        #expect(filters == ExerciseFilters(muscles: [.shoulders], movements: ["shoulder.horizontalAbduction"],
                                           includeEquipment: [.cable], excludeEquipment: [.barbell], excludeSetups: [.bench]))
        #expect(ExerciseFilters(muscles: ["wings"], movements: ["neck.spin"], includeEquipment: [], excludeEquipment: ["rope"],
                                excludeSetups: []) == nil)
        // Equipment both asked for and left out is left out.
        #expect(ExerciseFilters(includeEquipment: [.cable], excludeEquipment: [.cable]).includeEquipment.isEmpty)
    }

    @Test("Only searches of 3 or more words with thin results ask the model")
    func whenItRuns() throws {
        #expect(!ExerciseQueryModel.shouldAsk("rear delts", matches: []))
        #expect(ExerciseQueryModel.shouldAsk("rear delts no bench", matches: []))
        let strong = ExerciseSearch.Match(key: "a", score: 0.9, name: 1, meaning: 0, structure: 0, history: 0)
        #expect(!ExerciseQueryModel.shouldAsk("barbell bench press", matches: [strong, strong, strong]))
        let weak = ExerciseSearch.Match(key: "a", score: 0.4, name: 0.4, meaning: 0, structure: 0, history: 0)
        #expect(ExerciseQueryModel.shouldAsk("barbell bench press", matches: [weak, weak, weak]))

        #expect(try !results("barbell bench press").isThin)
        #expect(try !results("").isThin)
    }

    @Test("Without a reading, or after clearing it, results are the fast results")
    func clearingRestoresFastResults() throws {
        let text = "rear delts no bench"
        let fast = try results(text).matches.map(\.persistentModelID)
        let read = try results(text, filters: ExerciseFilters(movements: ["shoulder.horizontalAbduction"], excludeSetups: [.bench]))
        #expect(read.matches.map(\.persistentModelID) != fast)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let index = ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
        let byKey = Dictionary(uniqueKeysWithValues: exercises.map { ($0.searchKey, $0.persistentModelID) })
        #expect(fast == index.rank(ExerciseQuery(text)).compactMap { byKey[$0.key] })
    }

    @Test("Summary names what was read in plain words")
    func summary() {
        let filters = ExerciseFilters(muscles: [.back], movements: ["elbow.flexion"], includeEquipment: [.dumbbell],
                                      excludeEquipment: [.machine], excludeSetups: [.pullUpBar])
        #expect(filters.summary == "back, elbow flexion, dumbbell, no machine, no pull-up bar")
        #expect(ExerciseQuery("pulls").adding(filters).summary == filters.summary)
        #expect(ExerciseQuery("pulls").summary == nil)
    }

    @Test("The model's answer schema builds from the app's lists")
    func answerSchema() {
        _ = ExerciseQueryModel.Answer.generationSchema
        #expect(ExerciseFilters.movementKeys.contains("shoulder.horizontalAbduction"))
        #expect(!ExerciseFilters.equipmentNames.contains(Equipment.loadableBodyweight.rawValue))
    }
}
