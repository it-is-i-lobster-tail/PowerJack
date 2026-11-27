//
//  HistoryExportTests.swift
//  PowerJackTests
//
//  The workout history CSV: one row per set, with what each set belongs to, in a form
//  any spreadsheet reads the same way, and nothing the lifter typed or where they are.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct HistoryExportTests {
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("Every set is one row, and every row has a value for each column")
    func oneRowPerSet() throws {
        let workout = try makeLoggedWorkout()
        let table = parse(HistoryExport.csv(for: [try #require(workout.programWeekValue?.programValue)], unit: .pounds))

        let setCount = workout.workoutExercises.map(\.workoutSets.count).reduce(0, +)
        #expect(table.count == setCount + 1)
        #expect(table[0] == HistoryExport.columns(unit: .pounds))
        #expect(table.allSatisfy { $0.count == table[0].count })
    }

    @Test("A logged set carries its program, day, exercise, targets, result and times")
    func loggedSet() throws {
        let workout = try makeLoggedWorkout()
        let rows = records(HistoryExport.csv(for: [try #require(workout.programWeekValue?.programValue)], unit: .pounds))
        let bench = try #require(rows.first { $0["Exercise"] == "Bench" && $0["Set Type"] == "Working" && $0["Set #"] == "1" })

        #expect(bench["Program #"] == "1")
        #expect(bench["Program"] == "Push")
        #expect(bench["Program Type"] == "Hypertrophy")
        #expect(bench["Week"] == "1" && bench["Day"] == "1")
        #expect(bench["Equipment"] == "Barbell" && bench["Exercise Source"] == "Built-in")
        #expect(bench["Superset"] == "A")
        #expect(bench["Set Status"] == "Complete")
        #expect(bench["Reps"] == "8" && bench["Weight (lb)"] == "225")
        #expect(bench["Set Started"] == start.formatted(.iso8601))
        #expect(bench["Set Logged"] == (start + 120).formatted(.iso8601))
        #expect(bench["Set Seconds"] == "120")
        #expect(bench["Effort"] == "2 reps left" && bench["Pain"] == "Mild")

        let skipped = try #require(rows.first { $0["Exercise"] == "Bench" && $0["Set Type"] == "Working" && $0["Set #"] == "2" })
        #expect(skipped["Set Status"] == "Skipped" && skipped["Reps"] == "" && skipped["Set Seconds"] == "")
    }

    @Test("Weights follow the unit, and 0 on loadable bodyweight stays 0")
    func weights() throws {
        let workout = try makeLoggedWorkout()
        let program = try #require(workout.programWeekValue?.programValue)
        let rows = records(HistoryExport.csv(for: [program], unit: .kilograms))

        let bench = try #require(rows.first { $0["Exercise"] == "Bench" && $0["Set Status"] == "Complete" })
        #expect(bench["Weight (kg)"] == "102.1")
        let dip = try #require(rows.first { $0["Set Status"] == "Complete" && $0["Equipment"] == "Loadable Bodyweight" })
        #expect(dip["Weight (kg)"] == "0" && dip["Exercise Source"] == "Custom")
    }

    @Test("The lifter's own templates and exercises keep their names, and times are UTC")
    func names() throws {
        let workout = try makeLoggedWorkout()
        let program = try #require(workout.programWeekValue?.programValue)
        let rows = records(HistoryExport.csv(for: [program], unit: .pounds))
        let dips = rows.filter { $0["Exercise Source"] == "Custom" }
        #expect(!dips.isEmpty && dips.allSatisfy { $0["Exercise"] == #"Dip, "Weighted""# })
        #expect(rows.allSatisfy { $0["Program"] == "Push" })
        // Times carry no offset that hints at where the lifter is.
        let times = rows.flatMap { [$0["Workout Started"], $0["Set Logged"]] }.compactMap { $0 }.filter { !$0.isEmpty }
        #expect(!times.isEmpty && times.allSatisfy { $0.hasSuffix("Z") })
    }

    @Test("The file is written and named for today")
    func file() throws {
        _ = try makeLoggedWorkout()
        let url = try HistoryExport.writeFile(from: container.mainContext, unit: .pounds)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent.hasPrefix("PowerJack History ") && url.pathExtension == "csv")
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("Program #,Program ID,Program,"))
    }

    // MARK: Long view

    @Test("A finished program's sets are saved once, and the export reads the same from them")
    func finishedProgramIsSaved() throws {
        let context = container.mainContext
        let workout = try makeLoggedWorkout()
        let program = try #require(workout.programWeekValue?.programValue)
        program.finishWorkout(workout)
        #expect(program.status == .complete)

        let saved = try HistoryArchive.records(in: context)
        let setCount = workout.workoutExercises.map(\.workoutSets.count).reduce(0, +)
        #expect(saved.count == setCount)
        #expect(saved.allSatisfy { $0.programID == program.syncID && $0.programStatus == .completed })
        #expect(HistoryExport.csv(for: [], saved: saved, unit: .pounds) == HistoryExport.csv(for: [program], unit: .pounds))
        #expect(HistoryExport.csv(for: [program], saved: saved, unit: .pounds) == HistoryExport.csv(for: [program], unit: .pounds))

        // Saving again, as the export and each launch do, adds nothing.
        try HistoryArchive.saveEndedPrograms(in: context)
        #expect(try context.fetchCount(FetchDescriptor<HistoryRecord>()) == setCount)
        let rows = records(HistoryExport.csv(for: [program], saved: saved, unit: .pounds))
        #expect(rows.allSatisfy { $0["Program Status"] == "Completed" && $0["Program ID"] == program.syncID?.uuidString })
    }

    @Test("A deleted program stays in the export, marked deleted")
    func deletedProgramStays() throws {
        let context = container.mainContext
        let workout = try makeLoggedWorkout()
        let program = try #require(workout.programWeekValue?.programValue)
        program.finishWorkout(workout)
        let id = try #require(program.syncID)
        let before = records(HistoryExport.csv(for: [program], unit: .pounds))

        try HistoryArchive.programWillBeDeleted(program, in: context)
        program.delete()
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Program>()).isEmpty)
        let url = try HistoryExport.writeFile(from: context, unit: .pounds)
        defer { try? FileManager.default.removeItem(at: url) }
        let after = records(try String(contentsOf: url, encoding: .utf8))
        #expect(after.count == before.count)
        #expect(after.allSatisfy { $0["Program Status"] == "Deleted" && $0["Program ID"] == id.uuidString })
        #expect(after.map { $0.filter { $0.key != "Program Status" } } == before.map { $0.filter { $0.key != "Program Status" } })
    }

    @Test("A program skipped for another is saved as skipped, and deleting it later keeps it")
    func skippedProgram() throws {
        let context = container.mainContext
        let workout = try makeLoggedWorkout()
        let program = try #require(workout.programWeekValue?.programValue)
        program.stop()
        program.stopAndCascade()
        #expect(try HistoryArchive.records(in: context).allSatisfy { $0.programStatus == .skipped })
        #expect(try !HistoryArchive.records(in: context).isEmpty)

        try HistoryArchive.programWillBeDeleted(program, in: context)
        program.delete()
        try context.save()
        let rows = records(HistoryExport.csv(for: [], saved: try HistoryArchive.records(in: context), unit: .pounds))
        #expect(!rows.isEmpty && rows.allSatisfy { $0["Program Status"] == "Deleted" })
    }

    @Test("A program deleted before any workout started leaves nothing behind")
    func untrainedProgram() throws {
        let context = container.mainContext
        let template = TemplateProgram(templateName: "Push", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        _ = template.addTemplateWorkout()
        context.insert(template)
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        try context.insertAndSave(program)

        try HistoryArchive.programWillBeDeleted(program, in: context)
        program.delete()
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<HistoryRecord>()) == 0)
    }

    @Test("The running program is read live, marked in progress")
    func runningProgramIsLive() throws {
        let context = container.mainContext
        let workout = try makeLoggedWorkout()
        let program = try #require(workout.programWeekValue?.programValue)

        let url = try HistoryExport.writeFile(from: context, unit: .pounds)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try context.fetchCount(FetchDescriptor<HistoryRecord>()) == 0)
        let rows = records(try String(contentsOf: url, encoding: .utf8))
        #expect(!rows.isEmpty && rows.allSatisfy { $0["Program Status"] == "In Progress" && $0["Program ID"] == program.syncID?.uuidString })
    }

    @Test("Programs that ended before the long view existed are saved once, and kept in start order")
    func backfill() throws {
        let context = container.mainContext
        let first = try #require(try makeLoggedWorkout().programWeekValue?.programValue)
        first.finishWorkout(try #require(first.programWeeks.first?.workouts.first))
        // As if saved by a version without the long view.
        for record in try context.fetch(FetchDescriptor<HistoryRecord>()) { context.delete(record) }
        try context.save()
        let second = try #require(try makeLoggedWorkout(at: start + 86_400).programWeekValue?.programValue)

        try HistoryArchive.saveEndedPrograms(in: context)
        try HistoryArchive.saveEndedPrograms(in: context)
        let saved = try HistoryArchive.records(in: context)
        #expect(Set(saved.compactMap(\.programID)) == [first.syncID])

        let rows = records(HistoryExport.csv(for: [second, first], saved: saved, unit: .pounds))
        #expect(rows.filter { $0["Program #"] == "1" }.allSatisfy { $0["Program ID"] == first.syncID?.uuidString })
        #expect(rows.filter { $0["Program #"] == "2" }.allSatisfy { $0["Program ID"] == second.syncID?.uuidString })
        #expect(rows.count == HistoryExport.rows(for: first).count + HistoryExport.rows(for: second).count)
    }

    @Test("Each launch skips programs already saved, saves trained ones that aren't, and leaves untrained ones alone")
    func launchSaveChecksSavedFirst() throws {
        let context = container.mainContext
        let saved = try #require(try makeLoggedWorkout().programWeekValue?.programValue)
        saved.finishWorkout(try #require(saved.programWeeks.first?.workouts.first))
        let batch = try HistoryArchive.records(in: context).map(\.batchID)
        #expect(!batch.isEmpty)
        #expect(try !HistoryArchive.save(saved, in: context), "already saved")
        #expect(try HistoryArchive.records(in: context).map(\.batchID) == batch)

        let unsaved = try #require(try makeLoggedWorkout(at: start + 86_400).programWeekValue?.programValue)
        #expect(try HistoryArchive.save(unsaved, in: context))
        #expect(try !HistoryArchive.save(unsaved, in: context))

        // A program that never trained gets no sync IDs and no rows, as before.
        let template = TemplateProgram(templateName: "Push", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        _ = template.addTemplateWorkout()
        context.insert(template)
        let untrained = Program(programLengthWeeks: 1, templateProgram: template)
        try context.insertAndSave(untrained)
        let untrainedID = untrained.syncID
        #expect(try !HistoryArchive.save(untrained, in: context))
        #expect(untrained.syncID == untrainedID)
        #expect(Set(try HistoryArchive.records(in: context).compactMap(\.programID)) == [saved.syncID, unsaved.syncID])
    }

    @Test("When two iPhones saved the same program, the export keeps one copy")
    func duplicateBatches() throws {
        let context = container.mainContext
        let workout = try makeLoggedWorkout()
        let program = try #require(workout.programWeekValue?.programValue)
        program.finishWorkout(workout)
        let rows = HistoryExport.rows(for: program)
        // The other iPhone's copy, saved a little later, arriving through iCloud.
        let otherBatch = UUID()
        for (order, row) in rows.enumerated() {
            context.insert(HistoryRecord(row, batchID: otherBatch, savedAt: .now + 60, programStarted: start, order: order))
        }
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<HistoryRecord>()) == rows.count * 2)
        let saved = try HistoryArchive.records(in: context)
        #expect(saved.count == rows.count && saved.allSatisfy { $0.batchID != otherBatch })
    }

    // MARK: Helpers

    /// A one-day program: Bench and a weighted dip in a superset, one set of each logged,
    /// the rest skipped, then rated.
    private func makeLoggedWorkout(at start: Date? = nil) throws -> Workout {
        let start = start ?? self.start
        let context = container.mainContext
        let bench = Exercise(exerciseName: "Bench", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)
        let dip = Exercise(exerciseName: #"Dip, "Weighted""#, exerciseEquipment: .loadableBodyweight, primaryMuscleFocus: .chest, userCreated: true)
        [bench, dip].forEach(context.insert)
        let template = TemplateProgram(templateName: "Push", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        let templateWorkout = template.addTemplateWorkout()
        for exercise in [bench, dip] { _ = templateWorkout.addTemplateExercise(exercise: exercise) }
        context.insert(template)
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        try context.insertAndSave(program)

        let workout = try #require(program.programWeeks.first?.workouts.first)
        let superset = UUID()
        workout.workoutExercises.forEach { $0.setSuperset(superset) }
        program.start()
        workout.startAndCascade(at: start)

        let (benchEntry, dipEntry) = (workout.workoutExercises[0], workout.workoutExercises[1])
        log(benchEntry.workingSets[0], reps: 8, weightTenthsPounds: 2250, in: benchEntry, at: start + 120)
        log(dipEntry.workingSets[0], reps: 10, weightTenthsPounds: 0, in: dipEntry, at: start + 200)
        for entry in [benchEntry, dipEntry] {
            entry.skipRemainingSets()
            entry.addFeedback(feedback: ExerciseFeedback(repsInReserve: .two, levelOfPain: .mild))
        }
        return workout
    }

    private func log(_ workoutSet: WorkoutSet, reps: Int, weightTenthsPounds: Int, in entry: WorkoutExercise, at date: Date) {
        workoutSet.reps = reps
        workoutSet.weightTenthsPounds = weightTenthsPounds
        entry.completeSet(workoutSet, at: date)
    }

    /// Rows after the header, keyed by column.
    private func records(_ csv: String) -> [[String: String]] {
        let table = parse(csv)
        return table.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(table[0], $0)) }
    }

    /// Reads RFC 4180 CSV: quoted fields may hold commas, line breaks and doubled quotes.
    private func parse(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var characters = csv.makeIterator()
        while let character = characters.next() {
            if quoted {
                if character == "\"" {
                    quoted = false
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                // A quote right after a closing quote is a doubled one.
                if !field.isEmpty { field.append("\"") }
                quoted = true
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character.isNewline {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
        }
        return rows
    }
}
