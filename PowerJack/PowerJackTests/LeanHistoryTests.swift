//
//  LeanHistoryTests.swift
//  PowerJackTests
//
//  The long history's lean shape (`HistoryProgram` + `HistoryExercise`) next to the old
//  `HistoryRecord` rows: both are written, old batches are backfilled, and the export and
//  the Data tab read exactly the same from either. Also the device marks that gate the trim.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct LeanHistoryTests {
    private let store = PowerJackStore(inMemory: true)
    private var context: ModelContext { store.container!.mainContext }
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("A year of history reads the same from the lean rows as from the old ones: export and Data tab")
    func bothShapesReadTheSame() throws {
        try seedYear()
        let (legacy, lean) = try bothPaths()
        #expect(legacy.count > 100)
        #expect(lean == legacy)
        // The sample has what's hardest to pack: warm-ups, skipped sets and supersets.
        #expect(legacy.contains { $0.row.setType == "Warmup" })
        #expect(legacy.contains { $0.row.setStatus == "Skipped" })
        #expect(HistoryExport.csv(for: [], saved: lean, unit: .pounds) == HistoryExport.csv(for: [], saved: legacy, unit: .pounds))
        #expect(studied(lean) == studied(legacy))
    }

    @Test("Saved programs without lean rows get them once at launch, and they read the same")
    func backfill() throws {
        try seedYear()
        let (legacy, _) = try bothPaths()
        try deleteLean()
        let batches = Set(try context.fetch(FetchDescriptor<HistoryRecord>()).compactMap(\.batchID))
        #expect(!batches.isEmpty)

        #expect(try HistoryArchive.backfillLeanHistory(in: context) == batches.count)
        #expect(try HistoryArchive.backfillLeanHistory(in: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HistoryProgram>()) == batches.count)
        #expect(try bothPaths().lean == legacy)
        #expect(sorted(try HistoryArchive.records(in: context)) == legacy)
    }

    @Test("Deleting a saved program marks both shapes deleted, and they still read the same")
    func deletedProgram() throws {
        try seedYear()
        let program = try #require(try context.fetch(FetchDescriptor<Program>()).first { $0.status == .complete })
        let id = try #require(program.syncID)
        try HistoryArchive.programWillBeDeleted(program, in: context)
        program.delete()
        try context.save()

        let (legacy, lean) = try bothPaths()
        let deleted = lean.filter { $0.programID == id }
        #expect(!deleted.isEmpty && deleted.allSatisfy { $0.programStatus == .deleted })
        #expect(lean == legacy)
        #expect(HistoryExport.csv(for: [], saved: lean, unit: .pounds) == HistoryExport.csv(for: [], saved: legacy, unit: .pounds))
    }

    @Test("A fixed set shows the fix in both shapes")
    func correction() throws {
        try seedYear()
        let program = try #require(try context.fetch(FetchDescriptor<Program>()).first { $0.status == .complete })
        let workoutSet = try #require(program.programWeeks.first?.workouts.first?.workoutExercises.first?.workingSets.first)
        #expect(workoutSet.correctReps(42))
        try HistoryArchive.correct(workoutSet, in: context)
        try context.save()

        let (legacy, lean) = try bothPaths()
        #expect(lean.contains { $0.programID == program.syncID && $0.row.reps == 42 })
        #expect(lean == legacy)
    }

    @Test("Two iPhones' copies of a batch, and two iPhones' batches of a program, read as one, the same from both shapes")
    func duplicates() throws {
        try seedYear()
        // The other iPhone backfilled the same batches before iCloud brought this one's copies.
        for (batchID, records) in Dictionary(grouping: try context.fetch(FetchDescriptor<HistoryRecord>()), by: \.batchID) {
            let rows = records.sorted { $0.order < $1.order }
            let batch = try #require(batchID)
            let lean = try #require(HistoryProgram.make(
                from: rows.map(\.row), batchID: batch, savedAt: rows[0].savedAt, programStarted: rows[0].programStartedValue
            ))
            context.insert(lean.program)
            lean.exercises.forEach(context.insert)
        }
        // And a second batch of one program, saved a minute later on the other iPhone.
        let program = try #require(try context.fetch(FetchDescriptor<Program>()).first { $0.status == .complete })
        let rows = HistoryExport.rows(for: program)
        let otherBatch = UUID()
        for (order, row) in rows.enumerated() {
            context.insert(HistoryRecord(row, batchID: otherBatch, savedAt: .now + 60, programStarted: nil, order: order))
        }
        let lean = try #require(HistoryProgram.make(from: rows, batchID: otherBatch, savedAt: .now + 60, programStarted: nil))
        context.insert(lean.program)
        lean.exercises.forEach(context.insert)
        try context.save()

        let (legacy, leanRows) = try bothPaths()
        #expect(leanRows == legacy)
        #expect(!leanRows.contains { $0.batchID == otherBatch })
        #expect(Set(leanRows.compactMap(\.batchID)).count == Set(try context.fetch(FetchDescriptor<HistoryProgram>()).compactMap(\.batchID)).count - 1)
    }

    @Test("A batch with lean rows is read from them, one without from its old rows")
    func prefersLean() throws {
        try seedYear()
        let batches = try context.fetch(FetchDescriptor<HistoryProgram>())
        #expect(batches.count > 1)
        // The first batch's lean copy holds a fix only it has; the second has only old rows.
        let first = try #require(batches.first)
        for slot in try context.fetch(FetchDescriptor<HistoryExercise>()) where slot.copyID == first.copyID {
            for set in slot.sets { slot.correct(setNumber: set.number, setType: set.type, reps: 99, weightTenthsPounds: set.weightTenthsPounds) }
        }
        let second = try #require(batches.last)
        let secondBatch = second.batchID
        for slot in try context.fetch(FetchDescriptor<HistoryExercise>()) where slot.copyID == second.copyID { context.delete(slot) }
        context.delete(second)
        try context.save()

        let saved = try HistoryArchive.records(in: context)
        let firstRows = saved.filter { $0.batchID == first.batchID }
        #expect(!firstRows.isEmpty && firstRows.allSatisfy { $0.row.reps == 99 })
        let fromOld = try context.fetch(FetchDescriptor<HistoryRecord>()).filter { $0.batchID == secondBatch }
        #expect(saved.filter { $0.batchID == secondBatch }.count == fromOld.count)
    }

    // MARK: Device marks

    @Test("Old history can go only once every device seen in 90 days reads the lean shape")
    func trimGate() throws {
        let phone = UUID(), watch = UUID(), oldPhone = UUID()
        #expect(try !DeviceSchemaMark.canTrimLegacyHistory(in: context, now: now), "no device has said so yet")

        try DeviceSchemaMark.update(in: context, deviceID: phone, device: SyncDevice.iPhone, now: now)
        try DeviceSchemaMark.update(in: context, deviceID: phone, device: SyncDevice.iPhone, now: now + 60)
        #expect(try context.fetchCount(FetchDescriptor<DeviceSchemaMark>()) == 1)
        #expect(try DeviceSchemaMark.canTrimLegacyHistory(in: context, now: now + 60))

        // A watch still on an older version, as iCloud would bring its row.
        let older = DeviceSchemaMark(deviceID: watch)
        older.lastSeenValue = now - 30 * 86_400
        context.insert(older)
        #expect(try !DeviceSchemaMark.canTrimLegacyHistory(in: context, now: now))
        try DeviceSchemaMark.update(in: context, deviceID: watch, device: SyncDevice.watch, now: now)
        #expect(try DeviceSchemaMark.canTrimLegacyHistory(in: context, now: now))

        // An old iPhone last seen 100 days ago no longer holds it back.
        let gone = DeviceSchemaMark(deviceID: oldPhone)
        gone.lastSeenValue = now - 100 * 86_400
        context.insert(gone)
        #expect(try DeviceSchemaMark.canTrimLegacyHistory(in: context, now: now))
        #expect(try !DeviceSchemaMark.canTrimLegacyHistory(in: context, now: now - 20 * 86_400))
    }

    @Test("A device keeps one ID")
    func deviceID() throws {
        let defaults = try #require(UserDefaults(suiteName: "LeanHistoryTests.\(UUID().uuidString)"))
        #expect(DeviceSchemaMark.currentDeviceID(in: defaults) == DeviceSchemaMark.currentDeviceID(in: defaults))
    }

    // MARK: Helpers

    private func seedYear() throws {
        try SimulatorTrainingHistory.populate(in: context, now: now)
        try HistoryArchive.saveEndedPrograms(in: context)
        try context.save()
    }

    /// The saved rows read only from the old shape, and only from the lean one.
    private func bothPaths() throws -> (legacy: [ArchivedRow], lean: [ArchivedRow]) {
        let legacy = HistoryArchive.uniqueBatchRecords(HistoryArchive.archivedRows(
            programs: [], exercises: [], legacy: try context.fetch(FetchDescriptor<HistoryRecord>())
        ))
        let lean = HistoryArchive.uniqueBatchRecords(HistoryArchive.archivedRows(
            programs: try context.fetch(FetchDescriptor<HistoryProgram>()),
            exercises: try context.fetch(FetchDescriptor<HistoryExercise>()),
            legacy: []
        ))
        return (sorted(legacy), sorted(lean))
    }

    /// Batches come back in store order, so compare them in a fixed one.
    private func sorted(_ rows: [ArchivedRow]) -> [ArchivedRow] {
        rows.sorted { ($0.batchID?.uuidString ?? "", $0.order) < ($1.batchID?.uuidString ?? "", $1.order) }
    }

    private func deleteLean() throws {
        try context.delete(model: HistoryExercise.self)
        try context.delete(model: HistoryProgram.self)
        try context.save()
    }

    /// What the Data tab builds from the saved rows alone.
    private func studied(_ rows: [ArchivedRow]) -> [String] {
        let history = StudyHistory(programs: [], archive: rows, logs: [], unit: .pounds, today: now)
        return (history.sessions.map { String(describing: $0) } + history.workouts.map { String(describing: $0) }).sorted()
    }
}
