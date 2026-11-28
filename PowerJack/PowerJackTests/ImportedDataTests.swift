import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ImportedDataTests {
    private func imported(_ day: String, _ exercise: Exercise, source: String, order: Int,
                          weight: Int? = 1350, reps: Int? = 8) -> ImportedSet {
        let set = ImportedSet()
        set.sourceKey = "\(day).\(source).\(order)"
        set.trainingDay = day
        set.sourceExercise = source
        set.exerciseKey = exercise.syncKey!
        set.exerciseName = exercise.exerciseName
        set.muscle = exercise.primaryMuscleFocus.rawValue
        set.weightTenthsPounds = weight
        set.reps = reps
        set.sourceOrder = order
        return set
    }

    private func catalogExercise(_ id: String, in context: ModelContext) throws -> Exercise {
        let entry = try #require(ExerciseCatalog.entries.first { $0.id == id })
        let exercise = entry.makeExercise()
        context.insert(exercise)
        return exercise
    }

    @Test func daysListNewestFirstInLoggedOrder() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let squat = try catalogExercise("barbell-back-squat", in: context)
        let sets = [imported("2024-01-02", squat, source: "Barbell Squat", order: 5),
                    imported("2025-03-04", squat, source: "Barbell Squat", order: 2),
                    imported("2024-01-02", squat, source: "Barbell Squat", order: 1)]
        let days = ImportedData.days(sets)
        #expect(days.map(\.id) == ["2025-03-04", "2024-01-02"])
        #expect(days[1].sets.map(\.sourceOrder) == [1, 5])
    }

    @Test func dayTitleIsTheCalendarDayEverywhere() {
        // Stored days have no time zone, so the title never slips to the day before.
        #expect(ImportedData.title(forDay: "2025-03-04").contains("4"))
        #expect(ImportedData.title(forDay: "not a day") == "not a day")
    }

    @Test func detailReadsWeightRepsTimeAndDistance() {
        let set = ImportedSet()
        set.weightTenthsPounds = 1350
        set.reps = 8
        #expect(ImportedData.detail(set, unit: .pounds) == "135 lb × 8 reps")
        set.weightTenthsPounds = nil
        set.reps = 1
        #expect(ImportedData.detail(set, unit: .pounds) == "1 rep")
        set.reps = nil
        set.durationSeconds = 95
        set.distance = 2.5
        set.distanceUnit = "km"
        #expect(ImportedData.detail(set, unit: .pounds) == "1:35 · 2.5 km")
    }

    @Test func searchFindsLiftsByEitherName() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let squat = try catalogExercise("barbell-back-squat", in: context)
        let bench = try catalogExercise("barbell-bench-press", in: context)
        let sets = [imported("2025-03-04", squat, source: "Barbell Squat", order: 0),
                    imported("2025-03-04", bench, source: "Flat Barbell Bench Press", order: 1)]
        let index = ExerciseSearch.Index(ImportedData.documents(for: sets, exercises: [squat, bench]))

        #expect(ImportedData.matching("", in: sets, index: index).count == 2)
        #expect(ImportedData.matching("squat", in: sets, index: index).map(\.exerciseKey) == [squat.syncKey])
        #expect(ImportedData.matching("flat bench", in: sets, index: index).map(\.exerciseKey) == [bench.syncKey])
        // Before the index is built, plain name matching still finds the FitNotes name.
        #expect(ImportedData.matching("Flat", in: sets, index: nil).map(\.exerciseKey) == [bench.syncKey])
    }

    @Test func deletingRemovesOnlyTheChosenSets() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let squat = try catalogExercise("barbell-back-squat", in: context)
        let kept = imported("2025-03-04", squat, source: "Barbell Squat", order: 0)
        let doomed = [imported("2025-03-04", squat, source: "Barbell Squat", order: 1),
                      imported("2025-03-05", squat, source: "Barbell Squat", order: 0)]
        for set in [kept] + doomed { context.insert(set) }
        try context.save()

        try ImportedData.delete(doomed, in: context)

        let left = try context.fetch(FetchDescriptor<ImportedSet>())
        #expect(left.map(\.sourceKey) == [kept.sourceKey])
        // The lift itself stays: only the imported sets go.
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
    }

    @Test func deletedSetsLeaveTheDataTabHistory() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let squat = try catalogExercise("barbell-back-squat", in: context)
        let set = imported("2025-03-04", squat, source: "Barbell Squat", order: 0)
        context.insert(set)
        try context.save()
        #expect(!StudyHistory(context: context, unit: .pounds).sessions.isEmpty)

        try ImportedData.delete([set], in: context)

        #expect(StudyHistory(context: context, unit: .pounds).sessions.isEmpty)
    }
}
