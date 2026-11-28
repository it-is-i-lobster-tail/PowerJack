//
//  ExerciseRemovalTests.swift
//  PowerJackTests
//
//  Deleting, archiving and merging the lifter's own exercises: nothing logged is ever lost,
//  archived lifts leave search but stay in history, and a merge moves everything to the target.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct ExerciseRemovalTests {
    /// History needs a store on disk; each test gets its own, with a year and a half of training.
    private func trainedStore() throws -> ModelContainer {
        let url = URL.temporaryDirectory.appending(path: "ExerciseRemoval-\(UUID().uuidString).store")
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

    private func own(_ name: String, in context: ModelContext) throws -> Exercise {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: .machine, primaryMuscleFocus: .back, userCreated: true)
        exercise.assignSyncID()
        context.insert(exercise)
        try context.save()
        return exercise
    }

    private func catalog(_ id: String, in context: ModelContext) throws -> Exercise {
        try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == id })).first)
    }

    /// The training history's own exercise, which every program logged.
    private func lunge(in context: ModelContext) throws -> Exercise {
        try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.userCreatedValue })).first)
    }

    private func pickerNames(in context: ModelContext, query: String = "") throws -> [String] {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let index = ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
        let results = ExercisePickerResults(exercises: exercises, index: index, query: query, muscles: [], mode: .add)
        return (results.matches + results.others).map(\.exerciseName)
    }

    private func logged(_ key: String, in history: StudyHistory) -> Int {
        history.sessions.filter { $0.key == key }.reduce(0) { total, session in
            total + (session.sets + session.warmups).count { $0.status == .complete }
        }
    }

    // MARK: Delete

    @Test("An own exercise nothing uses deletes outright")
    func deleteUnused() throws {
        let context = PowerJackSeed.makeInMemoryContainer().mainContext
        let row = try own("Friday Pec Squeeze", in: context)

        let usage = try ExerciseRemoval.usage(of: row, in: context)
        #expect(usage == ExerciseRemoval.Usage(loggedSets: 0, isUsed: false))
        try ExerciseRemoval.delete(row, in: context)

        #expect(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)
    }

    @Test("An own exercise in a template, a program or history can't be deleted")
    func deleteBlockedForUsed() throws {
        let context = PowerJackSeed.makeInMemoryContainer().mainContext
        let inTemplate = try own("Template Row", in: context)
        let template = TemplateProgram(templateName: "Mine", workoutsPerWeek: 1, templateMuscleFocus: [.back])
        context.insert(template)
        _ = template.addTemplateWorkout().addTemplateExercise(exercise: inTemplate)
        try context.save()

        let imported = try own("Imported Row", in: context)
        let set = ImportedSet()
        set.sourceKey = "a.1"
        set.trainingDay = "2025-01-02"
        set.exerciseKey = try #require(imported.syncKey)
        set.reps = 8
        context.insert(set)
        try context.save()

        #expect(try ExerciseRemoval.usage(of: inTemplate, in: context) == .init(loggedSets: 0, isUsed: true))
        #expect(try ExerciseRemoval.usage(of: imported, in: context) == .init(loggedSets: 1, isUsed: true))
        for exercise in [inTemplate, imported] {
            #expect(throws: ExerciseRemoval.RemovalError.used) { try ExerciseRemoval.delete(exercise, in: context) }
        }
        #expect(try context.fetch(FetchDescriptor<Exercise>()).count == 2)
        #expect(template.templateWorkouts.first?.templateExercises.first?.exercise === inTemplate)
    }

    @Test("Built-in exercises are never removed")
    func builtInsStay() throws {
        let context = PowerJackSeed.makeInMemoryContainer().mainContext
        try ExerciseCatalog.seed(in: context)
        let bench = try catalog("barbell-bench-press", in: context)
        let row = try catalog("barbell-row", in: context)
        #expect(throws: ExerciseRemoval.RemovalError.builtIn) { try ExerciseRemoval.delete(bench, in: context) }
        #expect(throws: ExerciseRemoval.RemovalError.builtIn) { try ExerciseRemoval.archive(bench, in: context) }
        #expect(throws: ExerciseRemoval.RemovalError.builtIn) { try ExerciseRemoval.merge(bench, into: row, in: context) }
        #expect(!bench.isDeleted && !bench.isArchived)
    }

    // MARK: Archive

    @Test("Archiving hides an exercise from search and pickers but keeps its history")
    func archiveHidesFromSearchKeepsHistory() throws {
        let context = try trainedStore().mainContext
        let lunge = try lunge(in: context)
        let key = try #require(lunge.syncKey)
        let before = StudyHistory(context: context, unit: .pounds, today: ChartSearchFixture.today)
        let loggedBefore = logged(key, in: before)
        #expect(loggedBefore > 0)
        #expect(try pickerNames(in: context, query: "reverse lunge").contains(lunge.exerciseName))
        let usage = try ExerciseRemoval.usage(of: lunge, in: context)
        #expect(usage.isUsed && usage.loggedSets == loggedBefore)

        try ExerciseRemoval.archive(lunge, in: context)

        #expect(lunge.isArchived)
        #expect(try !pickerNames(in: context).contains(lunge.exerciseName))
        #expect(try !pickerNames(in: context, query: "reverse lunge").contains(lunge.exerciseName))
        let after = StudyHistory(context: context, unit: .pounds, today: ChartSearchFixture.today)
        #expect(logged(key, in: after) == loggedBefore)
        // Exports still carry its sets.
        let csv = HistoryExport.csv(for: try context.fetch(FetchDescriptor<Program>()), saved: try HistoryArchive.records(in: context))
        #expect(csv.contains(lunge.exerciseName))
    }

    @Test("Unarchiving brings an exercise back to search")
    func unarchive() throws {
        let context = PowerJackSeed.makeInMemoryContainer().mainContext
        let row = try own("Hammer Strength Row", in: context)
        try ExerciseRemoval.archive(row, in: context, at: .distantPast)
        #expect(row.archivedAtValue == .distantPast)
        #expect(try !pickerNames(in: context, query: "hammer").contains("Hammer Strength Row"))

        try ExerciseRemoval.unarchive(row, in: context)

        #expect(!row.isArchived)
        #expect(try pickerNames(in: context, query: "hammer").contains("Hammer Strength Row"))
    }

    // MARK: Merge

    @Test("Merging moves sets, template and program rows, imports, saved history, records and charts")
    func mergeMovesEverything() throws {
        let context = try trainedStore().mainContext
        let lunge = try lunge(in: context)
        let oldKey = try #require(lunge.syncKey)
        let squat = try catalog("barbell-back-squat", in: context)
        let newKey = try #require(squat.syncKey)

        // A template row, a one-time substitute, an import, a deleted program's saved history and a lift record.
        let template = TemplateProgram(templateName: "Mine", workoutsPerWeek: 1, templateMuscleFocus: [.quads])
        context.insert(template)
        _ = template.addTemplateWorkout().addTemplateExercise(exercise: lunge)
        let programs = try context.fetch(FetchDescriptor<Program>()).sorted { ($0.syncID?.uuidString ?? "") < ($1.syncID?.uuidString ?? "") }
        let imported = ImportedSet()
        imported.sourceKey = "b.1"
        imported.trainingDay = "2024-03-04"
        imported.exerciseKey = oldKey
        imported.exerciseName = lunge.exerciseName
        imported.reps = 10
        imported.weightTenthsPounds = 950
        context.insert(imported)
        let deleted = try #require(programs.first { $0.status != .active && $0.programWeeks.contains { $0.workouts.contains {
            $0.workoutExercises.contains { $0.exercise === lunge }
        } } })
        let substituted = try #require(programs.filter { $0 !== deleted }.flatMap { $0.programWeeks.flatMap(\.workouts) }
            .flatMap(\.workoutExercises).first { $0.exercise?.catalogID == "barbell-back-squat" && $0.substitute == nil })
        substituted.replaceDuplicateSubstitute(with: lunge)
        try HistoryArchive.programWillBeDeleted(deleted, in: context)
        context.delete(deleted)
        var state = StrengthState()
        state.lifts[StrengthLifts.key(for: lunge)] = StrengthLiftRecord(e1rmKg: 80)
        context.insert(StrengthLog(date: .now.addingTimeInterval(-60), state: state))
        try context.save()

        let defaults = try #require(UserDefaults(suiteName: "ExerciseRemovalTests-\(UUID().uuidString)"))
        var options = StudyOptions()
        options.exerciseKeys = [oldKey, "catalog:barbell-bench-press"]
        let study = TrainingStudy.allCases[0]
        defaults.set(try FavoriteCharts(data: Data()).toggling(study, options: options, name: "Lunge"), forKey: FavoriteCharts.storageKey)
        defaults.set(try SavedStudyViews(data: Data()).saving(options, for: study), forKey: SavedStudyViews.storageKey)

        let before = StudyHistory(context: context, unit: .pounds, today: ChartSearchFixture.today)
        let lungeSets = logged(oldKey, in: before)
        let squatSets = logged(newKey, in: before)
        let usage = try ExerciseRemoval.usage(of: lunge, in: context)
        #expect(usage.loggedSets == lungeSets)

        let moved = try ExerciseRemoval.merge(lunge, into: squat, in: context, defaults: defaults)

        #expect(moved == usage.loggedSets)
        #expect(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.userCreatedValue })).isEmpty)
        #expect(template.templateWorkouts.first?.templateExercises.first?.exercise === squat)
        // A substitute that is now the planned lift itself is no substitute.
        #expect(substituted.substitute == nil && substituted.exercise === squat)
        let rows = try context.fetch(FetchDescriptor<WorkoutExercise>())
        #expect(rows.allSatisfy { $0.exercise != nil })
        #expect(imported.exerciseKey == newKey && imported.exerciseName == squat.exerciseName)
        let saved = try HistoryArchive.records(in: context)
        #expect(!saved.isEmpty && !saved.contains { $0.row.exerciseKey == oldKey })
        #expect(saved.contains { $0.row.exerciseKey == newKey && $0.row.programID == deleted.syncID })
        let record = try #require(try StrengthLog.latest(in: context)?.state)
        #expect(record.lifts[StrengthLifts.key(for: lunge)] == nil)
        #expect(record.lifts["barbell-back-squat"]?.e1rmKg == 80)

        // Charts and records read the merged sets as the target's, including days both were logged.
        let after = StudyHistory(context: context, unit: .pounds, today: ChartSearchFixture.today)
        #expect(logged(oldKey, in: after) == 0)
        #expect(logged(newKey, in: after) == squatSets + lungeSets)
        #expect(after.sessions.filter { $0.key == newKey }.allSatisfy { $0.name == squat.exerciseName })

        let favorites = try #require(defaults.data(forKey: FavoriteCharts.storageKey))
        let favorite = try #require(FavoriteCharts(data: favorites).charts.first)
        #expect(favorite.options.exerciseKeys == [newKey, "catalog:barbell-bench-press"])
        let view = SavedStudyViews(data: try #require(defaults.data(forKey: SavedStudyViews.storageKey)))[study]
        #expect(view.exerciseKeys == [newKey, "catalog:barbell-bench-press"])
    }

    @Test("A lift record the target already has stays")
    func mergeKeepsTargetRecord() throws {
        let context = PowerJackSeed.makeInMemoryContainer().mainContext
        try ExerciseCatalog.seed(in: context)
        let row = try own("Hammer Strength Row", in: context)
        let target = try catalog("barbell-row", in: context)
        var state = StrengthState()
        state.lifts[StrengthLifts.key(for: row)] = StrengthLiftRecord(e1rmKg: 50)
        state.lifts["barbell-row"] = StrengthLiftRecord(e1rmKg: 100)
        context.insert(StrengthLog(date: .now.addingTimeInterval(-60), state: state))
        try context.save()

        try ExerciseRemoval.merge(row, into: target, in: context)

        let lifts = try #require(try StrengthLog.latest(in: context)?.state).lifts
        #expect(lifts.count == 1 && lifts["barbell-row"]?.e1rmKg == 100)
    }

    @Test("Merging into itself changes nothing")
    func mergeIntoItself() throws {
        let context = PowerJackSeed.makeInMemoryContainer().mainContext
        let row = try own("Hammer Strength Row", in: context)
        #expect(throws: ExerciseRemoval.RemovalError.sameExercise) { try ExerciseRemoval.merge(row, into: row, in: context) }
        #expect(!row.isDeleted)
    }

    @Test("FitNotes still matches an archived exercise by name, so an import never makes a duplicate")
    func fitNotesMatchesArchived() throws {
        let context = PowerJackSeed.makeInMemoryContainer().mainContext
        try ExerciseCatalog.seed(in: context)
        let row = try own("Hammer Strength Row", in: context)
        try ExerciseRemoval.archive(row, in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(FitNotesMatcher.direct("Hammer Strength Row", among: exercises) === row)
    }

    // MARK: History cache

    @Test("The Data tab's kept history catches up on archive, merge and delete without a full rebuild")
    func cacheCatchesUp() async throws {
        let context = try trainedStore().mainContext
        let summary = HistorySummary()
        _ = summary.parts(in: context)
        #expect(summary.fullBuilds == 1)
        let lunge = try lunge(in: context)
        let oldKey = try #require(lunge.syncKey)

        try ExerciseRemoval.archive(lunge, in: context)
        try await settle()
        expectMatchesFullBuild(summary, in: context)

        let squat = try catalog("barbell-back-squat", in: context)
        try ExerciseRemoval.merge(lunge, into: squat, in: context, defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        try await settle()
        expectMatchesFullBuild(summary, in: context)
        #expect(!summary.parts(in: context).workouts.values.contains { $0.sessions.contains { $0.key == oldKey } })

        try ExerciseRemoval.delete(try own("Unused", in: context), in: context)
        try await settle()
        expectMatchesFullBuild(summary, in: context)
        #expect(summary.fullBuilds == 1)
    }

    private func settle() async throws {
        await HistoryChangesWait.counted()
    }

    private func expectMatchesFullBuild(_ summary: HistorySummary, in context: ModelContext,
                                        sourceLocation: SourceLocation = #_sourceLocation) {
        let kept = summary.parts(in: context)
        let full = HistoryParts(context: context, calendar: .current)
        #expect(Set(kept.workouts.keys) == Set(full.workouts.keys), sourceLocation: sourceLocation)
        for (id, part) in full.workouts {
            #expect(kept.workouts[id]?.sessions == part.sessions, sourceLocation: sourceLocation)
            #expect(kept.workouts[id]?.familiar == part.familiar, sourceLocation: sourceLocation)
        }
        #expect(kept.archived == full.archived, sourceLocation: sourceLocation)
        #expect(kept.imported == full.imported, sourceLocation: sourceLocation)
        #expect(kept.ownLifts == full.ownLifts, sourceLocation: sourceLocation)
        #expect(kept.familiarity == full.familiarity, sourceLocation: sourceLocation)
    }

    // MARK: Watch

    @Test("The watch drops its copy of an own exercise the iPhone no longer sends once nothing uses it")
    func watchDropsUnusedCopies() throws {
        let context = PowerJackSeed.makeInMemoryContainer().mainContext
        let phone = Exercise(exerciseName: "Hammer Strength Row", exerciseEquipment: .machine, primaryMuscleFocus: .back, userCreated: true)
        phone.assignSyncID()
        let state = try #require(phone.syncState)
        let unused = Exercise(snapshot: state)
        let other = Exercise(exerciseName: "Kept Row", exerciseEquipment: .machine, primaryMuscleFocus: .back, userCreated: true)
        other.assignSyncID()
        let used = Exercise(snapshot: try #require(other.syncState))
        context.insert(unused)
        context.insert(used)
        let workout = Workout(order: 0)
        context.insert(workout)
        _ = workout.addWorkoutExercise(exercise: used)
        try context.save()

        try ProgramSnapshot(program: nil, notRunning: [], exercises: [], strengthLog: nil, applied: [:]).apply(to: context)

        let left = try context.fetch(FetchDescriptor<Exercise>()).map(\.exerciseName)
        #expect(left == ["Kept Row"])
    }
}
