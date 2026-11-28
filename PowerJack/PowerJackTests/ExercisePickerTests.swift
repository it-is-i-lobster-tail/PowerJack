import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ExercisePickerTests {
    let container = PowerJackSeed.makeInMemoryContainer()
    let exercises: [Exercise]
    let index: ExerciseSearch.Index
    let bench: Exercise

    init() throws {
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        context.insert(Exercise(exerciseName: "Friday pec squeeze", exerciseEquipment: .machine,
                                primaryMuscleFocus: .chest, userCreated: true))
        try context.save()
        exercises = try context.fetch(FetchDescriptor<Exercise>())
        index = ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
        let all = exercises
        bench = try #require(all.first { $0.catalogID == "barbell-bench-press" })
    }

    private func results(_ query: String, _ mode: ExercisePickerMode = .add, muscles: Set<Muscle> = [],
                         familiarity: ExerciseFamiliarity = .none) -> ExercisePickerResults {
        ExercisePickerResults(exercises: exercises, index: index, familiarity: familiarity, query: query, muscles: muscles, mode: mode)
    }

    @Test func benchAlternatives() {
        let mode = ExercisePickerMode.substitute(WorkoutExercise(exercise: bench, order: 0))
        let suggestions = results("", mode)
        let top = suggestions.matches.prefix(3).compactMap(\.catalogID)
        // Flat presses on other equipment move exactly like it. An incline also raises the arms forward.
        #expect(Set(top) == ["dumbbell-bench-press", "dumbbell-floor-press", "machine-chest-press"])
        let barbellVariants: Set<String> = ["decline-barbell-bench-press", "incline-barbell-bench-press"]
        #expect(barbellVariants.isDisjoint(with: top))
        let changes = results("", .change(bench)).matches.prefix(3).compactMap(\.catalogID)
        #expect(!barbellVariants.isDisjoint(with: changes))
        // Neighbours first, then every other lift under "All Exercises".
        #expect(!suggestions.others.isEmpty)
        let options = suggestions.matches + suggestions.others
        #expect(Set(options.map(\.persistentModelID)).count == exercises.count - 1)
        #expect(options.count == exercises.count - 1)
        #expect(!options.contains { $0 === bench })
        #expect(options.contains { $0.userCreated })
        #expect(suggestions.others.map(\.exerciseName) == suggestions.others.map(\.exerciseName)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending })

        let squat = results("squat", mode)
        #expect(squat.others.isEmpty)
        #expect(squat.matches.prefix(3).allSatisfy { $0.exerciseName.lowercased().contains("squat") })
        let barbell = results("barbell bench", mode)
        #expect(Set(barbell.matches.prefix(2).compactMap(\.catalogID)) == barbellVariants)
        // Named equipment ranks first but no longer hides the rest.
        #expect(barbell.matches.contains { $0.catalogID == "dumbbell-bench-press" })
    }

    @Test func addSearchAndMuscleFilters() {
        let all = results("")
        #expect(all.others.isEmpty)
        #expect(all.matches.count == exercises.count)
        let pecs = results("pecs")
        #expect(pecs.matches.count >= 3)
        #expect(pecs.matches.prefix(3).allSatisfy { $0.primaryMuscleFocus == .chest })
        #expect(results("Friday pec squeeze").matches.first?.exerciseName == "Friday pec squeeze")
        #expect(results("peanut butter").isEmpty)

        let muscles: Set<Muscle> = [.triceps, .quads]
        let filtered = results("", muscles: muscles).matches
        let primary = filtered.prefix { muscles.contains($0.primaryMuscleFocus) }
        let secondary = filtered.dropFirst(primary.count)
        #expect(Set(primary.map(\.primaryMuscleFocus)) == muscles)
        #expect(secondary.contains { $0 === bench })
        #expect(secondary.allSatisfy { !muscles.contains($0.primaryMuscleFocus) && !muscles.isDisjoint(with: $0.secondaryMuscles) })
        let presses = results("bench press", muscles: [.triceps]).matches
        #expect(presses.first?.primaryMuscleFocus == .triceps)
        #expect(presses.dropFirst().contains { $0.primaryMuscleFocus == .chest })
    }

    @Test func familiarLiftsListFirst() throws {
        let squat = try #require(exercises.first { $0.catalogID == "barbell-back-squat" })
        let familiarity = ExerciseFamiliarity(sessions: [[bench.searchKey], [squat.searchKey], [squat.searchKey]])
        let browse = results("", familiarity: familiarity).matches
        #expect(Array(browse.prefix(2)) == [squat, bench])
        #expect(browse.count == exercises.count)
        let rest = browse.dropFirst(2).map(\.exerciseName)
        #expect(rest == rest.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }
}
