//
//  StrengthEngineTests.swift
//  PowerJackTests
//
//  The Strengthen rules as pure functions, checked against the rulebook's test cases (T1-T25) where
//  they apply. Priority lifts run a top set and back-offs; secondary slots keep module 7's weekly
//  progression. kg cases use 2.5 kg steps on a 20 kg bar, lb cases 5 lb steps on a 45 lb bar.
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct StrengthEngineTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let kgBar = LoadGrid(unit: .kilograms, step: 2.5, isBarbell: true)
    private let lbBar = LoadGrid(unit: .pounds, step: 5, isBarbell: true)

    // MARK: 1 Units and load steps

    @Test("Loads round to the nearest grid load, ties down, never under the bar (1.1)")
    func rounding() {
        #expect(kgBar.nearest(146.25) == 145)
        #expect(kgBar.nearest(146.26) == 147.5)
        #expect(kgBar.down(147.4) == 145)
        #expect(kgBar.nearest(12) == 20)
        #expect(abs(lbBar.nearest(pounds(325.5)) - pounds(325)) < 0.001)
        #expect(kgBar.moved(140, bySteps: 1) == 142.5)

        let dumbbells = LoadGrid(unit: .kilograms, step: 2, isBarbell: false)
        #expect(dumbbells.nearest(0.5) == 2)
        #expect(dumbbells.isCoarse(at: 20))
        #expect(!kgBar.isCoarse(at: 60))
    }

    @Test("Loads never pass the 1,000 lb a set can log, and neither do intended loads (1.1)")
    func loadCap() {
        let sled = LoadGrid(unit: .pounds, step: 10, isBarbell: false)
        #expect(abs(sled.nearest(pounds(1_004)) - pounds(1_000)) < 0.001)
        #expect(abs(sled.moved(pounds(1_000), bySteps: 1) - pounds(1_000)) < 0.001)
        #expect(kgBar.maximumKilograms == 452.5)

        // A leg press at 1,000 lb rated 5+ stays there, and its intended load stops at the cap too.
        let last = session(.normal, reps: 6, rir: 2, intended: pounds(1_000), sets: Array(repeating: (pounds(1_000), 6), count: 3), rated: 5)
        let next = plan(context(zone: .moderate, grid: sled, history: [last]), record: confident(e1rm: pounds(1_400)), clock: StrengthClock(blockWeek: 3))
        #expect(abs((next.loadKg ?? 0) - pounds(1_000)) < 0.001)
        #expect((next.intendedKg ?? .infinity) <= LoadGrid.capKilograms)
    }

    @Test("Each equipment type has its own default step in each unit (1.5)")
    func defaultSteps() {
        #expect(StrengthLoadSteps.defaultStep(for: .barbell, in: .kilograms) == 2.5)
        #expect(StrengthLoadSteps.defaultStep(for: .barbell, in: .pounds) == 5)
        #expect(StrengthLoadSteps.defaultStep(for: .dumbbell, in: .kilograms) == 2)
        #expect(StrengthLoadSteps.defaultStep(for: .machine, in: .pounds) == 10)
        #expect(StrengthLoadSteps.defaultStep(for: .kettlebell, in: .kilograms) == 4)
        #expect(StrengthLoadSteps.defaultStep(for: .bodyweight, in: .kilograms) == nil)
        for equipment in Equipment.allCases where equipment != .bodyweight {
            for unit in WeightUnit.allCases {
                let step = StrengthLoadSteps.defaultStep(for: equipment, in: unit)
                #expect(step.map { StrengthLoadSteps.options(for: equipment, in: unit).contains($0) } == true)
            }
        }
    }

    @Test("Weights convert between kg and tenths of a pound without drifting")
    func unitConversion() {
        let tenths = WeightUnit.kilograms.tenthsPounds(from: 102.5)
        #expect(WeightUnit.kilograms.format(tenthsPounds: tenths) == "102.5")
        #expect(WeightUnit.pounds.format(tenthsPounds: 2250) == "225")
        #expect(WeightUnit.kilograms.maxEntry == 453)
        #expect(WeightUnit.tenthsPounds(fromKilograms: pounds(325)) == 3250)
    }

    // MARK: 4 Estimation

    @Test("Ratings of 4 and 5+ give lower bounds that only raise e1RM (T4)")
    func lowerBounds() {
        // A deadlift calibrating from 200.47 kg, rated 4 on 4 reps at 170 kg: n = 8.
        var record = StrengthLiftRecord(e1rmKg: 200.47)
        let rated = session(.calibration, reps: 4, rir: 3, intended: 171, sets: [(170, 4)], rated: 4)
        let value = StrengthEstimate.value(of: rated, curve: .main)
        #expect(abs((value.boundKg ?? 0) - 204.33) < 0.01)
        StrengthEstimate.update(&record, with: [rated], curve: .main, calibrating: true)
        // Bounds are smoothed like weekly values (adopted fix 1): 200.47 + 0.8 × (204.33 − 200.47).
        #expect(abs((record.e1rmKg ?? 0) - 203.56) < 0.01)
        #expect(record.ratedDates.count == 1)

        // 6 reps rated 5+ is n = 11, past the 10 the rules trust: no bound and no confidence.
        let tooLong = session(.normal, reps: 6, rir: 2, intended: 150, sets: [(150, 6)], rated: 5)
        #expect(StrengthEstimate.value(of: tooLong, curve: .main) == .init(isRated: false))
    }

    @Test("Weekly e1RM is the best session's value, smoothed at 0.5, and big jumps wait a week (4.1-4.3)")
    func smoothing() {
        var record = StrengthLiftRecord(e1rmKg: 160, calibrationWeeksLeft: 0)
        // 5 reps at RIR 2 on 140 kg: 140 ÷ pct(7) = 164.13. The lighter session the same week doesn't pull it down.
        let best = session(.normal, reps: 5, rir: 2, intended: 140, sets: [(140, 5)], rated: 2)
        let lighter = session(.normal, reps: 5, rir: 2, intended: 130, sets: [(130, 5)], rated: 2)
        StrengthEstimate.update(&record, with: [lighter, best], curve: .main, calibrating: false)
        #expect(abs((record.e1rmKg ?? 0) - 162.06) < 0.01)

        // A 20% jump is held back, then confirmed by a value within 5% of it.
        let before = record.e1rmKg
        StrengthEstimate.update(&record, with: [session(.normal, reps: 5, rir: 2, intended: 170, sets: [(170, 5)], rated: 2)], curve: .main, calibrating: false)
        #expect(record.e1rmKg == before)
        #expect(record.suspectKg != nil)
        StrengthEstimate.update(&record, with: [session(.normal, reps: 5, rir: 2, intended: 170, sets: [(170, 5)], rated: 2)], curve: .main, calibrating: false)
        #expect((record.e1rmKg ?? 0) > 180)
        #expect(record.suspectKg == nil)
    }

    @Test("Deload and painful sessions feed no e1RM (10.7, 15.8)")
    func excludedSessions() {
        let deload = session(.deload, reps: 4, rir: 3, intended: 130, sets: [(130, 4)], rated: 3)
        let painful = session(.normal, reps: 4, rir: 2, intended: 140, sets: [(140, 4)], rated: 2, pain: 3)
        #expect(StrengthEstimate.value(of: deload, curve: .main).e1rmKg == nil)
        #expect(StrengthEstimate.value(of: painful, curve: .main).e1rmKg == nil)
    }

    // MARK: 5 and 9 Targets

    @Test("The heavy day's top set goes 3, 3, 2, then 1 rep; the volume day's 5, 5, 5, then 4; secondaries stay 6 @ 2 (5.1)")
    func topSetSchemes() {
        let heavy = (1...4).map { StrengthRules.topSetScheme(zone: .heavy, blockWeek: $0, of: 4) }
        #expect(heavy.map(\.reps) == [3, 3, 2, 1])
        #expect(heavy.map(\.rir) == [2, 2, 2, 1])
        #expect(heavy.map(\.backShare) == [0.92, 0.92, 0.90, 0.87])
        #expect(heavy.allSatisfy { $0.backSets == 3 && $0.backReps == 3 })

        let moderate = (1...4).map { StrengthRules.topSetScheme(zone: .moderate, blockWeek: $0, of: 4) }
        #expect(moderate.map(\.reps) == [5, 5, 5, 4])
        #expect(moderate.map(\.rir) == [3, 3, 2, 2])
        #expect(moderate.map(\.backReps) == [5, 5, 5, 4])

        // A longer block holds the triple until its last two weeks.
        #expect((1...6).map { StrengthRules.topSetScheme(zone: .heavy, blockWeek: $0, of: 6).reps } == [3, 3, 3, 3, 2, 1])
        #expect(StrengthPrescriber.targets(context(role: .secondary, zone: nil), record: .init(), clock: StrengthClock()) == (6, 2))
    }

    @Test("A top set loads from e1RM × pct(reps + RIR) and its back-offs from their share of it")
    func topSetLoads() {
        // A 227 lb bench on the bench curve: a triple at 200, a double at 205, then a single at 220.
        let record = confident(e1rm: pounds(227))
        let slot = context(zone: .heavy, curve: .bench, grid: lbBar)
        func lb(_ plan: StrengthSlotPlan) -> [Double] { plan.sets.map { (($0.loadKg ?? 0) / WeightUnit.kilogramsPerPound).rounded() } }

        let triple = plan(slot, record: record, clock: StrengthClock(blockWeek: 1))
        #expect((triple.kind, triple.topSets, triple.reps, triple.rir) == (.normal, 1, 3, 2))
        #expect(triple.sets.map(\.reps) == [3, 3, 3, 3])
        #expect(lb(triple) == [200, 185, 185, 185])

        let double = plan(slot, record: record, clock: StrengthClock(blockWeek: 3))
        #expect(double.sets.map(\.reps) == [2, 3, 3, 3])
        #expect(lb(double) == [205, 185, 185, 185])

        let single = plan(slot, record: record, clock: StrengthClock(blockWeek: 4))
        #expect((single.reps, single.rir) == (1, 1))
        #expect(lb(single) == [220, 190, 190, 190])
        // About 96% of e1RM, the heavy single the block builds to.
        #expect(abs((single.loadKg ?? 0) / pounds(227) - 0.969) < 0.001)

        // The volume day: 5 @ 3 at 185 lb, back-offs 3 × 5 at 170.
        let volume = plan(context(zone: .moderate, curve: .bench, grid: lbBar), record: record, clock: StrengthClock(blockWeek: 1))
        #expect(volume.sets.map(\.reps) == [5, 5, 5, 5])
        #expect(lb(volume) == [185, 170, 170, 170])
    }

    @Test("Back-offs keep last week's count, and a stall step at a block's start adds one (11.5)")
    func backOffCount() {
        let last = topSession(top: (100, 3), back: [(92.5, 3), (92.5, 3), (92.5, 3), (92.5, 3)], rated: 2)
        let kept = plan(context(zone: .heavy, history: [last]), record: confident(e1rm: 120), clock: StrengthClock(blockWeek: 2))
        #expect(kept.sets.count == 5)

        var stalled = confident(e1rm: 120)
        stalled.stepThisWeek = .sets
        let added = plan(context(zone: .heavy, history: [topSession(top: (100, 3), back: [(92.5, 3), (92.5, 3), (92.5, 3)], rated: 2)]),
                         record: stalled, clock: StrengthClock(blockWeek: 1, startsBlock: true))
        #expect(added.sets.count == 5)
        // Never more than 4 back-offs.
        let capped = plan(context(zone: .heavy, history: [last]), record: stalled, clock: StrengthClock(blockWeek: 1, startsBlock: true))
        #expect(capped.sets.count == 1 + StrengthRules.maxBackSets)
    }

    @Test("Near-max squat and bench top sets carry a spotter reminder instead of staying light (5.2, T24)")
    func spotterRule() {
        let record = confident(e1rm: 150)
        let single = plan(context(zone: .heavy, spotter: true), record: record, clock: StrengthClock(blockWeek: 4))
        #expect((single.reps, single.rir) == (1, 1))
        #expect(single.rules.contains("5.2"))
        #expect(!plan(context(zone: .heavy, spotter: false), record: record, clock: StrengthClock(blockWeek: 4)).rules.contains("5.2"))
        // A triple @ 2 is 5 reps to failure, past the line.
        #expect(!plan(context(zone: .heavy, spotter: true), record: record, clock: StrengthClock(blockWeek: 1)).rules.contains("5.2"))
    }

    // MARK: 7 Weekly progression, on secondary slots

    @Test("Low confidence limits a rise to one step (T3)")
    func lowConfidenceStep() {
        var record = StrengthLiftRecord(calibrationWeeksLeft: 1)
        record.ratedDates = [now, now]
        let last = session(.calibration, reps: 6, rir: 2, intended: 133, sets: Array(repeating: (132.5, 6), count: 3), rated: 4)
        let next = plan(secondary(history: [last]), record: record, clock: StrengthClock(blockWeek: 1))
        #expect(next.kind == .calibration)
        #expect(next.loadKg == 135)
        #expect(abs((next.intendedKg ?? 0) - 135.5) < 0.001)
    }

    @Test("After rounding, a rise is capped at the bar × 1.075 rounded down, or one step (T2)")
    func postRoundingCap() {
        // A row on 180 kg, intended 180.33, Δ +3: 193.86 rounds to 195, the cap gives 192.5.
        let last = session(.normal, reps: 6, rir: 2, intended: 180.33, sets: Array(repeating: (180, 6), count: 3), rated: 5)
        let next = plan(secondary(history: [last]), record: confident(e1rm: 260), clock: StrengthClock(blockWeek: 3))
        #expect(next.loadKg == 192.5)
    }

    @Test("A binding ceiling rounds to nearest, and with d ≥ 0 never lowers last week's bar (T5)")
    func ceiling() {
        // Moving from 6 @ 3 to 6 @ 2, Δ −1 so d = 0: 142.28 × 1.0234 = 145.61, ceiling 170.22 × pct(7) = 145.20.
        let squat = session(.normal, reps: 6, rir: 3, intended: 142.28, sets: Array(repeating: (140, 6), count: 3), rated: 2)
        let squatNext = plan(secondary(history: [squat]), record: confident(e1rm: 170.22), clock: StrengthClock(blockWeek: 2))
        #expect(squatNext.loadKg == 145)
        #expect(squatNext.rules.contains("7.6"))

        // Bench held at 6 @ 2, rated 0 (Δ −2): the ceiling 105.93 binds but the bar stays at 107.5.
        let bench = session(.normal, reps: 6, rir: 2, intended: 106.32, sets: Array(repeating: (107.5, 6), count: 3), rated: 0)
        let benchNext = plan(secondary(curve: .bench, history: [bench]), record: confident(e1rm: 127.17), clock: StrengthClock(blockWeek: 2))
        #expect(benchNext.rules.contains("7.6"))
        #expect(benchNext.loadKg == 107.5)
    }

    @Test("A miss sets the base at the lifted load (T7)")
    func missThenWave() {
        // 3 × 6 @ 2: reps 6, 5, then 6 at 185 after the miss rule, rated 1.
        let last = StrengthSession(
            plan: StrengthSlotPlan(kind: .normal, reps: 6, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 6, loadKg: 192.5), intendedKg: 193.86),
            sets: [
                .init(loadKg: 192.5, reps: 6, plannedLoadKg: 192.5, completed: true),
                .init(loadKg: 192.5, reps: 5, plannedLoadKg: 192.5, completed: true),
                .init(loadKg: 185, reps: 6, plannedLoadKg: 192.5, completed: true),
            ],
            rir: 1,
            pain: 0,
            date: now
        )
        #expect(last.delta == -3)
        let next = plan(secondary(history: [last]), record: confident(e1rm: 260), clock: StrengthClock(blockWeek: 4))
        #expect((next.reps, next.rir) == (6, 2))
        #expect(next.loadKg == 180)
    }

    @Test("Each rep easier than planned adds 2.5%, on target nudges 1.25%, 1-2 short holds (7.3)")
    func weeklyChange() {
        let record = confident(e1rm: 300)
        func next(rated: Int) -> Double? {
            let last = session(.normal, reps: 6, rir: 2, intended: 140, sets: Array(repeating: (140, 6), count: 3), rated: rated)
            return plan(secondary(history: [last]), record: record, clock: StrengthClock(blockWeek: 3)).intendedKg
        }
        #expect(abs((next(rated: 3) ?? 0) - 143.5) < 0.001)
        #expect(abs((next(rated: 2) ?? 0) - 141.75) < 0.001)
        #expect(next(rated: 1) == 140)
        #expect(next(rated: 0) == 140)
    }

    @Test("Under half the planned sets done means no increase (7.4)")
    func tooFewSets() {
        let last = StrengthSession(
            plan: StrengthSlotPlan(kind: .normal, reps: 6, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 6, loadKg: 140), intendedKg: 140),
            sets: [.init(loadKg: 140, reps: 6, plannedLoadKg: 140, completed: true)],
            rir: 4,
            pain: 0,
            date: now
        )
        let next = plan(secondary(history: [last]), record: confident(e1rm: 300), clock: StrengthClock(blockWeek: 3))
        #expect(next.intendedKg == 140)
    }

    @Test("A swap to a priority lift plans from its e1RM, not an accessory deload week's high reps (14.6)")
    func accessoryDeloadIsNoBase() {
        let deload = StrengthSession(
            plan: StrengthSlotPlan(kind: .deload, reps: 16, rir: 2, sets: StrengthSlotPlan.uniform(1, reps: 16, loadKg: 45)),
            sets: [.init(loadKg: 45, reps: 16, plannedLoadKg: 45, completed: true)],
            rir: 3,
            pain: 0,
            date: now,
            plannedRole: .accessory
        )
        // 100 × pct(3 + 2) = 89.8, so a 90 kg triple.
        let next = plan(context(zone: .heavy, history: [deload]), record: confident(e1rm: 100), clock: StrengthClock(blockWeek: 2))
        #expect((next.reps, next.topSets, next.loadKg) == (3, 1, 90))
    }

    @Test("Coarse steps raise reps first, then step the load with reps refit (1.2, T22)")
    func repsMode() {
        // A chest press in 10 lb steps at 90 lb × 9 @ 2 with the offset at 3: E = 90 ÷ pct(11), fit(100) = 4.
        let machine = LoadGrid(unit: .pounds, step: 10, isBarbell: false)
        let last = StrengthSession(
            plan: StrengthSlotPlan(kind: .normal, reps: 6, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 9, loadKg: pounds(90)), repOffset: 3, intendedKg: pounds(90)),
            sets: Array(repeating: .init(loadKg: pounds(90), reps: 9, plannedLoadKg: pounds(90), completed: true), count: 3),
            rir: 2,
            pain: 0,
            date: now
        )
        #expect(last.delta == 0)
        let next = plan(secondary(grid: machine, history: [last]), record: confident(e1rm: pounds(200)), clock: StrengthClock(blockWeek: 3))
        #expect(abs((next.loadKg ?? 0) - pounds(100)) < 0.001)
        #expect(next.repOffset == -2)
        #expect(next.sets.first?.reps == 4)
    }

    // MARK: 10 Deloads

    @Test("A priority lift's deload is block week 1's top set at 90%, one back-off, 2 more RIR (10.6)")
    func deloadWeek() {
        // 180 × pct(3 + 2) × 0.9 = 145.5: a 145 kg triple @ 4, then 3 at 132.5.
        let last = topSession(top: (162.5, 1), back: [(140, 3), (140, 3), (140, 3)], rated: 1)
        let next = plan(context(zone: .heavy, history: [last]), record: confident(e1rm: 180), clock: StrengthClock(blockWeek: 4, upcoming: .deload))
        #expect(next.kind == .deload)
        #expect((next.topSets, next.reps, next.rir) == (1, 3, 4))
        #expect(next.sets == [StrengthPlannedSet(reps: 3, loadKg: 145), StrengthPlannedSet(reps: 3, loadKg: 132.5)])
    }

    @Test("A secondary slot's deload halves sets, takes 90% of the load and adds 2 RIR (T9)")
    func secondaryDeloadWeek() {
        let last = normal(reps: 6, rir: 2, intended: 151.23)
        let next = plan(secondary(history: [last]), record: confident(e1rm: 180), clock: StrengthClock(blockWeek: 4, upcoming: .deload))
        #expect(next.kind == .deload)
        #expect((next.sets.count, next.reps, next.rir, next.loadKg) == (1, 6, 4, 135))
    }

    @Test("Block week 1 restarts from e1RM, or from the scaled pre-deload load at low confidence (T10, T11)")
    func newBlockLoads() {
        let clock = StrengthClock(blockWeek: 1, blockType: .b, startsBlock: true)
        // 165.49 × pct(8) = 137.69.
        let squat = plan(secondary(history: [deloadSession, normal(reps: 6, rir: 2, intended: 151.23)]), record: confident(e1rm: 165.49), clock: clock)
        #expect((squat.reps, squat.rir, squat.loadKg) == (6, 2, 137.5))

        var unsure = StrengthLiftRecord(e1rmKg: 212.36, calibrationWeeksLeft: 0)
        unsure.ratedDates = [now, now]
        let deadlift = plan(secondary(history: [deloadSession, normal(reps: 6, rir: 2, intended: 180.38)]), record: unsure, clock: clock)
        #expect(deadlift.loadKg == 180)
        let sure = plan(secondary(history: [deloadSession, normal(reps: 6, rir: 2, intended: 180.38)]), record: confident(e1rm: 212.36), clock: clock)
        #expect(sure.loadKg == 177.5)

        // A priority lift starts the block from e1RM too: 165.49 × pct(5) = 148.61.
        let top = plan(context(zone: .heavy, history: [deloadSession, normal(reps: 4, rir: 1, intended: 151.23)]), record: confident(e1rm: 165.49), clock: clock)
        #expect((top.reps, top.rir, top.loadKg) == (3, 2, 147.5))
    }

    @Test("A flagged lift gets a micro-deload, then returns from its last normal week with d = 0 (T14)")
    func microDeload() {
        // A secondary bench in lb on the bench curve: 3 × 6 @ 2 at an intended 108.81 lb.
        var record = confident(e1rm: pounds(140))
        record.flagged = true
        let week2 = normal(reps: 6, rir: 2, intended: pounds(108.81), load: pounds(110))
        let micro = plan(secondary(curve: .bench, grid: lbBar, history: [week2]), record: record, clock: StrengthClock(blockWeek: 3))
        #expect(micro.kind == .microDeload)
        #expect(micro.sets.count == 2)
        #expect(abs((micro.loadKg ?? 0) - pounds(105)) < 0.001)

        record.flagged = false
        let microSession = StrengthSession(
            plan: micro,
            sets: Array(repeating: .init(loadKg: micro.loadKg, reps: 6, plannedLoadKg: micro.loadKg, completed: true), count: 2),
            rir: 2,
            pain: 0,
            date: now
        )
        let week4 = plan(secondary(curve: .bench, grid: lbBar, history: [microSession, week2]), record: record, clock: StrengthClock(blockWeek: 4))
        #expect(abs((week4.loadKg ?? 0) - pounds(110)) < 0.001)
    }

    @Test("A flagged priority lift's micro-deload takes 5% off its top set and a back-off away (10.3)")
    func topSetMicroDeload() {
        var record = confident(e1rm: 150)
        record.flagged = true
        let last = topSession(top: (135, 3), back: [(125, 3), (125, 3), (125, 3)], rated: 2)
        // 150 × pct(5) × 0.95 = 127.97.
        let micro = plan(context(zone: .heavy, history: [last]), record: record, clock: StrengthClock(blockWeek: 2))
        #expect((micro.kind, micro.topSets, micro.reps) == (.microDeload, 1, 3))
        #expect(micro.sets.count == 3)
        #expect(micro.loadKg == 127.5)
    }

    @Test("Two bad sessions flag a lift; two flagged priority lifts bring a reactive deload (10.2, 10.4)")
    func flagsAndReactiveDeload() {
        var state = StrengthState()
        state.clock.blockWeek = 2
        for key in ["squat", "bench"] {
            state[key] = confident(e1rm: 150)
        }
        func badWeek() -> StrengthClosedWeek {
            let entries = ["squat", "bench"].map { key in
                StrengthClosedWeek.Entry(
                    key: key, role: .primary, zone: .heavy, curve: .main,
                    session: session(.normal, reps: 4, rir: 2, intended: 120, sets: Array(repeating: (120, 4), count: 3), rated: 0)
                )
            }
            return StrengthClosedWeek(entries: entries, priorityKeys: ["squat", "bench"], kind: .build, closedAt: now)
        }
        StrengthWeekClose.close(&state, week: badWeek())
        #expect(state["squat"].flagged == false)
        #expect(state.clock.upcoming == .build)
        StrengthWeekClose.close(&state, week: badWeek())
        // Δ −2 twice flags both lifts, which deloads the whole next week instead of micro-deloads.
        #expect(state.clock.upcoming == .deload)
        #expect(state.clock.lastDeloadPlanned == false)
        #expect(state["squat"].flagged == false)

        StrengthWeekClose.close(&state, week: StrengthClosedWeek(entries: [], priorityKeys: ["squat", "bench"], kind: .deload, closedAt: now))
        #expect(state.clock.startsBlock)
        #expect(state.clock.blockType == .a)
    }

    @Test("A calibration week counts as block week 1; block week 4 brings the planned deload, then block B (9.5, 10.5)")
    func blockClock() {
        var state = StrengthState()
        func week(_ kind: StrengthSlotKind, rated: Int = 2) -> StrengthClosedWeek {
            StrengthClosedWeek(
                entries: [.init(key: "squat", role: .primary, zone: .heavy, curve: .main, session: session(kind, reps: 4, rir: 2, intended: 140, sets: Array(repeating: (140, 4), count: 3), rated: rated))],
                priorityKeys: ["squat"],
                kind: kind == .deload ? .deload : .build,
                closedAt: now
            )
        }
        StrengthWeekClose.close(&state, week: week(.calibration))
        #expect(state.clock.blockWeek == 2)
        #expect(state["squat"].isCalibrating == false)
        for expected in 3...4 {
            StrengthWeekClose.close(&state, week: week(.normal))
            #expect(state.clock.blockWeek == expected)
        }
        StrengthWeekClose.close(&state, week: week(.normal))
        #expect(state.clock.upcoming == .deload)
        StrengthWeekClose.close(&state, week: week(.deload))
        #expect(state.clock.upcoming == .build)
        #expect(state.clock.startsBlock)
        #expect((state.clock.blockWeek, state.clock.blockType) == (1, .b))
    }

    @Test("One lift back from a break doesn't skip the planned deload; every priority lift back does and restarts the count (10.5, 12.5)")
    func returnWeekSkipsDeload() {
        func blockEnd(returning: Set<String>) -> StrengthState {
            var state = StrengthState()
            state.clock.blockWeek = 4
            state.clock.weeksSinceDeload = 3
            let entries = ["squat", "bench"].map { key in
                StrengthClosedWeek.Entry(
                    key: key, role: .primary, zone: .heavy, curve: .main,
                    session: session(returning.contains(key) ? .returnWeek1 : .normal, reps: 4, rir: 2, intended: 120, sets: Array(repeating: (120, 4), count: 3), rated: 2)
                )
            }
            StrengthWeekClose.close(&state, week: StrengthClosedWeek(entries: entries, priorityKeys: ["squat", "bench"], kind: .build, closedAt: now))
            return state
        }
        #expect(blockEnd(returning: ["squat"]).clock.upcoming == .deload)
        let whole = blockEnd(returning: ["squat", "bench"])
        #expect(whole.clock.upcoming == .build && whole.clock.startsBlock)
        #expect(whole.clock.weeksSinceDeload == 0)
    }

    @Test("No real gain over 8 normal weeks adds a back-off for the next block (11.3, 11.5)")
    func plateau() {
        var state = StrengthState()
        state["squat"] = confident(e1rm: 150)
        state.clock.blockWeek = 1
        for _ in 0..<8 {
            let entry = StrengthClosedWeek.Entry(
                key: "squat", role: .primary, zone: .heavy, curve: .main,
                // 4 @ 2 at 120 kg: the same e1RM and plan every week.
                session: session(.normal, reps: 4, rir: 2, intended: 120, sets: Array(repeating: (120, 4), count: 3), rated: 2)
            )
            if state.clock.upcoming == .deload {
                StrengthWeekClose.close(&state, week: StrengthClosedWeek(entries: [], priorityKeys: ["squat"], kind: .deload, closedAt: now))
            }
            // Every week lands exactly on the estimate, so nothing reads as a drop.
            state["squat"].e1rmKg = 120 / 0.874
            StrengthWeekClose.close(&state, week: StrengthClosedWeek(entries: [entry], priorityKeys: ["squat"], kind: .build, closedAt: now))
        }
        #expect(state["squat"].pendingStep == .sets)
        StrengthWeekClose.close(&state, week: StrengthClosedWeek(entries: [], priorityKeys: ["squat"], kind: .deload, closedAt: now))
        #expect(state["squat"].stepThisWeek == .sets)
        #expect(state["squat"].plateauStage == 2)
        let last = topSession(top: (130, 3), back: [(120, 3), (120, 3), (120, 3)], rated: 2)
        #expect(plan(context(zone: .heavy, history: [last]), record: state["squat"], clock: state.clock).sets.count == 5)
    }

    // MARK: 12 Breaks

    @Test("Breaks restart lighter by their length (12.1, 12.2)")
    func breaks() {
        #expect(StrengthSessionRules.returnBand(daysOff: 14) == nil)
        #expect(StrengthSessionRules.returnBand(daysOff: 15) == 1)
        #expect(StrengthSessionRules.returnBand(daysOff: 35) == 2)
        #expect(StrengthSessionRules.returnBand(daysOff: 90) == 3)
        #expect(StrengthSessionRules.returnBand(daysOff: 91) == 4)

        // A 140 kg secondary squat after 5 weeks off restarts at 125 kg, a set fewer, 1 more rep in reserve.
        var plan = StrengthSlotPlan(kind: .normal, reps: 6, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 6, loadKg: 140), intendedKg: 140)
        StrengthSessionRules.applyReturn(band: 2, to: &plan, preBreakKg: 140, e1rmKg: nil, curve: .main, grid: kgBar)
        #expect(plan.kind == .returnWeek1)
        #expect((plan.sets.count, plan.rir, plan.loadKg) == (2, 3, 125))

        // Week 2 of that band is 5% under the pre-break load: 133, so 132.5.
        let weekOne = StrengthSession(
            plan: plan,
            sets: Array(repeating: .init(loadKg: 125, reps: 6, plannedLoadKg: 125, completed: true), count: 2),
            rir: 3,
            pain: 0,
            date: now
        )
        let weekTwo = self.plan(secondary(history: [weekOne, normal(reps: 6, rir: 2, intended: 140)]), record: confident(e1rm: 170), clock: StrengthClock(blockWeek: 2))
        #expect(weekTwo.kind == .returnWeek2)
        #expect(weekTwo.loadKg == 132.5)
    }

    @Test("Back from a break, a top set takes the cut, its back-offs follow a set fewer, and week 2 is 5% under plan (12.2)")
    func topSetBreak() {
        var plan = StrengthSlotPlan(kind: .normal, reps: 3, rir: 2, sets: StrengthSlotPlan.topAndBack(reps: 3, loadKg: 140, backSets: 3, backReps: 3, backLoadKg: 130), intendedKg: 140)
        plan.topSets = 1
        StrengthSessionRules.applyReturn(band: 2, to: &plan, preBreakKg: 140, e1rmKg: nil, curve: .main, grid: kgBar)
        #expect((plan.kind, plan.topSets, plan.rir) == (.returnWeek1, 1, 3))
        // 140 × 0.9 = 126, so 125; back-offs at 130 ÷ 140 of it: 116.07, so 115.
        #expect(plan.sets == [StrengthPlannedSet(reps: 3, loadKg: 125)] + StrengthSlotPlan.uniform(2, reps: 3, loadKg: 115))

        let weekOne = StrengthSession(
            plan: plan,
            sets: plan.sets.map { .init(loadKg: $0.loadKg, reps: 3, plannedLoadKg: $0.loadKg, completed: true) },
            rir: 3,
            pain: 0,
            date: now
        )
        // Block week 2's triple from e1RM: 170 × pct(5) × 0.95 = 145.03.
        let weekTwo = self.plan(context(zone: .heavy, history: [weekOne]), record: confident(e1rm: 170), clock: StrengthClock(blockWeek: 2))
        #expect((weekTwo.kind, weekTwo.returnBand, weekTwo.topSets) == (.returnWeek2, 2, 1))
        #expect(weekTwo.loadKg == 145)
    }

    // MARK: 6 In session

    @Test("A short set drops the sets still to do 4% per missing rep (T6)")
    func missRule() {
        #expect(StrengthSessionRules.loadAfterMiss(setLoadKg: 192.5, missingReps: 1, plannedKg: 192.5, grid: kgBar) == 185)
        // The cut stops 10% under plan, but always moves at least a step.
        #expect(StrengthSessionRules.loadAfterMiss(setLoadKg: 100, missingReps: 5, plannedKg: 100, grid: kgBar) == 90)
        #expect(StrengthSessionRules.loadAfterMiss(setLoadKg: 40, missingReps: 1, plannedKg: 40, grid: kgBar) == 37.5)
    }

    @Test("In kilograms a short set's cut still moves a whole step, though sets store tenths of a pound (6.2)")
    func missRuleStoredKilograms() {
        let machine = LoadGrid(unit: .kilograms, step: 5, isBarbell: false)
        let stored = WeightUnit.kilograms(fromTenthsPounds: WeightUnit.tenthsPounds(fromKilograms: 40))
        #expect(StrengthSessionRules.loadAfterMiss(setLoadKg: stored, missingReps: 1, plannedKg: stored, grid: machine) == 35)
    }

    @Test("A rated top set moves its back-offs: +2.5% a rep easier (up to 2), −4% a rep harder or missed (up to 3)")
    func backOffsFollowTheTopSet() {
        func back(reps: Int = 3, rated: Int) -> Double {
            StrengthSessionRules.backOffLoad(topKg: 100, share: 0.9, reps: reps, plannedReps: 3, rated: rated, aim: 2, grid: kgBar)
        }
        #expect(back(rated: 2) == 90)
        // 90 × 1.05 = 94.5, so 95, and a third easy rep adds nothing.
        #expect(back(rated: 4) == 95)
        #expect(back(rated: 5) == 95)
        // 90 × 0.96 = 86.4 and 90 × 0.92 = 82.8.
        #expect(back(rated: 1) == 87.5)
        #expect(back(rated: 0) == 82.5)
        // A rep short of the triple reads as 3 reps harder than aimed: 90 × 0.88 = 79.2.
        #expect(back(reps: 2, rated: 0) == 80)
    }

    @Test("A top-set session rates its top set, and each set counts as short only against its own reps")
    func topSetSessionReading() {
        let done = topSession(top: (140, 1), back: [(122.5, 3), (122.5, 3), (122.5, 2)], rated: 1, rir: 1)
        #expect(done.ratedSet?.loadKg == 140)
        #expect(done.delta == 0)
        #expect(done.missedSets.map(\.reps) == [2])

        // A top set left undone rates the last set done instead.
        var skippedTop = done
        skippedTop.sets[0].completed = false
        #expect(skippedTop.ratedSet?.loadKg == 122.5)
    }

    // MARK: 15 Pain

    @Test("Moderate pain cuts the next session a set and 10%, then each easy session ramps back (15.5, 15.7)")
    func moderatePain() {
        var pain = StrengthPainState()
        StrengthPain.record(&pain, session: session(.normal, reps: 4, rir: 2, intended: 140, sets: Array(repeating: (140, 4), count: 3), rated: 2, pain: 3))
        #expect(pain.pending == .cut)

        var next = StrengthSlotPlan(kind: .normal, reps: 4, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 4, loadKg: 142.5), intendedKg: 142)
        #expect(StrengthPain.apply(pain, to: &next, lastSession: nil, grid: kgBar) == false)
        #expect((next.kind, next.sets.count, next.loadKg) == (.painCut, 2, 127.5))

        // The cut session uses the action up; each easy session after it gives back a set, then 5% of the cap.
        StrengthPain.record(&pain, session: session(.painCut, reps: 4, rir: 2, intended: 142, sets: [(127.5, 4), (127.5, 4)], rated: 2, pain: 1))
        #expect(pain.pending == nil)
        #expect((pain.capShare, pain.setsDropped) == (0.9, 1))
        StrengthPain.record(&pain, session: session(.painCut, reps: 4, rir: 2, intended: 142, sets: [(127.5, 4), (127.5, 4)], rated: 2, pain: 0))
        #expect(pain.setsDropped == 0)
        StrengthPain.record(&pain, session: session(.painCut, reps: 4, rir: 2, intended: 142, sets: Array(repeating: (127.5, 4), count: 3), rated: 2, pain: 0))
        #expect(abs((pain.capShare ?? 0) - 0.945) < 0.0001)
    }

    @Test("Severe pain opens a check-in whose Lighter plan is 2 sets, 20% lighter rounded down, RIR 3+ (15.4, T21)")
    func severePain() {
        var pain = StrengthPainState()
        StrengthPain.record(&pain, session: session(.normal, reps: 4, rir: 2, intended: 140, sets: Array(repeating: (140, 4), count: 3), rated: 2, pain: 4))
        #expect(pain.pending == .lighter)
        var next = StrengthSlotPlan(kind: .normal, reps: 4, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 4, loadKg: 140), intendedKg: 140)
        #expect(StrengthPain.apply(pain, to: &next, lastSession: nil, grid: kgBar))
        #expect((next.kind, next.sets.count, next.rir, next.loadKg) == (.painLighter, 2, 3, 110))
    }

    @Test("Pain keeps a top-set plan's shape, and Lighter turns it into 2 easy back-off sets (15.4, 15.5)")
    func topSetPain() {
        var cut = StrengthPainState()
        cut.pending = .cut
        var next = StrengthSlotPlan(kind: .normal, reps: 2, rir: 2, sets: StrengthSlotPlan.topAndBack(reps: 2, loadKg: 140, backSets: 3, backReps: 3, backLoadKg: 125), intendedKg: 140)
        next.topSets = 1
        var cutPlan = next
        _ = StrengthPain.apply(cut, to: &cutPlan, lastSession: nil, grid: kgBar)
        // 10% off the top set, the back-offs at their share of it, one fewer.
        #expect((cutPlan.kind, cutPlan.topSets) == (.painCut, 1))
        #expect(cutPlan.sets == [StrengthPlannedSet(reps: 2, loadKg: 125)] + StrengthSlotPlan.uniform(2, reps: 3, loadKg: 112.5))

        var lighter = StrengthPainState()
        lighter.pending = .lighter
        var lighterPlan = next
        #expect(StrengthPain.apply(lighter, to: &lighterPlan, lastSession: nil, grid: kgBar))
        #expect((lighterPlan.kind, lighterPlan.topSets, lighterPlan.rir) == (.painLighter, 0, 3))
        #expect(lighterPlan.sets == StrengthSlotPlan.uniform(2, reps: 3, loadKg: 110))
    }

    @Test("Two Noticeable ratings in a row hold load and sets (15.6)")
    func painWatch() {
        var pain = StrengthPainState()
        let last = session(.normal, reps: 4, rir: 2, intended: 140, sets: Array(repeating: (140, 4), count: 3), rated: 2, pain: 2)
        StrengthPain.record(&pain, session: last)
        StrengthPain.record(&pain, session: last)
        #expect(pain.holds)
        var next = StrengthSlotPlan(kind: .normal, reps: 4, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 4, loadKg: 142.5), intendedKg: 142)
        _ = StrengthPain.apply(pain, to: &next, lastSession: last, grid: kgBar)
        #expect(next.loadKg == 140)
        #expect(next.intendedKg == 140)
    }

    // MARK: Gaps found by the simulation

    @Test("No warm-up lands on the working weight, though sets store tenths of a pound (5.7)")
    func warmupsAtTheBar() {
        let bar = WeightUnit.kilograms(fromTenthsPounds: WeightUnit.tenthsPounds(fromKilograms: 20))
        let atTheBar = StrengthSlotPlan(kind: .normal, reps: 4, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 4, loadKg: bar))
        #expect(StrengthPrescriber.warmups(for: atTheBar, slot: context(zone: .heavy), record: .init()) == [])
    }

    @Test("A deload week halves an accessory's sets even when last week's went unlogged (10.6)")
    func accessoryDeloadAfterSkip() {
        let curls = LoadGrid(unit: .kilograms, step: 2, isBarbell: false)
        let skipped = StrengthSession(
            plan: StrengthSlotPlan(kind: .accessory, reps: 10, rir: 2, sets: StrengthSlotPlan.uniform(2, reps: 10, loadKg: 12)),
            sets: Array(repeating: .init(loadKg: 12, reps: 10, plannedLoadKg: 12, completed: false), count: 2),
            rir: nil,
            pain: nil,
            date: nil
        )
        let next = plan(context(role: .accessory, zone: nil, grid: curls, repRange: 8...12, history: [skipped]), record: .init(), clock: StrengthClock(upcoming: .deload))
        #expect(next.kind == .deload)
        // One set at 90% of 12 kg, so 10 kg on 2 kg steps.
        #expect(next.sets == [StrengthPlannedSet(reps: 10, loadKg: 10)])
    }

    @Test("An accessory keeps its sets: one skipped this week comes back next week (5.1)")
    func accessoryKeepsSets() {
        let curls = LoadGrid(unit: .kilograms, step: 2, isBarbell: false)
        let last = StrengthSession(
            plan: StrengthSlotPlan(kind: .accessory, reps: 10, rir: 2, sets: StrengthSlotPlan.uniform(2, reps: 10, loadKg: 12)),
            sets: [true, false].map { .init(loadKg: 12, reps: 10, plannedLoadKg: 12, completed: $0) },
            rir: 2,
            pain: 0,
            date: now
        )
        let next = plan(context(role: .accessory, zone: nil, grid: curls, repRange: 8...12, history: [last]), record: .init(), clock: StrengthClock())
        #expect(next.sets == StrengthSlotPlan.uniform(2, reps: 11, loadKg: 12))
    }

    @Test("An accessory short of its rep range goes back to the bottom of it, as today's double progression does (5.1)")
    func accessoryBackIntoRange() {
        let curls = LoadGrid(unit: .kilograms, step: 2, isBarbell: false)
        let last = StrengthSession(
            plan: StrengthSlotPlan(kind: .accessory, reps: 8, rir: 2, sets: StrengthSlotPlan.uniform(2, reps: 8, loadKg: 14)),
            sets: [6, 5].map { .init(loadKg: 14, reps: $0, plannedLoadKg: 14, completed: true) },
            rir: 2,
            pain: 0,
            date: now
        )
        let next = plan(context(role: .accessory, zone: nil, grid: curls, repRange: 8...12, history: [last]), record: .init(), clock: StrengthClock())
        #expect(next.sets == StrengthSlotPlan.uniform(2, reps: 8, loadKg: 14))
        #expect(next.rules == ["5.1", "hold"])
    }

    @Test("A skipped accessory set planned under the rep range comes back inside it (5.1)")
    func skippedSetBackIntoRange() {
        let raises = LoadGrid(unit: .pounds, step: 5, isBarbell: false)
        // The second set was held at 1 rep, then skipped this week.
        let last = StrengthSession(
            plan: StrengthSlotPlan(kind: .accessory, reps: 10, rir: 2, sets: [StrengthPlannedSet(reps: 10, loadKg: pounds(30)), StrengthPlannedSet(reps: 1, loadKg: pounds(30))]),
            sets: [.init(loadKg: pounds(30), reps: 10, plannedLoadKg: pounds(30), completed: true), .init(loadKg: pounds(30), reps: nil, plannedLoadKg: pounds(30), completed: false)],
            rir: 2,
            pain: 0,
            date: now
        )
        let next = plan(context(role: .accessory, zone: nil, grid: raises, repRange: 5...20, history: [last]), record: .init(), clock: StrengthClock())
        #expect(next.sets.map(\.reps) == [10, 5])
    }

    @Test("A bodyweight exercise plans no weight, though it had one before its equipment changed (1.3)")
    func bodyweightDropsLoads() {
        let last = StrengthSession(
            plan: StrengthSlotPlan(kind: .accessory, reps: 10, rir: 2, sets: StrengthSlotPlan.uniform(2, reps: 10, loadKg: 20)),
            sets: Array(repeating: .init(loadKg: 20, reps: 10, plannedLoadKg: 20, completed: true), count: 2),
            rir: 2,
            pain: 0,
            date: now
        )
        let bodyweight = StrengthSlotContext(
            key: "own", role: .accessory, zone: nil, curve: .main, grid: nil, needsSpotter: false, repRange: 5...20, history: [last]
        )
        let next = StrengthPrescriber.plan(bodyweight, record: .init(), clock: StrengthClock(), at: now)
        #expect(next.sets == StrengthSlotPlan.uniform(2, reps: 11, loadKg: nil))
    }

    @Test("Week 2 back repeats week 1 on the grid of the unit now in use (1.4, 12.3)")
    func returnRepeatAfterUnitSwitch() {
        let fine = LoadGrid(unit: .kilograms, step: 0.5, isBarbell: true)
        var weekOne = StrengthSlotPlan(kind: .returnWeek1, reps: 4, rir: 2, sets: StrengthSlotPlan.uniform(2, reps: 4, loadKg: pounds(199)), intendedKg: pounds(199))
        weekOne.returnBand = 1
        let last = StrengthSession(
            plan: weekOne,
            sets: [4, 3].map { .init(loadKg: pounds(199), reps: $0, plannedLoadKg: pounds(199), completed: true) },
            rir: 0,
            pain: 0,
            date: now
        )
        // 199 lb is 90.26 kg: 90 on 0.5 kg plates.
        let next = plan(context(zone: .heavy, grid: fine, history: [last]), record: confident(e1rm: 120), clock: StrengthClock(blockWeek: 2))
        #expect(next.rules == ["12.3"])
        #expect(next.loadKg == 90)
    }

    @Test("Week 2 back repeats week 1 evenly, even with a set the lifter added to it (12.3)")
    func returnRepeatEven() {
        var weekOne = StrengthSlotPlan(
            kind: .returnWeek1, reps: 4, rir: 3,
            sets: StrengthSlotPlan.uniform(2, reps: 4, loadKg: 125) + [StrengthPlannedSet(reps: nil, loadKg: 125)],
            intendedKg: 126
        )
        weekOne.returnBand = 2
        let last = StrengthSession(
            plan: weekOne,
            sets: [4, 3, 3].map { .init(loadKg: 125, reps: $0, plannedLoadKg: 125, completed: true) },
            rir: 0,
            pain: 0,
            date: now
        )
        let next = plan(context(zone: .heavy, history: [last, normal(reps: 4, rir: 2, intended: 140)]), record: confident(e1rm: 170), clock: StrengthClock(blockWeek: 2))
        #expect(next.kind == .returnWeek2)
        #expect(next.rules == ["12.3"])
        #expect(next.sets == StrengthSlotPlan.uniform(3, reps: 4, loadKg: 125))
    }

    @Test("A deload restarts the run of RIR 0 weeks, so another reactive deload takes two more (10.1, 10.4)")
    func rir0RunRestarts() {
        var state = StrengthState()
        state["squat"] = confident(e1rm: 150)
        // A rep past the target but rated 0: no miss and Δ −1, so only the RIR 0 rule can deload.
        func week(_ kind: WeekKind) -> StrengthClosedWeek {
            let sets = Array(repeating: (120.0, 5), count: kind == .deload ? 1 : 3)
            let entry = StrengthClosedWeek.Entry(
                key: "squat", role: .primary, zone: .heavy, curve: .main,
                session: session(kind == .deload ? .deload : .normal, reps: 4, rir: 2, intended: 120, sets: sets, rated: 0)
            )
            return StrengthClosedWeek(entries: [entry], priorityKeys: ["squat"], kind: kind, closedAt: now)
        }
        StrengthWeekClose.close(&state, week: week(.build))
        StrengthWeekClose.close(&state, week: week(.build))
        #expect(state.clock.upcoming == .deload)
        StrengthWeekClose.close(&state, week: week(.deload))
        StrengthWeekClose.close(&state, week: week(.build))
        #expect(state.clock.rir0Weeks == 1)
        #expect(state.clock.upcoming == .build)
    }

    @Test("A swap that makes an accessory a priority lift starts it fresh, not from its 15-rep weeks (14.3)")
    func accessoryTurnedPriority() {
        let rows = StrengthSession(
            plan: StrengthSlotPlan(kind: .accessory, reps: 15, rir: 2, sets: StrengthSlotPlan.uniform(2, reps: 15, loadKg: 60)),
            sets: Array(repeating: .init(loadKg: 60, reps: 15, plannedLoadKg: 60, completed: true), count: 2),
            rir: 2,
            pain: 0,
            date: now
        )
        // No e1RM yet: a by-feel triple and its back-offs, even in a deload week.
        let next = plan(context(zone: .heavy, history: [rows]), record: .init(), clock: StrengthClock(blockWeek: 4, upcoming: .deload))
        #expect((next.kind, next.topSets, next.reps, next.loadKg) == (.calibration, 1, 3, nil))
        #expect(next.sets.allSatisfy { $0.reps == 3 && $0.loadKg == nil })
    }

    @Test("After a switch from lb to kg, holds and the ceiling keep last week's bar rounded down to the kg grid (1.4)")
    func unitSwitchRounding() {
        let fine = LoadGrid(unit: .kilograms, step: 0.5, isBarbell: true)
        let pounds275 = pounds(275)

        // Two Noticeable ratings in a row hold at last week's 275 lb, which is 124.74 kg: 124.5 on the kg grid.
        var pain = StrengthPainState()
        let last = session(.normal, reps: 4, rir: 2, intended: pounds275, sets: Array(repeating: (pounds275, 4), count: 3), rated: 2, pain: 2)
        StrengthPain.record(&pain, session: last)
        StrengthPain.record(&pain, session: last)
        var held = StrengthSlotPlan(kind: .normal, reps: 4, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 4, loadKg: 127), intendedKg: 127)
        _ = StrengthPain.apply(pain, to: &held, lastSession: last, grid: fine)
        #expect(held.loadKg == 124.5)

        // A ceiling of 143 × pct(7) = 122.0 binds with d ≥ 0, so the bar stays at last week's, on the new grid.
        let ceilinged = plan(secondary(grid: fine, history: [session(.normal, reps: 6, rir: 2, intended: pounds275, sets: Array(repeating: (pounds275, 6), count: 3), rated: 2)]),
                             record: confident(e1rm: 143), clock: StrengthClock(blockWeek: 3))
        #expect(ceilinged.rules.contains("7.6"))
        #expect(ceilinged.loadKg == 124.5)
    }

    @Test("A pain ramp at workout start rounds a plan made before a unit switch down to the new grid (1.4, 15.7)")
    func rampAfterUnitSwitch() {
        // Planned at 60 kg, then switched to lb with 2 lb steps: 132.3 lb isn't on the grid, 131 lb is.
        let lb2 = LoadGrid(unit: .pounds, step: 2, isBarbell: true)
        var plan = StrengthSlotPlan(kind: .normal, reps: 6, rir: 2, sets: StrengthSlotPlan.uniform(3, reps: 6, loadKg: 60), intendedKg: 62)
        _ = StrengthPain.apply(StrengthPainState(capShare: 0.98), to: &plan, lastSession: nil, grid: lb2)
        #expect(plan.kind == .painCut)
        #expect(abs((plan.loadKg ?? 0) - pounds(131)) < 0.001)
    }

    @Test("Deloads and micro-deloads cut from the bar when a cap kept it under the intended load (10.3, 10.6)")
    func lighterThanTheBar() {
        // The bar was held at 45 lb while the intended load ran ahead to 58 lb: 5% off the bar, not off 58.
        let last = session(.normal, reps: 6, rir: 2, intended: pounds(58), sets: Array(repeating: (pounds(45), 6), count: 3), rated: 2)
        var flagged = confident(e1rm: pounds(90))
        flagged.flagged = true
        let micro = plan(secondary(grid: lbBar, history: [last]), record: flagged, clock: StrengthClock(blockWeek: 2))
        #expect(micro.kind == .microDeload)
        #expect(abs((micro.loadKg ?? 0) - pounds(45)) < 0.001)

        let deload = plan(secondary(grid: lbBar, history: [last]), record: confident(e1rm: pounds(90)), clock: StrengthClock(blockWeek: 4, upcoming: .deload))
        #expect(deload.kind == .deload)
        #expect(abs((deload.loadKg ?? 0) - pounds(45)) < 0.001)
    }

    @Test("Weeks with no weight yet start from the lift's e1RM, and so does a block with no normal week to build on (2.6, 9.4)")
    func noLoadHistory() {
        let byFeel = StrengthSession(
            plan: StrengthSlotPlan(kind: .calibration, reps: 4, rir: 3, sets: StrengthSlotPlan.uniform(3, reps: 4, loadKg: nil)),
            sets: Array(repeating: .init(loadKg: nil, reps: nil, plannedLoadKg: nil, completed: false), count: 3),
            rir: nil,
            pain: nil,
            date: nil
        )
        // Skipped before it started: 180 × pct(3 + 2) = 161.6, a 162.5 kg triple.
        let skipped = plan(context(zone: .heavy, history: [byFeel]), record: confident(e1rm: 180), clock: StrengthClock(blockWeek: 1))
        #expect((skipped.kind, skipped.loadKg) == (.normal, 162.5))

        // Only a deload since: the new block starts from e1RM, not 10% light from the deload.
        let deloaded = session(.deload, reps: 4, rir: 3, intended: 130, sets: [(130, 4)], rated: 4)
        let block = plan(context(zone: .heavy, history: [deloaded, byFeel]), record: confident(e1rm: 180), clock: StrengthClock(blockWeek: 1, startsBlock: true))
        #expect((block.kind, block.loadKg) == (.normal, 162.5))

        // A weightless week skipped after the deload has nothing to repeat (7.4), so e1RM sets the load again.
        let skippedAgain = plan(context(zone: .heavy, history: [byFeel, deloaded]), record: confident(e1rm: 180), clock: StrengthClock(blockWeek: 2))
        #expect(skippedAgain.loadKg != nil)
    }

    // MARK: Accessories and codes

    @Test("Accessories keep a double progression in the strength steps and never add sets (5.1)")
    func accessories() {
        let curls = LoadGrid(unit: .kilograms, step: 2, isBarbell: false)
        func next(reps: Int, rated: Int) -> StrengthSlotPlan {
            let last = StrengthSession(
                plan: StrengthSlotPlan(kind: .accessory, reps: reps, rir: 2, sets: StrengthSlotPlan.uniform(2, reps: reps, loadKg: 12)),
                sets: Array(repeating: .init(loadKg: 12, reps: reps, plannedLoadKg: 12, completed: true), count: 2),
                rir: rated,
                pain: 0,
                date: now
            )
            return plan(context(role: .accessory, zone: nil, grid: curls, repRange: 5...12, history: [last]), record: .init(), clock: StrengthClock())
        }
        #expect(next(reps: 8, rated: 2).sets.map(\.reps) == [9, 9])
        #expect(next(reps: 11, rated: 2).sets.map(\.loadKg) == [14, 14])
        #expect(next(reps: 8, rated: 0).sets.map(\.reps) == [8, 8])
        #expect(next(reps: 8, rated: 2).sets.count == 2)
    }

    @Test("A slot's kind, break band and rule IDs survive the trip through its stored code")
    func slotCode() {
        var plan = StrengthSlotPlan(kind: .returnWeek1, reps: 4, rir: 3, sets: [], rules: ["12.1", "12.2"])
        plan.returnBand = 2
        let parsed = StrengthSlotPlan.parse(code: plan.code)
        #expect(parsed?.kind == .returnWeek1)
        #expect(parsed?.returnBand == 2)
        #expect(parsed?.rules == ["12.1", "12.2"])
        #expect(StrengthSlotPlan.parse(code: "nonsense") == nil)
    }

    // MARK: Helpers

    private func pounds(_ value: Double) -> Double { value * WeightUnit.kilogramsPerPound }

    private var deloadSession: StrengthSession {
        session(.deload, reps: 4, rir: 3, intended: 135, sets: [(135, 4)], rated: 4)
    }

    private func normal(reps: Int, rir: Int, intended: Double, load: Double? = nil) -> StrengthSession {
        let bar = load ?? kgBar.nearest(intended)
        return session(.normal, reps: reps, rir: rir, intended: intended, sets: Array(repeating: (bar, reps), count: 3), rated: rir)
    }

    private func session(
        _ kind: StrengthSlotKind,
        reps: Int,
        rir: Int,
        intended: Double?,
        sets: [(Double, Int)],
        rated: Int?,
        pain: Int? = 0
    ) -> StrengthSession {
        let planned = sets.first?.0
        return StrengthSession(
            plan: StrengthSlotPlan(kind: kind, reps: reps, rir: rir, sets: StrengthSlotPlan.uniform(sets.count, reps: reps, loadKg: planned), intendedKg: intended),
            sets: sets.map { .init(loadKg: $0.0, reps: $0.1, plannedLoadKg: planned, completed: true) },
            rir: rated,
            pain: pain,
            date: now
        )
    }

    /// A priority lift's finished session: a top set and back-offs, all done as planned.
    private func topSession(top: (Double, Int), back: [(Double, Int)], rated: Int, rir: Int = 2) -> StrengthSession {
        var plan = StrengthSlotPlan(
            kind: .normal, reps: top.1, rir: rir,
            sets: [StrengthPlannedSet(reps: top.1, loadKg: top.0)] + back.map { StrengthPlannedSet(reps: 3, loadKg: $0.0) },
            intendedKg: top.0
        )
        plan.topSets = 1
        return StrengthSession(
            plan: plan,
            sets: ([top] + back).map { .init(loadKg: $0.0, reps: $0.1, plannedLoadKg: $0.0, completed: true) },
            rir: rated,
            pain: 0,
            date: now
        )
    }

    private func confident(e1rm: Double) -> StrengthLiftRecord {
        var record = StrengthLiftRecord(e1rmKg: e1rm, calibrationWeeksLeft: 0)
        record.ratedDates = [now, now, now, now]
        return record
    }

    private func context(
        role: StrengthRole = .primary,
        zone: StrengthZone?,
        curve: StrengthCurve = .main,
        grid: LoadGrid? = nil,
        spotter: Bool = false,
        repRange: ClosedRange<Int> = 5...12,
        history: [StrengthSession] = []
    ) -> StrengthSlotContext {
        StrengthSlotContext(
            key: "lift",
            role: role,
            zone: zone,
            curve: curve,
            grid: grid ?? kgBar,
            needsSpotter: spotter,
            repRange: repRange,
            history: history
        )
    }

    /// A secondary slot, which keeps module 7's weekly progression at 6 @ 2.
    private func secondary(curve: StrengthCurve = .main, grid: LoadGrid? = nil, history: [StrengthSession] = []) -> StrengthSlotContext {
        context(role: .secondary, zone: nil, curve: curve, grid: grid, history: history)
    }

    private func plan(_ slot: StrengthSlotContext, record: StrengthLiftRecord, clock: StrengthClock) -> StrengthSlotPlan {
        StrengthPrescriber.plan(slot, record: record, clock: clock, at: now)
    }
}
