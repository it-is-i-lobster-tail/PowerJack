import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ExercisePickerTests {
    let container = PowerJackSeed.makeInMemoryContainer()
    let exercises: [Exercise]
    let index: ExerciseChartSearch.Index
    let bench: Exercise

    init() throws {
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        context.insert(Exercise(exerciseName: "Friday pec squeeze", exerciseEquipment: .machine,
                                primaryMuscleFocus: .chest, userCreated: true))
        try context.save()
        exercises = try context.fetch(FetchDescriptor<Exercise>())
        index = ExerciseChartSearch.Index(exercises.map(ExerciseChartSearch.Document.init))
        let all = exercises
        bench = try #require(all.first { $0.catalogID == "barbell-bench-press" })
    }

    private func results(_ query: String, _ mode: ExercisePickerMode = .add, muscles: Set<Muscle> = []) -> ExercisePickerResults {
        ExercisePickerResults(exercises: exercises, index: index, query: query, muscles: muscles, mode: mode)
    }

    @Test func benchAlternatives() {
        let mode = ExercisePickerMode.substitute(WorkoutExercise(exercise: bench, order: 0))
        let suggestions = results("", mode)
        let ids = suggestions.suggested.compactMap(\.catalogID)
        #expect(ids.count == 3)
        #expect(ids.contains("dumbbell-bench-press"))
        #expect(ids.contains("incline-dumbbell-bench-press"))
        #expect(!ids.contains("incline-barbell-bench-press"))
        #expect(results("", .change(bench)).suggested.contains { $0.catalogID == "incline-barbell-bench-press" })
        let options = suggestions.suggested + suggestions.named
        #expect(Set(options.map(\.persistentModelID)).count == exercises.count - 1)
        #expect(!options.contains { $0 === bench })
        #expect(options.contains { $0.userCreated })

        let squat = results("squat", mode)
        #expect(squat.suggested.count == 3)
        #expect(squat.suggested.allSatisfy { $0.exerciseName.lowercased().contains("squat") })
        #expect(squat.named.allSatisfy { $0.exerciseName.lowercased().contains("squat") })
        let barbell = results("barbell bench", mode)
        #expect(barbell.suggested.first?.catalogID == "incline-barbell-bench-press")
        #expect(barbell.suggested.allSatisfy { $0.equipment == .barbell })
    }

    @Test func addSearchAndMuscleFilters() {
        let all = results("")
        #expect(all.suggested.isEmpty)
        #expect(all.named.count == exercises.count)
        let pecs = results("pecs")
        #expect(pecs.suggested.count == 3)
        #expect(pecs.suggested.allSatisfy { $0.primaryMuscleFocus == .chest })
        #expect(pecs.named.isEmpty)
        let custom = results("Friday pec squeeze")
        #expect(custom.suggested.map(\.exerciseName) == ["Friday pec squeeze"])
        #expect(custom.named.isEmpty)
        #expect(results("peanut butter").isEmpty)

        let muscles: Set<Muscle> = [.triceps, .quads]
        let filtered = results("", muscles: muscles).named
        let primary = filtered.prefix { muscles.contains($0.primaryMuscleFocus) }
        let secondary = filtered.dropFirst(primary.count)
        #expect(Set(primary.map(\.primaryMuscleFocus)) == muscles)
        #expect(secondary.contains { $0 === bench })
        #expect(secondary.allSatisfy { !muscles.contains($0.primaryMuscleFocus) && !muscles.isDisjoint(with: $0.secondaryMuscles) })
        let presses = results("bench press", muscles: [.triceps])
        #expect(presses.suggested.first?.primaryMuscleFocus == .triceps)
        #expect(presses.suggested.dropFirst().contains { $0.primaryMuscleFocus == .chest })
    }
}
