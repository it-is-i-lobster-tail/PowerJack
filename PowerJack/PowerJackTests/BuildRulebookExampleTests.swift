//
//  BuildRulebookExampleTests.swift
//  PowerJackTests
//
//  The hypertrophy rulebook's six worked examples, row by row: each week is logged as the "Did" column
//  says, and the engine must plan the "Next week" column. Filler exercises keep each example's muscle at
//  the weekly volume the example states, and are logged on target.
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct BuildRulebookExampleTests {
    @Test("Example 1: an 8-12 dumbbell press climbs, steps and deloads")
    func dumbbellPress() {
        let press = BuildExercise(minReps: 8, maxReps: 12, primary: .chest, fatigueLevel: .moderate)
        var run = ExampleRun([
            (press, 0, plan(3, 10, 600, aim: 3)),
            (fly, 0, plan(4, 12, 300, aim: 3)),
            (machinePress, 1, plan(3, 10, 1000, aim: 3)),
        ])
        run.log(did(10, 10, 10, at: 600, rir: 3))
        #expect(run.plan(of: 0) == [3, 11, 600, 2])
        run.log(did(11, 11, 11, at: 600, rir: 3))
        #expect(run.plan(of: 0) == [3, 12, 600, 2])
        run.log(did(12, 12, 12, at: 600, rir: 2))
        #expect(run.plan(of: 0) == [3, 11, 650, 0])
        #expect(run.code(of: 0) == .loadUp)
        run.log(did(11, 11, 12, at: 650, rir: 0))
        #expect(run.week == BuildWeek(kind: .deload, blockWeek: 5))
        #expect(run.plan(of: 0) == [2, 11, 550, 3])
        run.log(did(11, 11, at: 550, rir: 5))
        #expect(run.week == BuildWeek(kind: .build, blockWeek: 1))
        #expect(run.plan(of: 0) == [3, 9, 650, 3])
        #expect(run.code(of: 0) == .blockRebase)
    }

    @Test("Example 2: two misses in a row on a squat back off 5% in whole steps")
    func squatMisses() {
        let squat = BuildExercise(minReps: 6, maxReps: 10, primary: .quads, secondary: [.glutes, .hamstrings], fatigueLevel: .high)
        var run = ExampleRun([
            (squat, 0, plan(4, 7, 2250, aim: 3)),
            (BuildExercise(minReps: 6, maxReps: 12, primary: .quads, fatigueLevel: .high), 0, plan(3, 10, 3000, aim: 3)),
            (BuildExercise(minReps: 10, maxReps: 20, primary: .quads, fatigueLevel: .low), 1, plan(3, 12, 800, aim: 3)),
            (machinePress, 1, plan(3, 10, 1000, aim: 3)),
            (row, 1, plan(3, 10, 500, aim: 3)),
            (curl, 0, plan(3, 10, 300, aim: 3)),
        ])
        // Week 1 was clean, so week 2 starts from 4 × 8 × 225 with no misses.
        run.log(did(7, 7, 7, 7, at: 2250, rir: 3))
        #expect(run.plan(of: 0) == [4, 8, 2250, 2])
        run.log(did(8, 8, 7, 6, at: 2250, rir: 0))
        #expect(run.plan(of: 0) == [4, 8, 2250, 2])
        #expect(run.code(of: 0) == .holdMiss)
        run.log(did(8, 8, 7, 7, at: 2250, rir: 0))
        #expect(run.plan(of: 0) == [4, 8, 2150, 1])
        #expect(run.code(of: 0) == .loadDown)
        run.log(did(8, 8, 8, 8, at: 2150, rir: 1))
        #expect(run.week == BuildWeek(kind: .deload, blockWeek: 5))
        #expect(run.plan(of: 0) == [2, 8, 1900, 3])
        run.log(did(8, 8, at: 1900, rir: 5))
        #expect(run.plan(of: 0) == [4, 6, 2150, 3])
    }

    @Test("Example 3: elbow pain holds, cuts 10%, then a severe rating cuts 20% behind a check-in")
    func skullCrusherPain() {
        let skullCrusher = BuildExercise(minReps: 8, maxReps: 12, primary: .triceps, fatigueLevel: .moderate)
        var run = ExampleRun([
            (skullCrusher, 0, plan(3, 10, 600, aim: 3)),
            (BuildExercise(minReps: 10, maxReps: 20, primary: .triceps, fatigueLevel: .low), 0, plan(4, 12, 500, aim: 3)),
            (BuildExercise(minReps: 10, maxReps: 20, primary: .triceps, fatigueLevel: .low), 1, plan(3, 12, 400, aim: 3)),
        ])
        run.log(did(10, 10, 10, at: 600, rir: 3, pain: .mild))
        #expect(run.plan(of: 0) == [3, 11, 600, 2])
        run.log(did(11, 11, 11, at: 600, rir: 2, pain: .moderate))
        #expect(run.plan(of: 0) == [3, 11, 600, 2])
        #expect(run.code(of: 0) == .painHold)
        run.log(did(11, 11, 11, at: 600, rir: 2, pain: .moderate))
        #expect(run.plan(of: 0) == [3, 11, 550, 1])
        #expect(run.code(of: 0) == .painReduce)
        run.log(did(11, 11, 11, at: 550, rir: 3, pain: .severe))
        #expect(run.week == BuildWeek(kind: .deload, blockWeek: 5))
        #expect(run.plan(of: 0) == [2, 11, 450, 3])
        #expect(run.slotPlans[0].checkInPain == .severe)
        run.log(did(11, 11, at: 450, rir: 5, pain: .mild))
        #expect(run.week == BuildWeek(kind: .build, blockWeek: 1))
        // Pain DOWN takes the step, 2 sets, from the held slot only.
        #expect(run.plan(of: 0) == [1, 11, 450, 3])
        #expect(run.code(of: 0) == .volumeDown)
    }

    @Test("Example 4: a 3-week holiday after 2 build weeks replaces the deload")
    func holiday() {
        let deadlift = BuildExercise(minReps: 8, maxReps: 12, primary: .hamstrings, secondary: [.glutes], fatigueLevel: .high)
        var run = ExampleRun([
            (deadlift, 0, plan(3, 9, 1850, aim: 3)),
            (BuildExercise(minReps: 10, maxReps: 20, primary: .hamstrings, fatigueLevel: .low), 0, plan(4, 12, 900, aim: 3)),
            (BuildExercise(minReps: 10, maxReps: 20, primary: .hamstrings, fatigueLevel: .low), 1, plan(3, 12, 700, aim: 3)),
        ])
        run.log(did(9, 9, 9, at: 1850, rir: 3))
        #expect(run.plan(of: 0) == [3, 10, 1850, 2])
        run.log(did(10, 10, 10, at: 1850, rir: 2))
        #expect(run.plan(of: 0) == [3, 11, 1850, 2])
        run.takeBreak(band: 1)
        #expect(run.week == BuildWeek(kind: .build, blockWeek: 1, returnBand: 1))
        #expect(run.plan(of: 0) == [3, 9, 1850, 3])
        #expect(run.code(of: 0) == .blockRebase)
        run.log(did(9, 9, 9, at: 1850, rir: 2))
        #expect(run.plan(of: 0) == [3, 10, 1850, 2])
        run.log(did(10, 10, 10, at: 1850, rir: 2))
        #expect(run.plan(of: 0) == [3, 11, 1850, 2])
    }

    @Test("Example 5: a 20 lb lateral raise steps at 20 reps and re-baselines for 3 reps left")
    func lateralRaise() {
        let raise = BuildExercise(minReps: 10, maxReps: 20, primary: .shoulders, fatigueLevel: .low)
        var run = ExampleRun([
            (raise, 0, plan(3, 18, 200, aim: 2)),
            (BuildExercise(minReps: 8, maxReps: 15, primary: .shoulders, fatigueLevel: .moderate), 0, plan(4, 10, 500, aim: 3)),
            (BuildExercise(minReps: 10, maxReps: 20, primary: .shoulders, fatigueLevel: .low), 1, plan(4, 12, 300, aim: 3)),
        ])
        // Week 1 was on target, so week 2 starts from 3 × 19 × 20 aiming for 1 rep left.
        run.log(did(18, 18, 18, at: 200, rir: 2))
        #expect(run.plan(of: 0) == [3, 19, 200, 1])
        run.log(did(19, 19, 19, at: 200, rir: 2))
        #expect(run.plan(of: 0) == [3, 20, 200, 1])
        run.log(did(20, 20, 20, at: 200, rir: 1))
        #expect(run.plan(of: 0) == [3, 14, 250, 0])
        run.log(did(14, 14, 14, at: 250, rir: 0))
        #expect(run.plan(of: 0) == [2, 14, 200, 3])
        run.log(did(14, 14, at: 200, rir: 5))
        #expect(run.plan(of: 0) == [3, 11, 250, 3])
        run.log(did(11, 11, 11, at: 250, rir: 3))
        #expect(run.plan(of: 0) == [3, 12, 250, 2])
        run.log(did(12, 12, 12, at: 250, rir: 3))
        #expect(run.plan(of: 0) == [3, 13, 250, 1])
    }

    @Test("Example 6: back ramps up to its floor two sets a block, and pull-ups re-baseline from capacity")
    func backFloor() {
        let pullUp = BuildExercise(minReps: 6, maxReps: 12, primary: .back, secondary: [.biceps, .forearms, .abs], repsOnly: true, fatigueLevel: .moderate)
        let facePull = BuildExercise(minReps: 10, maxReps: 20, primary: .shoulders, secondary: [.back], fatigueLevel: .low)
        let dumbbellRow = BuildExercise(minReps: 8, maxReps: 12, primary: .back, secondary: [.biceps, .forearms, .abs], fatigueLevel: .moderate)
        var run = ExampleRun([
            (pullUp, 0, plan(3, 8, nil, aim: 2)),
            (facePull, 0, plan(2, 15, 300, aim: 2)),
            (dumbbellRow, 1, plan(3, 10, 500, aim: 3)),
            (BuildExercise(minReps: 8, maxReps: 15, primary: .shoulders, fatigueLevel: .moderate), 1, plan(4, 10, 500, aim: 3)),
            (BuildExercise(minReps: 10, maxReps: 20, primary: .shoulders, fatigueLevel: .low), 1, plan(4, 12, 200, aim: 3)),
        ])
        run.log([0: did(8, 8, 8, at: nil, rir: 2), 2: did(10, 10, 10, at: 500, rir: 3)])
        #expect(run.plan(of: 0) == [3, 9, nil, 1])
        #expect(run.plan(of: 2) == [4, 9, 500, 2])
        #expect(run.code(of: 2) == .volumeRamp)
        run.log([0: did(9, 9, 9, at: nil, rir: 1), 2: did(9, 9, 9, 9, at: 500, rir: 3)])
        #expect(run.plan(of: 0) == [4, 8, nil, 1])
        #expect(run.code(of: 0) == .volumeRamp)
        #expect(run.plan(of: 2) == [4, 10, 500, 2])
        run.log([0: did(8, 8, 8, 8, at: nil, rir: 1), 2: did(10, 10, 10, 10, at: 500, rir: 2)])
        #expect(run.plan(of: 0) == [4, 9, nil, 0])
        #expect(run.plan(of: 2) == [4, 11, 500, 0])
        run.log([0: did(9, 9, 9, 10, at: nil, rir: 0), 2: did(11, 11, 11, 13, at: 500, rir: 0)])
        #expect(run.plan(of: 0) == [2, 5, nil, 3])
        #expect(run.plan(of: 2) == [2, 11, 450, 3])
        run.log([0: did(5, 5, at: nil, rir: 5), 2: did(11, 11, at: 450, rir: 5)])
        #expect(run.plan(of: 0) == [4, 7, nil, 2])
        #expect(run.plan(of: 2) == [4, 10, 500, 3])
        run.log([0: did(7, 7, 7, 7, at: nil, rir: 3), 2: did(10, 10, 10, 10, at: 500, rir: 3)])
        #expect(run.plan(of: 0) == [4, 8, nil, 1])
        #expect(run.plan(of: 2) == [5, 9, 500, 2])
    }

    // MARK: Fillers

    private let fly = BuildExercise(minReps: 10, maxReps: 20, primary: .chest, fatigueLevel: .low)
    private let machinePress = BuildExercise(minReps: 8, maxReps: 12, primary: .chest, fatigueLevel: .moderate)
    private let row = BuildExercise(minReps: 8, maxReps: 12, primary: .back, fatigueLevel: .moderate)
    private let curl = BuildExercise(minReps: 10, maxReps: 20, primary: .biceps, fatigueLevel: .low)

    private func plan(_ sets: Int, _ reps: Int, _ load: Int?, aim: Int) -> BuildSlotPlan {
        BuildSlotPlan(sets: sets, reps: reps, load: load, rirTarget: aim, reason: .startHistory)
    }

    private func did(_ reps: Int..., at load: Int?, rir: Int, pain: LevelOfPain = .none) -> ExampleRun.Log {
        ExampleRun.Log(reps: reps, load: load, rir: rir, pain: pain)
    }
}

/// Feeds the engine one logged week at a time, like the planner does at each week's end.
@MainActor
private struct ExampleRun {
    struct Log {
        var reps: [Int]
        var load: Int?
        var rir: Int
        var pain: LevelOfPain
    }

    private(set) var weeks = [BuildWeek(kind: .build, blockWeek: 1)]
    private var slots: [BuildSlot]
    /// What each slot is planned to do this week.
    private(set) var slotPlans: [BuildSlotPlan]

    init(_ slots: [(BuildExercise, Int, BuildSlotPlan)]) {
        self.slots = slots.map { BuildSlot(workout: $0.1, exercise: $0.0, history: []) }
        slotPlans = slots.map(\.2)
    }

    var week: BuildWeek { weeks[weeks.count - 1] }

    /// [sets, reps, load, aim] of a slot's plan, for compact expectations.
    func plan(of slot: Int) -> [Int?] {
        let plan = slotPlans[slot]
        return [plan.sets, plan.reps, plan.load, plan.rirTarget]
    }

    func code(of slot: Int) -> BuildReason.Code {
        slotPlans[slot].reason.code
    }

    /// Logs the first slot as given and every other slot exactly as planned, on target, then plans next week.
    mutating func log(_ first: Log) {
        log([0: first])
    }

    mutating func log(_ logs: [Int: Log]) {
        for index in slots.indices {
            let plan = slotPlans[index]
            let log = logs[index] ?? Log(
                reps: Array(repeating: plan.reps ?? 10, count: plan.sets),
                load: plan.load,
                rir: plan.rirTarget,
                pain: .none
            )
            slots[index].history.append(exposure(log, planned: plan))
        }
        let next = BuildEngine.plan(BuildInput(weeks: weeks, slots: slots))
        weeks.append(next.week)
        slotPlans = next.slots
    }

    /// Replans the week that was planned but never started, as the first workout after a break does.
    mutating func takeBreak(band: Int) {
        let next = BuildEngine.planAfterBreak(BuildInput(weeks: weeks, slots: slots), band: band)
        weeks.append(BuildWeek(kind: next.week.kind, blockWeek: next.week.blockWeek, returnBand: band))
        slotPlans = next.slots
    }

    private func exposure(_ log: Log, planned plan: BuildSlotPlan) -> BuildExposure {
        let start = Date(timeIntervalSince1970: Double(weeks.count) * 7 * 86_400)
        return BuildExposure(
            weekIndex: weeks.count - 1,
            sets: log.reps.enumerated().map { index, reps in
                BuildSet(
                    plannedReps: plan.reps,
                    plannedLoad: plan.load,
                    reps: reps,
                    load: log.load,
                    completed: true,
                    completedAt: start.addingTimeInterval(Double(index) * 180)
                )
            },
            effort: .tapped(log.rir),
            pain: log.pain,
            rirTarget: plan.rirTarget,
            code: plan.reason.code,
            checkIn: plan.checkInPain == nil ? .none : .resolved,
            checkInSourcePain: plan.checkInPain
        )
    }
}
