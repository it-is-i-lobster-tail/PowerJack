import CoreData
import Foundation
import SwiftData
import Testing

@testable import PowerJack

/// The Data tab and the exercise picker keep their history summaries until the next saved change.
@MainActor
struct HistoryCacheTests {
    private func sampleStore() throws -> PowerJackStore {
        let store = PowerJackStore(inMemory: true)
        try SimulatorTrainingHistory.populate(in: store.container.mainContext, now: ChartSearchFixture.today)
        return store
    }

    /// Lets the save notifications arrive and the burst settle.
    private func settle() async {
        try? await Task.sleep(for: HistoryChanges.settle * 3)
    }

    private func importedRow(_ day: String, in context: ModelContext) -> ImportedSet {
        let row = ImportedSet()
        row.trainingDay = day
        row.exerciseKey = StudyHistory.squat
        row.exerciseName = "Barbell Back Squat"
        row.reps = 5
        row.weightTenthsPounds = 2250
        context.insert(row)
        return row
    }

    @Test("History fetched from the store draws every chart as the queried history did")
    func storeHistoryMatches() throws {
        let store = try sampleStore()
        let context = store.container.mainContext
        let today = ChartSearchFixture.today
        _ = importedRow("2025-06-02", in: context)
        try context.save()
        let queried = StudyHistory(
            programs: try context.fetch(FetchDescriptor<Program>()),
            archive: try context.fetch(FetchDescriptor<HistoryRecord>()).map(\.archived),
            logs: try context.fetch(FetchDescriptor<WorkoutLog>()),
            imported: try context.fetch(FetchDescriptor<ImportedSet>()),
            exercises: try context.fetch(FetchDescriptor<Exercise>()), unit: .pounds, today: today)
        let fetched = StudyHistory(context: context, unit: .pounds, today: today)

        #expect(!fetched.sessions.isEmpty)
        #expect(fetched.revision == queried.revision)
        #expect(fetched.sessions.count == queried.sessions.count)
        #expect(fetched.workouts.count == queried.workouts.count)
        for study in TrainingStudy.allCases {
            #expect(fetched.result(for: study) == queried.result(for: study), "\(study)")
        }
    }

    @Test("The Data tab reuses its history until a change is saved")
    func dataHistoryRebuildsAfterSave() async throws {
        let changes = HistoryChanges.shared
        let store = try sampleStore()
        let context = store.container.mainContext
        try context.save()
        await settle()

        let before = changes.count
        let first = StudyHistory.current(in: context, unit: .pounds)
        _ = importedRow("2025-06-02", in: context)
        let unsaved = StudyHistory.current(in: context, unit: .pounds)
        // Other suites save too, so only check reuse while nothing was saved anywhere.
        if changes.count == before {
            #expect(unsaved.revision == first.revision, "Redraws before a save reuse the history")
        }

        try context.save()
        await settle()
        #expect(changes.count > before)
        let saved = StudyHistory.current(in: context, unit: .pounds)
        #expect(saved.revision != first.revision)
        #expect(saved.revision == StudyHistory(context: context, unit: .pounds).revision)
        #expect(StudyHistory.current(in: context, unit: .kilograms).revision != saved.revision, "A new unit rebuilds")
    }

    @Test("The search journal's own saves don't count as training changes")
    func journalSavesAreIgnored() throws {
        let store = PowerJackStore(inMemory: true)
        let context = store.container.mainContext
        let row = importedRow("2025-06-02", in: context)
        try context.save()
        let journal = GallerySearchJournal(inMemory: true)
        let phrase = GallerySearchPhrase(key: "bench", text: "bench")
        journal.context?.insert(phrase)
        try journal.context?.save()

        #expect(HistoryChanges.counts([row.persistentModelID]))
        #expect(HistoryChanges.counts([phrase.persistentModelID, row.persistentModelID]))
        #expect(!HistoryChanges.counts([phrase.persistentModelID]))
        #expect(!HistoryChanges.counts([]))
    }

    @Test("Only the training store's iCloud imports count, not other stores like the tips store")
    func otherStoresAreIgnored() throws {
        let changes = HistoryChanges.shared
        let store = PowerJackStore(inMemory: true)
        _ = StudyHistory.current(in: store.container.mainContext, unit: .pounds)
        let tips = URL(filePath: NSTemporaryDirectory()).appending(path: "tips.sqlite")
        #expect(!changes.counts(tips))
        #expect(changes.counts(try #require(store.container.configurations.first?.url)))
    }

    @Test("Picker familiarity matches the workouts and imports it was built from")
    func familiarityFromStore() async throws {
        let store = try sampleStore()
        let context = store.container.mainContext
        _ = importedRow("2026-11-24", in: context)
        try context.save()
        let expected = ExerciseFamiliarity.from(workouts: try context.fetch(FetchDescriptor<Workout>()),
                                                imported: try context.fetch(FetchDescriptor<ImportedSet>()))
        #expect(expected.score(StudyHistory.squat) > 0)
        let cache = HistoryCache<ExerciseFamiliarity>()
        var builds = 0
        let first = cache.value(in: context) { builds += 1; return expected }
        let again = cache.value(in: context) { builds += 1; return .none }
        #expect(first == expected && again == expected)
        #expect(builds == 1)
    }
}
