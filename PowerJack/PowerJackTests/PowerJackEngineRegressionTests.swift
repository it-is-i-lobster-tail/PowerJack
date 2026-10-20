//
//  PowerJackEngineRegressionTests.swift
//  PowerJackTests
//
//  Bugs the PowerJack simulation found (PowerJackSimulation), each pinned to the rule it broke so it
//  stays fixed. Fixtures are in PowerJackEngineTests.swift.
//

import Foundation
import Testing
@testable import PowerJack

extension PowerJackEngineTests {
    // MARK: R5.2 blocks

    @Test("Blocks run every BUILD week R5.2 lays out, to the final column: a 6-week program is BBBBB D")
    func longBlocks() {
        let expected: [Int: (types: String, columns: [Int])] = [
            6: ("BBBBBD", [1, 2, 3, 3, 4]),
            7: ("BBBBBBD", [1, 2, 2, 3, 3, 4]),
            11: ("BBBBBDBBBBD", [1, 2, 3, 3, 4, 1, 2, 3, 4]),
            12: ("BBBBBDBBBBBD", [1, 2, 3, 3, 4, 1, 2, 3, 3, 4]),
        ]
        for (programWeeks, want) in expected {
            let logs = calendar(programWeeks: programWeeks)
            #expect(logs.map { $0.type == .build ? "B" : "D" }.joined() == want.types, "\(programWeeks) weeks")
            #expect(logs.filter { $0.type == .build }.map(\.column) == want.columns, "\(programWeeks) weeks")
            // The planner replays the same blocks and columns from the stored week types.
            let replayed = PowerJackCalendar.replay(logs, programWeeks: programWeeks)
            #expect(replayed.map(\.column) == logs.map(\.column) && replayed.map(\.block) == logs.map(\.blockNumber))
        }
    }

    // MARK: R2.3 band mode

    @Test("Band mode works up from the lift's own reps: 95 lb x 7 jumps to 100 x 5, and R2.3 resumes at 100")
    func bandModeFromOwnReps() throws {
        // R2.3's worked numbers: an overhead press at 95 lb with a 5-lb step (5.3%) runs 5-7 reps.
        let first = weekLog([
            [entry(press, sets: Array(repeating: (7, 95), count: 3), target: 2, loadTarget: 95, tap: 2)],
            [entry(press, sets: Array(repeating: (8, 90), count: 3), target: 2, loadTarget: 90, tap: 2)],
        ], column: 2)
        let second = try #require(PowerJackEngine.nextWeek(after: [first], context: context()))
        #expect(second.workouts[0][0].sets == Array(repeating: PowerJackSetPlan(reps: 5, load: 100), count: 3))
        #expect(second.workouts[0][0].reasons.contains(.loadJump))

        // At 100 lb the step is 5.0%, so R2.3 ramps from 100 rather than falling back to 95.
        let secondLog = weekLog(second.workouts.map { $0.map { logged($0, tap: 2) } }, column: second.header.column, blockWeek: 2)
        let third = try #require(PowerJackEngine.nextWeek(after: [first, secondLog], context: context()))
        #expect(third.workouts[0][0].sets.allSatisfy { $0.reps == 5 && $0.load == 100 })
    }

    // MARK: Limits

    @Test("No load is planned past the 1,000 lb a set can log")
    func thousandPoundLimit() throws {
        let plan = PowerJackEngine.firstWeek([[legPress], [legPress]], context: context())
        // 1,000 lb x 5 with 3 left calibrates an H anchor near 1,200 lb.
        let week = weekLog([
            [logged(plan.workouts[0][0], load: 1000, tap: 3)],
            [logged(plan.workouts[1][0], load: 900, tap: 3)],
        ])
        let next = try #require(PowerJackEngine.nextWeek(after: [week], context: context()))
        let loads = next.workouts.joined().flatMap { $0.sets.compactMap(\.load) }
        #expect(loads.contains(1000) && loads.allSatisfy { $0 <= 1000 })
    }

    @Test("No S or A set is planned past its widening limit, whatever was logged")
    func repsCappedAtTheLimit() throws {
        // A pulldown swapped in and taken to 40 reps at a light load: range 6-10, so 20 at most.
        var swapped = entry(pulldown, sets: [(40, 50), (40, 50)], target: 2, tap: 5)
        swapped.sets = swapped.sets.map { set in
            var set = set
            set.plannedReps = nil
            return set
        }
        let next = try #require(PowerJackEngine.nextWeek(after: [weekLog([[swapped]])], context: context()))
        #expect(next.workouts[0][0].sets.allSatisfy { ($0.reps ?? 0) <= 20 })
    }

    @Test("A load under one step is never cut upward: a 2.5 lb raise deloads at fewer reps and holds on a shortfall")
    func tinyLoads() throws {
        let build = weekLog([[entry(lateralRaise, sets: [(12, 2.5), (12, 2.5)], target: 2, tap: 2)]])
        let deload = builder([build], structure: [[lateralRaise]]).build(header: deloadHeader)
        #expect(deload.workouts[0][0].sets == [PowerJackSetPlan(reps: 7, load: 2.5)])

        // Far under the range: R2.4's 5% cut has no lighter step to go to.
        let short = weekLog([[entry(lateralRaise, sets: [(8, 2.5), (8, 2.5)], planned: 12, target: 2, tap: 0)]])
        let next = try #require(PowerJackEngine.nextWeek(after: [short], context: context()))
        #expect(next.workouts[0][0].sets.allSatisfy { $0.load == 2.5 })
    }

    @Test("A second deload repeats the first even when a check-in's Reset replaced its sets, and main lifts keep 3+ reps")
    func secondDeloadAfterReset() {
        let build = weekLog([[entry(squat, tag: .heavy, sets: [(5, 300), (5, 300), (5, 300), (5, 300)], target: 1, loadTarget: 300, tap: 1)]])
        let first = builder([build], structure: [[squat]]).build(header: deloadHeader)
        #expect(first.workouts[0][0].sets == Array(repeating: PowerJackSetPlan(reps: 5, load: 270), count: 2))

        // Reset gave the deload two fresh sets with nothing planned, loaded by feel at 135 for 2.
        var reset = entry(squat, sets: [(2, 135), (2, 135)], target: 3, tap: 0)
        reset.sets = reset.sets.map { set in
            var set = set
            (set.plannedReps, set.plannedLoad) = (nil, nil)
            return set
        }
        let deloaded = PowerJackWeekLog(type: .deload, blockWeek: 0, column: 0, workouts: [PowerJackWorkoutLog(entries: [reset])])
        #expect(builder([build, deloaded], structure: [[squat]]).build(header: deloadHeader).workouts[0][0].sets == first.workouts[0][0].sets)

        // A BUILD week whose sets were reset deloads a main lift at 3 reps or more, not at 60% of the 2 done.
        let resetBuild = weekLog([[reset]])
        let deload = builder([resetBuild], structure: [[squat], [squat]]).build(header: deloadHeader)
        #expect(deload.workouts[0][0].sets.allSatisfy { ($0.reps ?? 0) >= PowerJackRules.mainHeavyMinReps })
    }

    // MARK: Loads the lifter chose

    @Test("After a calibrating exposure a held slot keeps the lifter's weight instead of going blank")
    func calibratedHoldKeepsTheLoad() throws {
        let plan = PowerJackEngine.firstWeek([[squat, row]], context: context())
        #expect(plan.workouts[0][1].calibrating && plan.workouts[0][1].sets.allSatisfy { $0.load == nil })
        // Loaded by feel at 150 lb and a rep under the range's 6: a hold, not a cut.
        let week = weekLog([[logged(plan.workouts[0][0], load: 225, tap: 3), logged(plan.workouts[0][1], reps: 5, load: 150, tap: 2)]])
        let next = try #require(PowerJackEngine.nextWeek(after: [week], context: context()))
        #expect(next.workouts[0][1].sets.allSatisfy { $0.load == 150 && $0.reps == 6 })
    }

    @Test("A new block starts a slot left blank in its BUILD weeks from what the lifter lifted since")
    func blankSlotStartsFromHistory() {
        let done = Date.now.addingTimeInterval(-2 * 86_400)
        let blank = PowerJackEntryLog(
            exercise: row, sets: Array(repeating: PowerJackSetLog(plannedReps: 6), count: 2), target: 3, calibrating: true
        )
        // Loaded by feel in the deload: 150 lb for 6 with 3 left.
        let deloaded = PowerJackEntryLog(exercise: row, sets: [.done(6, at: 150, date: done)], rir: 3, pain: LevelOfPain.none)
        let weeks = [
            weekLog([[blank]]),
            PowerJackWeekLog(type: .deload, blockWeek: 0, column: 0, workouts: [PowerJackWorkoutLog(entries: [deloaded])]),
        ]
        let history = { (id: AnyHashable) in
            id == self.row.id ? [PowerJackExposure(date: done, entry: deloaded, weekType: .deload)] : []
        }
        let start = builder(weeks, structure: [[row]], history: history).build(header: blockStartHeader)
        #expect(!start.workouts[0][0].calibrating)
        #expect(start.workouts[0][0].sets.allSatisfy { $0.load == 150 })
    }

    @Test("A main lift whose tag changes mid-block starts again as the new tag: straight sets, no TOP set")
    func tagChangeRestarts() throws {
        // Last week the deadlift was trained once (a TOP set, then BACK sets) and a swap put it in a second workout.
        var once = entry(deadlift, tag: .topAndBack, sets: [(5, 355), (8, 320), (8, 320)], target: 2, loadTarget: 320, tap: 2, topRIR: 2)
        once.role = PowerJackSlotRole(role: .main, tag: .topAndBack)
        var swappedIn = entry(deadlift, sets: [(8, 300), (8, 300)], target: 2, tap: 2)
        swappedIn.unplanned = true
        let next = try #require(PowerJackEngine.nextWeek(
            after: [weekLog([[once], [swappedIn]], column: 2)],
            context: context(history: anchorHistory)
        ))
        let heavy = next.workouts[0][0]
        #expect(heavy.role == PowerJackSlotRole(role: .main, tag: .heavy))
        #expect(heavy.topSets == 0 && heavy.sets.allSatisfy { $0.reps == 5 && $0.load != nil })
        let volume = next.workouts[1][0]
        #expect(volume.topSets == 0 && volume.sets.allSatisfy { $0.reps == 8 && $0.load != nil })
    }

    // MARK: R2.5 and R10.7 load cap

    @Test("A slot new to the plan starts at most 10% over its exercise's best load of the last 14 days (R10.7)")
    func historyStartIsCapped() {
        let done = Date.now.addingTimeInterval(-3 * 86_400)
        let lifted = PowerJackEntryLog(exercise: row, sets: [.done(20, at: 100, date: done)], target: 1, rir: 0, pain: LevelOfPain.none)
        let history = { (id: AnyHashable) in id == self.row.id ? [PowerJackExposure(date: done, entry: lifted)] : [] }
        let plan = PowerJackEngine.firstWeek([[squat, row]], context: context(history: history))
        // 100 lb x 20 to failure puts the row's e1RM near 169 lb, so 6 reps at 3 left would be 135.
        #expect(plan.workouts[0][1].sets.allSatisfy { $0.load == 110 })
    }

    @Test("After two weeks away a TOP set is capped by its own best, not by its BACK sets (R2.5)")
    func topSetCapReadsTheTopSet() throws {
        let away = Date.now.addingTimeInterval(-20 * 86_400)
        var last = entry(deadlift, tag: .topAndBack, sets: [(5, 250), (8, 215), (8, 215)], target: 1, loadTarget: 215, tap: 2, topRIR: 2)
        last.topLoadTarget = 250
        last.sets = last.sets.map { set in
            var set = set
            set.completedAt = away
            return set
        }
        let history = { (id: AnyHashable) in
            id == self.deadlift.id ? [PowerJackExposure(date: away, entry: last, weekType: .build, tag: .topAndBack)] : []
        }
        let next = try #require(PowerJackEngine.nextWeek(after: [weekLog([[last]], column: 4)], context: context(history: history)))
        #expect(next.workouts[0][0].sets.first?.load == 250)
    }

    // MARK: R10 pain

    @Test("Severe pain opens the check-in before every next exposure until the exercise is done again")
    func checkInCarries() throws {
        let lastDone = Date.now.addingTimeInterval(-9 * 86_400)
        var hurt = entry(squat, sets: [(5, 300), (5, 300)], target: 2, loadTarget: 300, tap: 2)
        hurt.pain = .severe
        let history = { (_: AnyHashable) in [PowerJackExposure(date: lastDone, entry: hurt, weekType: .build, tag: .topAndBack)] }
        // Last week the check-in was answered Skip: nothing done.
        var skipped = entry(squat, sets: [(5, 270)], target: 2, loadTarget: 300, tap: 2)
        skipped.sets = [PowerJackSetLog(plannedReps: 5, plannedLoad: 270, isSkipped: true)]
        (skipped.rir, skipped.pain) = (nil, nil)
        let weeks = [weekLog([[skipped]])]

        let next = try #require(PowerJackEngine.nextWeek(after: weeks, context: context(history: history)))
        #expect(next.workouts[0][0].checkInPain == .severe)
        #expect(next.workouts[0][0].sets == [PowerJackSetPlan(reps: 5, load: 270)])
        // In a deload and at a block start too.
        let weekBuilder = builder(weeks, structure: [[squat]], history: history)
        #expect(weekBuilder.build(header: deloadHeader).workouts[0][0].checkInPain == .severe)
        #expect(weekBuilder.build(header: blockStartHeader).workouts[0][0].checkInPain == .severe)
    }

    @Test("A calibrating exposure done in pain doesn't calibrate: the next one does (R8.8)")
    func painfulCalibrationWaits() throws {
        let plan = PowerJackEngine.firstWeek([[squat], [squat]], context: context())
        var hurt = logged(plan.workouts[0][0], load: 225, tap: 3)
        hurt.pain = .severe
        let history = { (_: AnyHashable) in [PowerJackExposure(date: .now, entry: hurt, weekType: .build, tag: .heavy)] }
        let week = weekLog([[hurt], [logged(plan.workouts[1][0], load: 185, tap: 3)]])
        let next = try #require(PowerJackEngine.nextWeek(after: [week], context: context(history: history)))
        #expect(next.workouts[0][0].calibrating)
        #expect(next.workouts[0][0].checkInPain == .severe)
    }

    @Test("A pain hold keeps the load the lifter lifted, never more than planned (R10.2)")
    func painHoldKeepsTheLiftedLoad() throws {
        let now = Date.now
        var easy = entry(squat, sets: [(5, 300), (5, 300)], target: 2, loadTarget: 300, tap: 2)
        easy.pain = .none
        // Planned at 300, but Moderate pain kept the lifter at 280.
        var hurt = entry(squat, sets: [(5, 280), (5, 280)], target: 2, loadTarget: 300, tap: 2)
        hurt.sets = hurt.sets.map { set in
            var set = set
            set.plannedLoad = 300
            return set
        }
        hurt.pain = .moderate
        let history = { (_: AnyHashable) in
            [PowerJackExposure(date: now.addingTimeInterval(-7 * 86_400), entry: easy, weekType: .build), PowerJackExposure(date: now, entry: hurt, weekType: .build)]
        }
        let next = try #require(PowerJackEngine.nextWeek(after: [weekLog([[hurt]])], context: context(history: history)))
        #expect(next.workouts[0][0].sets.allSatisfy { $0.load == 280 })
        #expect(next.workouts[0][0].reasons.contains(.painHold))
    }

    @Test("A pain cut that would pass 30% under the pre-pain load holds the lifted load, even with nothing planned (R10.3)")
    func painReduceHoldsAtTheFloor() throws {
        let now = Date.now
        func squatEntry(_ load: Double, pain: LevelOfPain, daysAgo: Double, planned: Bool = true) -> PowerJackEntryLog {
            var logged = entry(squat, sets: [(5, load), (5, load)], target: 2, loadTarget: 300, tap: 2)
            logged.pain = pain
            logged.sets = logged.sets.map { set in
                var set = set
                set.completedAt = now.addingTimeInterval(-daysAgo * 86_400)
                // A check-in's Reset leaves sets with nothing planned.
                if !planned { (set.plannedReps, set.plannedLoad) = (nil, nil) }
                return set
            }
            return logged
        }
        // 300 before the pain, then Moderate twice: 220 is cut 10% to 195, under the 210 floor.
        let entries = [squatEntry(300, pain: .none, daysAgo: 14), squatEntry(300, pain: .moderate, daysAgo: 7), squatEntry(220, pain: .moderate, daysAgo: 0, planned: false)]
        let history = { (_: AnyHashable) in
            zip(entries, [14.0, 7, 0]).map { PowerJackExposure(date: now.addingTimeInterval(-$1 * 86_400), entry: $0, weekType: .build) }
        }
        let next = try #require(PowerJackEngine.nextWeek(after: entries.map { weekLog([[$0]]) }, context: context(history: history)))
        let plan = next.workouts[0][0]
        #expect(plan.reasons.contains(.painReduce))
        #expect(plan.sets.allSatisfy { $0.load == 220 })
    }

    @Test("A new block never raises an exercise in a pain episode above what it last lifted (R10.2)")
    func blockStartHoldsPain() {
        let now = Date.now
        func squatEntry(_ load: Double, pain: LevelOfPain, daysAgo: Double) -> PowerJackExposure {
            var logged = entry(squat, tag: .heavy, sets: [(5, load), (5, load)], target: 2, loadTarget: 300, tap: 2)
            logged.pain = pain
            logged.sets = logged.sets.map { set in
                var set = set
                set.completedAt = now.addingTimeInterval(-daysAgo * 86_400)
                return set
            }
            return PowerJackExposure(date: now.addingTimeInterval(-daysAgo * 86_400), entry: logged, weekType: .build, tag: .heavy)
        }
        // Planned from a 300 lb target, then Moderate pain twice in a row cut the squat to 270.
        let exposures = [squatEntry(300, pain: .none, daysAgo: 21), squatEntry(300, pain: .moderate, daysAgo: 14), squatEntry(270, pain: .moderate, daysAgo: 8)]
        let volume = entry(squat, sets: [(8, 230), (8, 230)], target: 2, loadTarget: 255, tap: 2)
        let weeks = [
            weekLog([[exposures[2].entry], [volume]]),
            PowerJackWeekLog(type: .deload, blockWeek: 0, column: 0, workouts: [PowerJackWorkoutLog(entries: [exposures[2].entry]), PowerJackWorkoutLog(entries: [volume])]),
        ]
        let start = builder(weeks, structure: [[squat], [squat]], history: { _ in exposures }).build(header: blockStartHeader)
        #expect(start.workouts[0][0].sets.allSatisfy { ($0.load ?? 0) <= 270 })
    }

    // MARK: G24 ties

    @Test("Added sets go to muscles in template order when their room ties, the same every time (G24)")
    func addsBreakTiesByTemplateOrder() throws {
        // Nine muscles with the same room, two clean weeks each, and 4 adds a week at most.
        let muscles: [Muscle] = [.biceps, .triceps, .calves, .shoulders, .hamstrings, .abs, .obliques, .forearms, .glutes]
        let day = muscles.map { single("\($0.rawValue)-isolation", $0) }
        let structure = [day, day, day]
        var plan = PowerJackEngine.firstWeek(structure, context: context(weeks: 12))
        var weeks: [PowerJackWeekLog] = []
        for _ in 0..<3 {
            weeks.append(asPlanned(plan, load: 20))
            plan = try #require(PowerJackEngine.nextWeek(after: weeks, context: context(weeks: 12)))
        }
        let added = day.map { exercise in
            plan.workouts.joined().contains { $0.exercise.id == exercise.id && $0.reasons.contains(.addedSet) }
        }
        #expect(added == [true, true, true, true, false, false, false, false, false])
        // The same logs give the same week, however often the engine runs.
        for _ in 0..<20 {
            #expect(try #require(PowerJackEngine.nextWeek(after: weeks, context: context(weeks: 12))) == plan)
        }
    }
}

// MARK: - Fixtures

extension PowerJackEngineTests {
    var deloadHeader: PowerJackWeekPlanHeader {
        PowerJackWeekPlanHeader(type: .deload, blockNumber: 1, blockWeek: 0, column: 0, isBlockStart: false)
    }

    var blockStartHeader: PowerJackWeekPlanHeader {
        PowerJackWeekPlanHeader(type: .build, blockNumber: 2, blockWeek: 1, column: 1, isBlockStart: true)
    }

    func builder(
        _ weeks: [PowerJackWeekLog],
        structure: [[PowerJackExercise]],
        history: @escaping (AnyHashable) -> [PowerJackExposure] = { _ in [] }
    ) -> PowerJackWeekBuilder {
        PowerJackWeekBuilder(context: context(history: history), weeks: weeks, structure: structure, warmupsDisabled: [])
    }

    /// Each week of a program whose BUILD weeks all show a strain sign but are never strained, so no
    /// deload is postponed or brought forward.
    func calendar(programWeeks: Int) -> [PowerJackWeekLog] {
        var logs: [PowerJackWeekLog] = []
        var header = PowerJackCalendar.firstWeek(programWeeks: programWeeks)
        while true {
            logs.append(PowerJackWeekLog(
                type: header.type, blockNumber: header.blockNumber, blockWeek: header.blockWeek, column: header.column,
                workouts: [PowerJackWorkoutLog(entries: [])]
            ))
            guard logs.count < programWeeks else { return logs }
            header = PowerJackCalendar.nextWeek(
                after: logs, programWeeks: programWeeks, strained: { _ in false }, anyStrainSign: { _ in true }, hardDeload: false
            )
        }
    }

    /// A week logged as planned, each slot tapped at its target, at `load` where the plan left it blank.
    func asPlanned(_ plan: PowerJackWeekPlan, load: Double) -> PowerJackWeekLog {
        var week = weekLog(
            plan.workouts.map { $0.map { logged($0, load: $0.exercise.repsOnly || $0.sets.first?.load != nil ? nil : load, tap: $0.target ?? 3) } },
            column: plan.header.column,
            blockWeek: plan.header.blockWeek
        )
        week.type = plan.header.type
        week.blockNumber = plan.header.blockNumber
        return week
    }
}
