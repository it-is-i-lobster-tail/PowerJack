//
//  StrengthRulebookExampleTests.swift
//  PowerJackTests
//
//  The worked examples written into the strength rulebook's modules, run through the real rules: each
//  number a module's example gives is a number the engine must give, in kilograms and in pounds.
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct StrengthRulebookExampleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let kgBar = LoadGrid(unit: .kilograms, step: 2.5, isBarbell: true)
    private let lbBar = LoadGrid(unit: .pounds, step: 5, isBarbell: true)

    /// Module 7's table: a squat held at 5 @ RIR 2 with the intermediate nudge and module 9 left out, e1RM held at
    /// 172.2 kg (381.3 lb), so the 7.6 ceiling sits at 150.5 kg (333.3 lb).
    @Test("Module 7's worked example: five weeks of a squat, in kilograms and in pounds", arguments: [WeightUnit.kilograms, .pounds])
    func weeklyProgression(_ unit: WeightUnit) {
        let grid = unit == .kilograms ? kgBar : lbBar
        let record = confident(e1rm: unit == .kilograms ? 172.2 : pounds(381.3))
        // Block B's moderate slot in block week 2 is 5 @ 2 for an intermediate, as the example holds it.
        let clock = StrengthClock(blockWeek: 2, blockType: .b)
        // Weeks 1-5: what was lifted, and the reps and rating of each set.
        let weeks: [(kg: Double, lb: Double, reps: Int, rated: Int)] = [
            (140, 310, 5, 4), (147.5, 325, 5, 1), (147.5, 325, 5, 2), (150, 330, 5, 2), (150, 335, 4, 0),
        ]
        let expected: [(kg: Double, lb: Double)] = [(147.5, 325), (147.5, 325), (150, 330), (150, 335), (147.5, 325)]

        var intended = unit == .kilograms ? weeks[0].kg : pounds(weeks[0].lb)
        for (week, lifted) in weeks.enumerated() {
            let load = unit == .kilograms ? lifted.kg : pounds(lifted.lb)
            let last = StrengthSession(
                plan: StrengthSlotPlan(kind: .normal, reps: 5, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 5, loadKg: load), intendedKg: intended),
                sets: Array(repeating: .init(loadKg: load, reps: lifted.reps, plannedLoadKg: load, completed: true), count: 3),
                rir: lifted.rated,
                pain: 0,
                date: now
            )
            let next = StrengthPrescriber.plan(context(grid: grid, history: [last]), record: record, clock: clock, at: now)
            let bar = unit == .kilograms ? expected[week].kg : pounds(expected[week].lb)
            #expect((next.reps, next.rir) == (5, 2), "week \(week + 2)")
            #expect(abs((next.loadKg ?? 0) - bar) < 0.001, "week \(week + 2): \(next.loadKg ?? 0) kg, expected \(bar) kg")
            intended = next.intendedKg ?? intended
        }
    }

    @Test("9.2's example: an advanced block A restarts its heavy squat at 157.5 kg, or 350 lb")
    func newBlock() {
        let clock = StrengthClock(trainedWeeks: 104, blockWeek: 1, startsBlock: true)
        let deload = StrengthSession(
            plan: StrengthSlotPlan(kind: .deload, reps: 3, rir: 3, sets: StrengthSlotPlan.uniform(1, reps: 3, loadKg: 145), intendedKg: 144),
            sets: [.init(loadKg: 145, reps: 3, plannedLoadKg: 145, completed: true)],
            rir: 4,
            pain: 0,
            date: now
        )
        // The last pre-deload week ran 3 @ 1, heavy enough that the 5% cap over it doesn't bind.
        let kg = StrengthPrescriber.plan(
            context(zone: .heavy, history: [deload, normal(reps: 3, rir: 1, intended: 160, grid: kgBar)]),
            record: confident(e1rm: 180), clock: clock, at: now
        )
        #expect((kg.reps, kg.rir, kg.loadKg) == (3, 3, 157.5))

        let lb = StrengthPrescriber.plan(
            context(zone: .heavy, grid: lbBar, history: [deload, normal(reps: 3, rir: 1, intended: pounds(355), grid: lbBar)]),
            record: confident(e1rm: pounds(400)), clock: clock, at: now
        )
        #expect(abs((lb.loadKg ?? 0) - pounds(350)) < 0.001)
    }

    @Test("10.3's example: 3 × 5 at 140 kg (310 lb) micro-deloads to 2 × 5 at 132.5 kg (295 lb)")
    func microDeload() {
        for (grid, load, expected) in [(kgBar, 140.0, 132.5), (lbBar, pounds(310), pounds(295))] {
            var record = confident(e1rm: load * 1.3)
            record.flagged = true
            let next = StrengthPrescriber.plan(
                context(grid: grid, history: [normal(reps: 5, rir: 2, intended: load, grid: grid)]),
                record: record, clock: StrengthClock(blockWeek: 2, blockType: .b), at: now
            )
            #expect(next.kind == .microDeload)
            #expect((next.sets.count, next.reps, next.rir) == (2, 5, 2))
            #expect(abs((next.loadKg ?? 0) - expected) < 0.001)
        }
    }

    @Test("10.6's example: 3 × 5 at 140 kg (310 lb) deloads to 1 × 5 at 125 kg (280 lb)")
    func deload() {
        for (grid, load, expected) in [(kgBar, 140.0, 125.0), (lbBar, pounds(310), pounds(280))] {
            let next = StrengthPrescriber.plan(
                context(grid: grid, history: [normal(reps: 5, rir: 2, intended: load, grid: grid)]),
                record: confident(e1rm: load * 1.3), clock: StrengthClock(blockWeek: 4, blockType: .b, upcoming: .deload), at: now
            )
            #expect(next.kind == .deload)
            #expect((next.sets.count, next.reps) == (1, 5))
            #expect(next.rir >= StrengthRules.deloadRIRMin)
            #expect(abs((next.loadKg ?? 0) - expected) < 0.001)
        }
    }

    @Test("12.2's example: after 5 weeks off a 140 kg (310 lb) squat restarts at 125 kg (280 lb), then 132.5 kg (295 lb)")
    func returnFromBreak() {
        for (grid, load, weekOne, weekTwo) in [(kgBar, 140.0, 125.0, 132.5), (lbBar, pounds(310), pounds(280), pounds(295))] {
            var plan = StrengthSlotPlan(kind: .normal, reps: 5, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 5, loadKg: load), intendedKg: load)
            StrengthSessionRules.applyReturn(band: 2, to: &plan, preBreakKg: load, e1rmKg: nil, curve: .main, grid: grid)
            #expect((plan.kind, plan.sets.count, plan.rir) == (.returnWeek1, 2, 3))
            #expect(abs((plan.loadKg ?? 0) - weekOne) < 0.001)

            let back = StrengthSession(
                plan: plan,
                sets: Array(repeating: .init(loadKg: plan.loadKg, reps: 5, plannedLoadKg: plan.loadKg, completed: true), count: 2),
                rir: 3,
                pain: 0,
                date: now
            )
            let next = StrengthPrescriber.plan(
                context(grid: grid, history: [back, normal(reps: 5, rir: 2, intended: load, grid: grid)]),
                record: confident(e1rm: load * 1.3), clock: StrengthClock(blockWeek: 2, blockType: .b), at: now
            )
            #expect(next.kind == .returnWeek2)
            #expect(abs((next.loadKg ?? 0) - weekTwo) < 0.001)
        }
    }

    @Test("6.2's example: a squat set at 140 kg (310 lb) one rep short drops the next to 135 kg (300 lb)")
    func missRule() {
        #expect(StrengthSessionRules.loadAfterMiss(setLoadKg: 140, missingReps: 1, plannedKg: 140, grid: kgBar) == 135)
        let lb = StrengthSessionRules.loadAfterMiss(setLoadKg: pounds(310), missingReps: 1, plannedKg: pounds(310), grid: lbBar)
        #expect(abs(lb - pounds(300)) < 0.001)
    }

    @Test("1.2's example: an overhead press at 30 kg (65 lb) goes 5, 6, 7 and 8 reps, then 32.5 kg (70 lb) × 4")
    func repsMode() {
        for (grid, start, stepped) in [(kgBar, 30.0, 32.5), (lbBar, pounds(65), pounds(70))] {
            var reps = 5
            var load = start
            var offset = 0
            var targets: [Int] = []
            for _ in 0..<4 {
                // A good week: every set at the target, rated on target (Δ = 0).
                let last = StrengthSession(
                    plan: StrengthSlotPlan(kind: .normal, reps: 5, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: reps, loadKg: load), repOffset: offset, intendedKg: load),
                    sets: Array(repeating: .init(loadKg: load, reps: reps, plannedLoadKg: load, completed: true), count: 3),
                    rir: 2,
                    pain: 0,
                    date: now
                )
                let next = StrengthPrescriber.plan(context(grid: grid, history: [last]), record: confident(e1rm: start * 1.3), clock: StrengthClock(blockWeek: 2, blockType: .b), at: now)
                reps = next.targetReps
                load = next.loadKg ?? load
                offset = next.repOffset
                targets.append(reps)
            }
            #expect(targets == [6, 7, 8, 4])
            #expect(abs(load - stepped) < 0.001)
        }
    }

    // MARK: Helpers

    private func pounds(_ value: Double) -> Double { value * WeightUnit.kilogramsPerPound }

    private func normal(reps: Int, rir: Int, intended: Double, grid: LoadGrid) -> StrengthSession {
        let bar = grid.nearest(intended)
        return StrengthSession(
            plan: StrengthSlotPlan(kind: .normal, reps: reps, rir: rir, sets: StrengthSlotPlan.uniform(3, reps: reps, loadKg: bar), intendedKg: intended),
            sets: Array(repeating: .init(loadKg: bar, reps: reps, plannedLoadKg: bar, completed: true), count: 3),
            rir: rir,
            pain: 0,
            date: now
        )
    }

    private func confident(e1rm: Double) -> StrengthLiftRecord {
        var record = StrengthLiftRecord(e1rmKg: e1rm, calibrationWeeksLeft: 0)
        record.ratedDates = [now, now, now, now]
        return record
    }

    /// A priority lift's slot on the main curve: the moderate one unless `zone` says otherwise.
    private func context(zone: StrengthZone = .moderate, grid: LoadGrid? = nil, history: [StrengthSession]) -> StrengthSlotContext {
        StrengthSlotContext(
            key: "lift",
            role: .primary,
            zone: zone,
            curve: .main,
            grid: grid ?? kgBar,
            needsSpotter: false,
            repRange: 5...12,
            history: history
        )
    }
}
