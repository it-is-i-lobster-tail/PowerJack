//
//  HistoryExportTests.swift
//  PowerJackTests
//
//  The workout history CSV: one row per set, with what each set belongs to, in a form
//  any spreadsheet reads the same way.
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
        #expect(bench["Set Started"] == start.formatted(.iso8601TimeZone))
        #expect(bench["Set Logged"] == (start + 120).formatted(.iso8601TimeZone))
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

    @Test("A name with commas and quotes comes back exactly as typed")
    func quoting() throws {
        let workout = try makeLoggedWorkout()
        let csv = HistoryExport.csv(for: [try #require(workout.programWeekValue?.programValue)], unit: .pounds)
        #expect(csv.contains(#""Dip, ""Weighted"""#))
        #expect(records(csv).contains { $0["Exercise"] == #"Dip, "Weighted""# })
    }

    @Test("The file is written and named for today")
    func file() throws {
        _ = try makeLoggedWorkout()
        let url = try HistoryExport.writeFile(from: container.mainContext, unit: .pounds)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent.hasPrefix("PowerJack History ") && url.pathExtension == "csv")
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("Program #,Program,"))
    }

    // MARK: Helpers

    /// A one-day program: Bench and a weighted dip in a superset, one set of each logged,
    /// the rest skipped, then rated.
    private func makeLoggedWorkout() throws -> Workout {
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

private extension FormatStyle where Self == Date.ISO8601FormatStyle {
    static var iso8601TimeZone: Date.ISO8601FormatStyle { Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: .current) }
}
