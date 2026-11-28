import Foundation
import SwiftData
import Testing

@testable import PowerJack

/// The Data tab's history, kept up to date one change at a time and in a file between launches,
/// must always read exactly as building it all from the store would.
@MainActor
@Suite(.serialized)
struct HistorySummaryTests {
    /// History needs a store on disk; each test gets its own.
    private func diskStore() throws -> ModelContainer {
        let url = URL.temporaryDirectory.appending(path: "HistorySummary-\(UUID().uuidString).store")
        let configuration = ModelConfiguration(schema: PowerJackSchema.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: PowerJackSchema.schema, configurations: [configuration])
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)
        try SimulatorTrainingHistory.populate(in: context, now: ChartSearchFixture.today)
        try HistoryArchive.saveEndedPrograms(in: context)
        try context.save()
        Self.kept.append(container)
        return container
    }

    /// A context must not outlive its container.
    private static var kept: [ModelContainer] = []

    /// Lets the save notifications arrive and the burst settle.
    private func settle() async {
        await HistoryChangesWait.counted()
    }

    private func expectMatchesFullBuild(_ summary: HistorySummary, in context: ModelContext,
                                        sourceLocation: SourceLocation = #_sourceLocation) {
        let kept = summary.parts(in: context)
        let full = HistoryParts(context: context, calendar: .current)
        #expect(Set(kept.workouts.keys) == Set(full.workouts.keys), sourceLocation: sourceLocation)
        for (id, part) in full.workouts {
            let other = kept.workouts[id]
            #expect(other?.workout == part.workout, sourceLocation: sourceLocation)
            #expect(other?.sessions == part.sessions, sourceLocation: sourceLocation)
            #expect(other?.familiar == part.familiar, sourceLocation: sourceLocation)
        }
        #expect(kept.archived == full.archived, sourceLocation: sourceLocation)
        #expect(kept.imported == full.imported, sourceLocation: sourceLocation)
        #expect(kept.logs == full.logs, sourceLocation: sourceLocation)
        #expect(kept.ownLifts == full.ownLifts, sourceLocation: sourceLocation)
        #expect(kept.familiarity == full.familiarity, sourceLocation: sourceLocation)

        let today = ChartSearchFixture.today
        let incremental = StudyHistory(parts: kept, unit: .pounds, today: today)
        let rebuilt = StudyHistory(context: context, unit: .pounds, today: today)
        #expect(incremental.revision == rebuilt.revision, sourceLocation: sourceLocation)
        #expect(incremental.sessions == rebuilt.sessions, sourceLocation: sourceLocation)
        #expect(incremental.workouts == rebuilt.workouts, sourceLocation: sourceLocation)
    }

    @Test("History built from the pieces matches the history built from every model")
    func piecesMatchModels() throws {
        let context = try diskStore().mainContext
        let today = ChartSearchFixture.today
        func all<M: PersistentModel>(_: M.Type) throws -> [M] { try context.fetch(FetchDescriptor<M>()) }
        let fromModels = StudyHistory(
            programs: try all(Program.self), archive: try HistoryArchive.records(in: context), logs: try all(WorkoutLog.self),
            imported: try all(ImportedSet.self), exercises: try all(Exercise.self), unit: .pounds, today: today)
        let fromStore = StudyHistory(context: context, unit: .pounds, today: today)
        #expect(fromStore.revision == fromModels.revision)
        #expect(fromStore.sessions == fromModels.sessions)
        #expect(!fromStore.sessions.isEmpty)
    }

    @Test("Logging, fixing and removing sets rebuild only the workouts they touch")
    func changesRebuildOnlyTheirWorkouts() async throws {
        let context = try diskStore().mainContext
        let summary = HistorySummary()
        expectMatchesFullBuild(summary, in: context)
        #expect(summary.fullBuilds == 1)

        // Log a set of the current workout.
        let program = try #require(try context.fetch(FetchDescriptor<Program>()).active)
        let workout = try #require(program.nextWorkout)
        program.prepareToStart(workout)
        workout.startAndCascade()
        try context.save()
        let slot = try #require(workout.workoutExercises.first)
        let set = try #require(slot.workingSets.first)
        set.reps = 5
        set.weightTenthsPounds = set.weightTenthsPlannedPounds
        slot.completeSet(set)
        try context.save()
        await settle()
        expectMatchesFullBuild(summary, in: context)

        // Fix a set logged weeks ago.
        let old = try #require(try context.fetch(FetchDescriptor<WorkoutSet>()).first {
            $0.status == .complete && !$0.isWarmup && $0.workoutExerciseValue?.workoutValue?.status == .complete
        })
        #expect(old.correctReps((old.reps ?? 5) + 3))
        try context.save()
        await settle()
        expectMatchesFullBuild(summary, in: context)

        // Remove an exercise from a finished workout.
        let finished = try #require(try context.fetch(FetchDescriptor<Workout>()).first { $0.status == .complete })
        context.delete(try #require(finished.workoutExercises.last))
        try context.save()
        await settle()
        expectMatchesFullBuild(summary, in: context)
        #expect(summary.fullBuilds == 1, "None of these rebuilt everything")
    }

    @Test("Renaming a lift or a program, importing and deleting a program keep the history exact")
    func otherChangesKeepItExact() async throws {
        let context = try diskStore().mainContext
        let summary = HistorySummary()
        expectMatchesFullBuild(summary, in: context)

        let own = try #require(try context.fetch(FetchDescriptor<Exercise>()).first { $0.userCreated })
        own.exerciseName = "Reverse Lunge (each leg)"
        try context.save()
        await settle()
        expectMatchesFullBuild(summary, in: context)

        let programs = try context.fetch(FetchDescriptor<Program>())
        let ended = try #require(programs.first { $0.status == .complete })
        ended.templateNameValue = "Renamed Block"
        try context.save()
        await settle()
        expectMatchesFullBuild(summary, in: context)

        let row = ImportedSet()
        row.trainingDay = "2025-06-02"
        row.exerciseKey = StudyHistory.squat
        row.exerciseName = "Barbell Back Squat"
        row.reps = 5
        row.weightTenthsPounds = 2250
        context.insert(row)
        try context.save()
        await settle()
        expectMatchesFullBuild(summary, in: context)

        // Its saved rows now stand in for it.
        try HistoryArchive.programWillBeDeleted(ended, in: context)
        context.delete(ended)
        try context.save()
        await settle()
        expectMatchesFullBuild(summary, in: context)
        #expect(summary.parts(in: context).archived.contains { $0.session != nil })
        #expect(summary.fullBuilds == 1)
    }

    @Test("A new weight unit or day only refilters the kept pieces")
    func unitAndDay() throws {
        let context = try diskStore().mainContext
        let summary = HistorySummary()
        let parts = summary.parts(in: context)
        let today = ChartSearchFixture.today
        let earlier = Calendar.current.date(byAdding: .day, value: -30, to: today)!
        for (unit, day) in [(WeightUnit.kilograms, today), (.pounds, earlier)] {
            let kept = StudyHistory(parts: parts, unit: unit, today: day)
            let rebuilt = StudyHistory(context: context, unit: unit, today: day)
            #expect(kept.revision == rebuilt.revision)
            #expect(kept.sessions == rebuilt.sessions)
        }
        #expect(summary.fullBuilds == 1)
    }

    @Test("A relaunch reads the file and catches up on changes made since")
    func fileRoundTrip() async throws {
        let context = try diskStore().mainContext
        let first = HistorySummary()
        _ = first.parts(in: context)
        let url = try #require(first.fileURL(in: context))
        #expect(FileManager.default.fileExists(atPath: url.path))

        // A change saved while no summary was watching, like an iCloud import before a launch.
        let row = ImportedSet()
        row.trainingDay = "2025-06-03"
        row.exerciseKey = StudyHistory.bench
        row.exerciseName = "Barbell Bench Press"
        row.reps = 8
        row.weightTenthsPounds = 1350
        context.insert(row)
        try context.save()

        let relaunched = HistorySummary()
        expectMatchesFullBuild(relaunched, in: context)
        #expect(relaunched.fullBuilds == 0, "Read from the file, not built again")

        relaunched.saveIfNeeded()
        let again = HistorySummary()
        expectMatchesFullBuild(again, in: context)
        #expect(again.fullBuilds == 0)
    }

    @Test("Clearing the local cache deletes the file and the next open builds it again")
    func clearDeletesTheFile() throws {
        let context = try diskStore().mainContext
        let summary = HistorySummary()
        _ = summary.parts(in: context)
        let url = try #require(summary.fileURL(in: context))
        #expect(FileManager.default.fileExists(atPath: url.path))

        summary.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        expectMatchesFullBuild(summary, in: context)
        #expect(summary.fullBuilds == 2)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A damaged file is built again instead of read")
    func damagedFile() throws {
        let context = try diskStore().mainContext
        let summary = HistorySummary()
        _ = summary.parts(in: context)
        let url = try #require(summary.fileURL(in: context))
        try Data("not a cache".utf8).write(to: url)

        let relaunched = HistorySummary()
        expectMatchesFullBuild(relaunched, in: context)
        #expect(relaunched.fullBuilds == 1)
    }

    @Test("Saved rows of live programs and old rows with lean copies aren't loaded")
    func archiveSkipsWhatItThrowsAway() throws {
        let context = try diskStore().mainContext
        let programs = try context.fetch(FetchDescriptor<Program>())
        let live = Set(programs.compactMap(\.syncID))
        #expect(try HistoryArchive.archivedRows(excluding: live, in: context).isEmpty)
        let everything = HistoryArchive.uniqueBatchRecords(try HistoryArchive.records(in: context))
        let gone = try #require(programs.first { $0.status == .complete }?.syncID)
        let kept = try HistoryArchive.archivedRows(excluding: live.subtracting([gone]), in: context)
        #expect(kept.map(\.row) == everything.filter { $0.programID == gone }.map(\.row))
    }
}
