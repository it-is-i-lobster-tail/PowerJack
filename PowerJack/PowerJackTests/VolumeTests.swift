//
//  VolumeTests.swift
//  PowerJackTests
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct VolumeTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let day: TimeInterval = 24 * 60 * 60

    @Test("Each completed working set counts 1 for the primary muscle and 0.5 for each secondary")
    func loggedSetsCountSecondaryMusclesAsHalf() {
        let exercises = PowerJackSeed.makeExercises()
        // Bench (chest; triceps, shoulders) and Pull Up (back; biceps, forearms).
        let workout = PowerJackSeed.makeWorkout(
            order: 0,
            exercises: [exercises[0], exercises[2]],
            sets: [
                sets([.complete, .complete, .complete]),
                sets([.complete, .complete, .skipped]),
            ]
        )
        container.mainContext.insert(workout)

        #expect(workout.loggedSetsByMuscle == [
            .chest: 3, .triceps: 1.5, .shoulders: 1.5,
            .back: 2, .biceps: 1, .forearms: 1,
        ])
    }

    @Test("A log reads back the sets it was given and zero for every other muscle")
    func logColumns() {
        let log = WorkoutLog(date: .now, setsByMuscle: [.chest: 3, .hamstrings: 1.5])

        #expect(log.sets(for: .chest) == 3)
        #expect(log.sets(for: .hamstrings) == 1.5)
        #expect(log.sets(for: .back) == 0)
    }

    @Test("Averages divide by the weeks since the first workout when that's inside the range")
    func averagesForNewUser() {
        let now = Date.now
        let logs = [
            WorkoutLog(date: now.addingTimeInterval(-14 * day), setsByMuscle: [.chest: 10]),
            WorkoutLog(date: now.addingTimeInterval(-7 * day), setsByMuscle: [.chest: 10]),
        ]

        let averages = WeeklyVolume.averages(of: logs, in: .days90, now: now)

        #expect(averages[.chest] == 10)
        #expect(averages[.back] == 0)
    }

    @Test("Workouts before the range are left out")
    func rangeExcludesOlderLogs() {
        let now = Date.now
        let logs = [
            WorkoutLog(date: now.addingTimeInterval(-120 * day), setsByMuscle: [.chest: 100]),
            WorkoutLog(date: now.addingTimeInterval(-3 * day), setsByMuscle: [.chest: 30]),
        ]

        let averages = WeeklyVolume.averages(of: logs, in: .days90, now: now)
        // 90 calendar days back, which is an hour more or less than 90 × 24 hours across a clock change.
        let start = VolumeRange.days90.start(before: now)!
        let weeks = now.timeIntervalSince(start) / (7 * day)

        #expect(abs((averages[.chest] ?? 0) - 30 / weeks) < 0.001)
    }

    @Test("Current Program excludes logs from other programs trained on the same date")
    func currentProgramVolume() throws {
        let scenario = PowerJackSeed.weekOneProgress()
        let session = try #require(scenario.program.nextWorkout?.syncID)
        let now = Date.now
        let logs = [
            WorkoutLog(date: now, setsByMuscle: [.chest: 3], sessionID: session),
            WorkoutLog(date: now, setsByMuscle: [.chest: 7], sessionID: UUID()),
        ]
        #expect(WeeklyVolume.averages(of: logs, in: .currentProgram, currentProgram: scenario.program, now: now)[.chest] == 3)
        #expect(WeeklyVolume.averages(of: logs, in: .currentProgram, now: now).isEmpty)
    }

    @Test("30 days includes its boundary and the picker offers the supported ranges")
    func thirtyDayVolume() throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 13)))
        #expect(VolumeRange.allCases.map(\.name) == ["Current Program", "30 days", "90 days", "Year to date", "1 year"])
        #expect(VolumeRange.days30.start(before: now, calendar: calendar) == start)
        let logs = [
            WorkoutLog(date: start.addingTimeInterval(-1), setsByMuscle: [.back: 100]),
            WorkoutLog(date: start, setsByMuscle: [.back: 3]),
            WorkoutLog(date: now, setsByMuscle: [.back: 5])
        ]
        let weeks = now.timeIntervalSince(start) / (7 * day)
        #expect(abs((WeeklyVolume.averages(of: logs, in: .days30, now: now)[.back] ?? 0) * weeks - 8) < 0.0001)
    }

    @Test("Program type filters use recorded types and resolve older logs by workout")
    func programTypeFilter() throws {
        let scenario = PowerJackSeed.weekOneProgress()
        let session = try #require(scenario.program.nextWorkout?.syncID)
        let oldLog = WorkoutLog(date: .now, setsByMuscle: [.chest: 1], sessionID: session)
        let strength = WorkoutLog(date: .now, setsByMuscle: [.chest: 2], programType: .strength)
        let unknown = WorkoutLog(date: .now, setsByMuscle: [.chest: 4], sessionID: UUID())
        let logs = [oldLog, strength, unknown]

        let selected = WeeklyVolume.logs(logs, matching: [scenario.program.templateType, .strength], programs: [scenario.program])
        #expect(selected.map { $0.sets(for: .chest) } == [1, 2])
        #expect(WeeklyVolume.logs(logs, matching: [], programs: []).count == 3)
        #expect(WeeklyVolume.logs(logs, matching: [.strength], programs: []).first === strength)
    }

    @Test("Year to date starts on January 1 and one year rolls back by a calendar year")
    func yearlyRangeBoundaries() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)))
        let january = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let previousYear = try #require(calendar.date(from: DateComponents(year: 2025, month: 3, day: 15)))

        #expect(VolumeRange.yearToDate.start(before: now, calendar: calendar) == january)
        #expect(VolumeRange.year.start(before: now, calendar: calendar) == previousYear)
    }

    @Test("Less than a week of history still counts as one week")
    func atLeastOneWeek() {
        let now = Date.now
        let logs = [WorkoutLog(date: now.addingTimeInterval(-1 * day), setsByMuscle: [.quads: 6])]

        #expect(WeeklyVolume.averages(of: logs, in: .days30, now: now)[.quads] == 6)
    }

    @Test("Volume trend keeps separate muscle totals and skips the unfinished week")
    func volumeTrend() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 4)))
        let first = try #require(calendar.dateInterval(of: .weekOfYear, for: date)?.start)
        let third = first.addingTimeInterval(14 * day)
        let fifth = first.addingTimeInterval(28 * day)
        let logs = [
            WorkoutLog(date: first, setsByMuscle: [.chest: 8, .back: 20]),
            WorkoutLog(date: third, setsByMuscle: [.chest: 4]),
            WorkoutLog(date: fifth, setsByMuscle: [.chest: 12]),
            WorkoutLog(date: fifth.addingTimeInterval(day), setsByMuscle: [.chest: 100])
        ]
        let now = fifth.addingTimeInterval(day)
        let trend = WeeklyVolume.trend(of: logs, in: .days90, selectedMuscles: [.chest, .back], now: now, calendar: calendar)
        let chestOnly = WeeklyVolume.trend(of: logs, in: .days90, selectedMuscles: [.chest], now: now, calendar: calendar)

        #expect(trend.map { $0.setsByMuscle[.chest, default: 0] } == [8, 0, 4, 0])
        #expect(trend.map { $0.setsByMuscle[.back, default: 0] } == [20, 0, 0, 0])
        #expect(chestOnly.allSatisfy { $0.setsByMuscle[.back] == nil })
    }

    @Test("No history has no averages")
    func emptyHistory() {
        #expect(WeeklyVolume.averages(of: [], in: .days30).isEmpty)
    }

    @Test("Month searches use the selected calendar weeks across years")
    func searchMonthVolume() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2
        func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
        }
        let firstJune = try date(2024, 6, 1)
        let secondJune = try date(2025, 6, 1)
        let now = try date(2025, 7, 10)
        let logs = try [
            WorkoutLog(date: firstJune.addingTimeInterval(-1), setsByMuscle: [.chest: 100]),
            WorkoutLog(date: firstJune, setsByMuscle: [.chest: 10]),
            WorkoutLog(date: date(2024, 7, 1).addingTimeInterval(-1), setsByMuscle: [.chest: 5]),
            WorkoutLog(date: date(2024, 7, 1), setsByMuscle: [.chest: 100]),
            WorkoutLog(date: secondJune, setsByMuscle: [.chest: 15]),
            WorkoutLog(date: date(2025, 7, 1), setsByMuscle: [.chest: 100]),
        ]
        let june = WorkoutDateFilter.month(6, year: nil)
        let averages = WeeklyVolume.averages(of: logs, in: .currentProgram, dateFilter: june, now: now, calendar: calendar)
        #expect(abs((averages[.chest] ?? 0) - 3.5) < 0.001)

        let trend = WeeklyVolume.trend(of: logs, in: .currentProgram, dateFilter: june, now: now, calendar: calendar)
        #expect(Set(trend.compactMap(\.periodStart)) == [firstJune, secondJune])
        #expect(trend.count == 11)
        #expect(trend.reduce(0) { $0 + $1.setsByMuscle[.chest, default: 0] } == 30)

        let july = WorkoutDateFilter.month(7, year: 2023)
        #expect(WeeklyVolume.averages(of: logs, in: .days90, dateFilter: july, now: now, calendar: calendar).isEmpty)
    }

    @Test("Day searches use each matching local date and exclude neighboring workouts")
    func searchDayVolume() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
        }

        let first = try date(2024, 11, 9)
        let second = try date(2025, 11, 9)
        let now = try date(2025, 12, 1)
        let logs = try [
            WorkoutLog(date: first.addingTimeInterval(-1), setsByMuscle: [.back: 100]),
            WorkoutLog(date: first, setsByMuscle: [.back: 4]),
            WorkoutLog(date: date(2024, 11, 10), setsByMuscle: [.back: 100]),
            WorkoutLog(date: date(2025, 11, 10).addingTimeInterval(-1), setsByMuscle: [.back: 6]),
        ]
        let filter = WorkoutDateFilter.day(9, month: 11, year: nil)
        let averages = WeeklyVolume.averages(of: logs, in: .currentProgram, dateFilter: filter, now: now, calendar: calendar)
        #expect(averages[.back] == 5)
        let trend = WeeklyVolume.trend(of: logs, in: .currentProgram, dateFilter: filter, now: now, calendar: calendar)
        #expect(trend.compactMap(\.periodStart) == [first, second])
        #expect(trend.map { $0.setsByMuscle[.back] } == [4, 6])

        let leapDay = WorkoutDateFilter.day(29, month: 2, year: nil)
        let periods = try leapDay.periods(from: date(2023, 1, 1), through: now, calendar: calendar)
        #expect(periods.map(\.start) == [try date(2024, 2, 29)])
    }

    @Test("Tiers follow the rounded weekly set count", arguments: [
        (0.0, VolumeTier.tooLittle), (2.4, .tooLittle), (2.5, .maintenance), (5.0, .maintenance),
        (6.0, .growth), (12.4, .growth), (13.0, .maxGrowth), (25.0, .maxGrowth), (26.0, .tooMuch),
    ])
    func tiers(weeklySets: Double, tier: VolumeTier) {
        #expect(VolumeTier(weeklySets: weeklySets) == tier)
    }

    @Test("Finishing a workout writes a log that survives deleting its program")
    func logOutlivesProgram() throws {
        let scenario = PowerJackSeed.weekOneProgress()
        let context = scenario.container.mainContext
        let program = scenario.program
        let workout = try #require(program.nextWorkout)
        if workout.status == .planned {
            workout.startAndCascade()
        }
        for workoutExercise in workout.workoutExercises {
            for workoutSet in workoutExercise.workingSets where workoutSet.status == .active {
                workoutSet.reps = 8
                workoutSet.complete()
            }
        }
        let expected = workout.loggedSetsByMuscle

        program.finishWorkout(workout)
        try context.save()
        program.stop()
        program.stopAndCascade()
        program.delete()
        try context.save()

        let logs = try context.fetch(FetchDescriptor<WorkoutLog>())
        #expect(logs.count == 1)
        for (muscle, sets) in expected {
            #expect(logs.first?.sets(for: muscle) == sets)
        }
    }

    @Test("Exercise graphs scope and renumber completed sets across programs")
    func exerciseHistoryRanges() throws {
        let calendar = Calendar.current
        func date(_ year: Int, _ month: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: 10))!
        }
        let lift = PowerJackSeed.makeExercises()[0]
        func program(_ name: String, dates: [Date], active: Bool) throws -> Program {
            let template = TemplateProgram(templateName: name, workoutsPerWeek: dates.count, templateMuscleFocus: [])
            let program = Program(programLengthWeeks: 1, templateProgram: template)
            container.mainContext.insert(program)
            let week = try #require(program.programWeeks.first)
            for (index, date) in dates.enumerated() {
                let workout = PowerJackSeed.makeWorkout(order: index, exercises: [lift], sets: [sets([.complete, .skipped])])
                workout.start(at: date)
                week.attach(workout)
            }
            program.start()
            if !active { program.complete() }
            return program
        }

        let current = try program("Current", dates: [date(2026, 11)], active: true)
        let older = try program("Past", dates: [date(2023, 2), date(2026, 1), date(2026, 10)], active: false)
        try container.mainContext.save()
        let ranges: [(VolumeRange, [String])] = [
            (.currentProgram, ["Current"]), (.days30, ["Current"]), (.days90, ["Past", "Current"])
        ]
        for (range, names) in ranges {
            let history = try #require(ProgramExerciseHistory.exercises(in: [current, older], range: range,
                                                                         now: date(2026, 12)).first)
            #expect(history.sessions.map(\.programName) == names)
            #expect(history.sets.map(\.id) == Array(1...names.count))
            #expect(history.sets.map(\.sessionIndex) == Array(names.indices))
            if range == .days90 {
                let periods = ExercisePeriod.weeks(history, now: date(2026, 12), calendar: calendar)
                #expect(periods.flatMap(\.sessionIndices) == Array(names.indices))
                #expect(periods.filter { !$0.sessionIndices.isEmpty }.allSatisfy { $0.reps.value == 8 })
                #expect(periods.contains { $0.sessionIndices.isEmpty && $0.load.value == nil })
            }
        }
    }

    @Test("Targets includes selected primary muscles and ignores secondary muscles")
    func exerciseHistoryMuscleFilter() throws {
        let exercises = Array(PowerJackSeed.makeExercises().prefix(3))
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: [])
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        container.mainContext.insert(program)
        let week = try #require(program.programWeeks.first)
        week.attach(PowerJackSeed.makeWorkout(order: 0, exercises: exercises, sets: exercises.map { _ in sets([.complete]) }))
        program.start()
        try container.mainContext.save()

        let selected = ProgramExerciseHistory.exercises(in: [program], range: .currentProgram,
                                                       primaryMuscles: [.back, .chest, .glutes])
        #expect(selected.map(\.name) == [exercises[0].exerciseName, exercises[2].exerciseName])
        #expect(ProgramExerciseHistory.exercises(in: [program], range: .currentProgram).count == 3)
    }

    @Test("Brzycki one-rep max uses recorded reserve and rejects sets above the rep limit")
    func oneRepMaxEstimate() throws {
        let exercise = PowerJackSeed.makeExercises()[0]
        let history = ProgramExerciseHistory(id: exercise.persistentModelID, name: exercise.exerciseName,
                                             supportsLoadEstimate: true)
        func set(reps: Int, rir: RepsInReserve?) -> ProgramExerciseHistory.LoggedSet {
            .init(id: 1, sessionIndex: 0, targetReps: nil, reps: reps, targetLoad: nil, load: 1_850, repsInReserve: rir)
        }

        let rated = try #require(history.estimate(set(reps: 6, rir: .two)))
        let unrated = try #require(history.estimate(set(reps: 6, rir: nil)))
        #expect(rated.tenthsPounds == 2_297)
        #expect(unrated.tenthsPounds == 2_148)
        #expect(rated.hasRecordedRIR)
        #expect(!unrated.hasRecordedRIR)
        #expect(history.estimate(set(reps: 9, rir: .two)) == nil)
    }

    @Test("Panning and zooming keep at most five ticks on visible samples, including both ends")
    func historyTicks() {
        #expect(HistoryWindow.tickIndices(in: 6..<18) == [6, 9, 12, 14, 17])
        #expect(HistoryWindow.tickIndices(in: 3..<8) == [3, 4, 5, 6, 7])
        #expect(HistoryWindow.tickIndices(in: 11..<12) == [11])
        #expect(HistoryWindow.tickIndices(in: 0..<0).isEmpty)
    }

    @Test("The history window stays capped at both ends and between items")
    func historyWindow() {
        let count = 47
        let span = HistoryWindow.maximumSpan(count: count)
        #expect(HistoryWindow.indices(count: count, window: (1 - span)...1) == 35..<47)
        #expect(HistoryWindow.indices(count: count, window: 0...span) == 0..<12)
        #expect(HistoryWindow.indices(count: count, window: 0.103...(0.103 + span)).count == 12)
        #expect(HistoryWindow.indices(count: 5, window: 0...1) == 0..<5)
        #expect(HistoryWindow.index(at: 1, count: count, window: (1 - span)...1) == 46)
    }

    @Test("Period comparisons preserve separate target and actual means and missing values")
    func periodComparison() {
        var period = ExercisePeriod(id: .now, index: 0)
        period.record(.init(id: 1, sessionIndex: 0, targetReps: 10, reps: 8, targetLoad: 500, load: 450))
        period.record(.init(id: 2, sessionIndex: 0, targetReps: 9, reps: 10, targetLoad: nil, load: 500))
        #expect(period.targetReps.value == 9.5)
        #expect(period.reps.value == 9)
        #expect(period.targetLoad.value == 500)
        #expect(period.load.value == 475)
    }

    private func sets(_ statuses: [Status]) -> [PowerJackSeed.SeedSet] {
        statuses.map {
            PowerJackSeed.SeedSet(
                plannedReps: 8,
                plannedWeightTenthsPounds: 1000,
                actualReps: 8,
                actualWeightTenthsPounds: 1000,
                status: $0
            )
        }
    }
}
