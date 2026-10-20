//
//  PowerJackEngineTests.swift
//  PowerJackTests
//
//  The PowerJacking rules, checked against the rulebook's own worked numbers (revision 2).
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct PowerJackEngineTests {
    // MARK: R8.1 table and R2.5 steps

    @Test("The reps-to-%1RM table matches R8.1's worked numbers")
    func percentTable() throws {
        #expect(abs(try #require(PowerJackPercent.percent(reps: 8)) - 83.67) < 0.01)
        #expect(abs(try #require(PowerJackPercent.percent(reps: 7)) - 85.71) < 0.01)
        #expect(abs(try #require(PowerJackPercent.e1RM(load: 245, reps: 5, rir: 2)) - 285.8) < 0.1)
        #expect(abs(try #require(PowerJackPercent.load(e1RM: 285.8, reps: 3, rir: 2)) - 256.7) < 0.1)
        #expect(PowerJackPercent.percent(reps: 40) == nil)
    }

    @Test("Loads round on a lattice through the last load, and rises are capped")
    func steps() {
        #expect(PowerJackSteps().roundDown(263.6) == 260)
        #expect(PowerJackSteps(origin: 260).roundNearest(270.0) == 270)
        #expect(PowerJackSteps(origin: 270).roundNearest(256.5) == 255)
        // Ties go to the lower load.
        #expect(PowerJackSteps(origin: 100).roundNearest(102.5) == 100)
        // At most max(10% over the best recent load, one step).
        #expect(PowerJackSteps().capped(400, best: 300) == 330)
        #expect(PowerJackSteps().capped(40, best: 20) == 25)
    }

    // MARK: R1 reference templates

    @Test("Template A gives R1's main lifts, roles and tags")
    func templateA() {
        let roles = PowerJackRoles.assign([
            [bench, row, press, pulldown, pushdown, curl],
            [squat, deadlift, legPress, legCurl, calfRaise],
            [bench, chinUp, inclineDumbbell, cableRow, lateralRaise, hammerCurl],
            [squat, romanian, lunge, legExtension, seatedCalf],
        ])
        #expect(roles[0].map(\.role) == [.main, .secondary, .main, .secondary, .accessory, .accessory])
        #expect(roles[0][0].tag == .heavy)
        #expect(roles[0][2].tag == .topAndBack)
        #expect(roles[1].map(\.tag) == [.heavy, .topAndBack, nil, nil, nil])
        #expect(roles[2][0].tag == .volume)
        #expect(roles[2][1].role == .secondary)
        #expect(roles[3][0].tag == .volume)
        #expect(roles[3][1].role == .secondary)
    }

    @Test("Template B: a bodyweight dip never blocks the loaded overhead press")
    func templateB() {
        let roles = PowerJackRoles.assign([
            [squat, bench, row, dip, legCurl, curl],
            [squat, press, deadlift, pullUp, lateralRaise, pushdown],
            [squat, bench, legPress, cableRow, calfRaise, hammerCurl],
        ])
        #expect(roles.map { $0[0].tag } == [.heavy, .volume, .heavy])
        #expect(roles[0][3].role == .secondary)
        #expect(roles[1][1] == PowerJackSlotRole(role: .main, tag: .topAndBack))
        #expect(roles[1][2] == PowerJackSlotRole(role: .main, tag: .topAndBack))
        #expect(roles[2][1].tag == .volume)
    }

    @Test("Template C: two bench entries in a workout are a TOP entry and a BACK entry")
    func templateC() {
        let roles = PowerJackRoles.assign([
            [bench, bench, inclineDumbbell, fly, assistedDip],
            [deadlift, cableRow],
            [squat, romanian, legPress],
            [press, landmine, lateralRaise],
        ])
        #expect(roles[0][0] == PowerJackSlotRole(role: .main, tag: .heavy))
        #expect(roles[0][1] == PowerJackSlotRole(role: .main, tag: .volume))
        #expect(roles[0][4].role == .secondary)
        #expect(roles[1][0].tag == .topAndBack)
        #expect(roles[3][0].tag == .topAndBack)
        // Shoulders give v-push and Moderate fatigue gives single-joint: an accessory.
        #expect(roles[3][1].role == .accessory)
    }

    // MARK: R5 calendar and R4.3 columns

    @Test("Programs of 1-12 weeks lay out R5.2's blocks")
    func layouts() {
        let expected = [
            1: "B", 2: "BB", 3: "BBB", 4: "BBBD", 5: "BBBBD", 6: "BBBBBD", 7: "BBBBBBD",
            8: "BBBDBBBD", 9: "BBBBDBBBD", 10: "BBBBDBBBBD", 11: "BBBBBDBBBBD", 12: "BBBBBDBBBBBD",
        ]
        for (weeks, layout) in expected {
            let text = PowerJackCalendar.layout(weeks: weeks, carry: 0).map { $0 == .build ? "B" : "D" }.joined()
            #expect(text == layout, "\(weeks) weeks")
        }
        // After a 3-week program, a 5-week one opens with the deload.
        #expect(PowerJackCalendar.layout(weeks: 5, carry: 3) == [.deload, .build, .build, .build, .deload])
    }

    @Test("Target columns spread across 3 to 6 BUILD weeks")
    func columns() {
        let columns = { (k: Int) in (1...k).map { PowerJackCalendar.column(week: $0, of: k, lastColumn: 0) } }
        #expect(columns(3) == [1, 3, 4])
        #expect(columns(4) == [1, 2, 3, 4])
        #expect(columns(5) == [1, 2, 3, 3, 4])
        #expect(columns(6) == [1, 2, 2, 3, 3, 4])
        #expect(PowerJackRules.rirByColumn(.main, .bigger) == [3, 2, 2, 1])
    }

    // MARK: R4.5 classes

    @Test("Taps at the planned reps class as R4.5's table")
    func tapTable() {
        func outcome(_ tap: Int, target: Int, role: PowerJackRole = .main) -> PowerJackClass {
            PowerJackPart(sets: [.done(5, at: 200)], tap: tap).outcome(role: role, target: target, previous: nil, noSignal: false)
        }
        #expect([0, 1, 2, 3, 4, 5].map { outcome($0, target: 3) } == [.hard, .hard, .met, .met, .met, .easy])
        #expect([0, 1, 2, 3, 4, 5].map { outcome($0, target: 2) } == [.hard, .met, .met, .met, .easy, .easy])
        #expect([0, 1, 2, 3, 4, 5].map { outcome($0, target: 1) } == [.hard, .met, .met, .easy, .easy, .easy])
        #expect(outcome(0, target: 1, role: .accessory) == .met)
    }

    @Test("Misses, skipped sets and legacy words")
    func missClasses() {
        let short = PowerJackPart(sets: [.done(5, at: 200), .done(3, at: 200, planned: 5)], tap: 0)
        #expect(short.outcome(role: .main, target: 2, previous: nil, noSignal: false) == .missBig)
        let oneShort = PowerJackPart(sets: [.done(4, at: 200, planned: 5)], tap: 0)
        #expect(oneShort.outcome(role: .main, target: 2, previous: nil, noSignal: false) == .missSmall)
        #expect(oneShort.outcome(role: .main, target: 2, previous: .missSmall, noSignal: false) == .missBig)
        var skipped = PowerJackSetLog.done(5, at: 200)
        skipped.isComplete = false
        skipped.isSkipped = true
        let incomplete = PowerJackPart(sets: [.done(5, at: 200), skipped], tap: 2)
        #expect(incomplete.outcome(role: .main, target: 2, previous: nil, noSignal: false) == .incomplete)
        // A legacy Very Easy never reads as EASY.
        let legacy = PowerJackPart(sets: [.done(5, at: 200)], legacyEffort: .veryEasy)
        #expect(legacy.outcome(role: .secondary, target: 2, previous: nil, noSignal: false) == .met)
        #expect(legacy.source == .legacy)
    }

    // MARK: Block start (R2.2)

    @Test("Block-start main-lift loads come from the anchor at 3 reps in reserve")
    func blockStartLoads() throws {
        let plan = PowerJackEngine.firstWeek(lifts, context: context(history: anchorHistory))
        #expect(plan.header == PowerJackWeekPlanHeader(type: .build, blockNumber: 1, blockWeek: 1, column: 1, isBlockStart: true))
        let heavySquat = plan.workouts[1][0]
        #expect(heavySquat.sets == Array(repeating: PowerJackSetPlan(reps: 5, load: 260), count: 3))
        #expect(abs(try #require(heavySquat.loadTarget) - 263.6) < 0.1)
        #expect(heavySquat.target == 3)
        #expect(plan.workouts[3][0].sets.first == PowerJackSetPlan(reps: 8, load: 235))
        #expect(plan.workouts[0][0].sets.first == PowerJackSetPlan(reps: 5, load: 195))
        #expect(plan.workouts[2][0].sets.first == PowerJackSetPlan(reps: 8, load: 170))
        // A once-a-week lift: 1 TOP set at the heavy reps, then BACK sets at the volume reps.
        let deadlift = plan.workouts[1][1]
        #expect(deadlift.topSets == 1)
        #expect(deadlift.sets == [PowerJackSetPlan(reps: 5, load: 335), PowerJackSetPlan(reps: 8, load: 305), PowerJackSetPlan(reps: 8, load: 305)])
        // Warm-ups from the first working load: 50x5, 70x3, 85x1 before a heavy lift.
        #expect(heavySquat.warmups == [
            PowerJackSetPlan(reps: 5, load: 130), PowerJackSetPlan(reps: 3, load: 180), PowerJackSetPlan(reps: 1, load: 220),
        ])
    }

    @Test("A main lift with no anchor is calibrated: the lifter loads it at 3 reps in reserve")
    func calibration() throws {
        let plan = PowerJackEngine.firstWeek([[squat], [squat]], context: context())
        let entry = plan.workouts[0][0]
        #expect(entry.calibrating)
        #expect(entry.sets.allSatisfy { $0.load == nil && $0.reps == 5 })
        #expect(entry.target == 3)

        // R8.8's example: 225 x 5 tapped 3 anchors at 268.9; week 2 aims at 2 reps left.
        let week = weekLog([
            [logged(entry, load: 225, tap: 3)],
            [logged(plan.workouts[1][0], load: 185, tap: 3)],
        ])
        let next = try #require(PowerJackEngine.nextWeek(after: [week], context: context()))
        #expect(next.workouts[0][0].sets.first == PowerJackSetPlan(reps: 5, load: 230))
        #expect(!next.workouts[0][0].calibrating)
    }

    // MARK: R2.3 and R2.4 within a block

    @Test("Week 2 follows Example 1: ramp, HARD holds, EASY steps and double progression")
    func exampleOneWeekTwo() throws {
        let first = PowerJackEngine.firstWeek(liftsWithAccessories, context: context(history: anchorHistory))
        var week = weekLog(first.workouts.map { $0.map { logged($0, tap: $0.target ?? 3) } })
        // Heavy bench tapped 1 against a target of 3: HARD.
        week.workouts[0].entries[0].rir = 1
        // The row and the lateral raise start where Example 1 has them.
        week.workouts[0].entries[1] = logged(first.workouts[0][1], sets: Array(repeating: (8, 185), count: 2), tap: 3)
        week.workouts[2].entries[1] = logged(first.workouts[2][1], sets: Array(repeating: (15, 20), count: 2), tap: 2)

        let next = try #require(PowerJackEngine.nextWeek(after: [week], context: context(history: anchorHistory)))
        #expect(next.header.column == 2)
        #expect(next.workouts[0][0].sets.allSatisfy { $0.load == 195 })
        #expect(next.workouts[0][1].sets == Array(repeating: PowerJackSetPlan(reps: 9, load: 185), count: 2))
        #expect(next.workouts[1][0].sets.allSatisfy { $0.load == 270 })
        #expect(next.workouts[1][1].sets.map(\.load) == [345, 315, 315])
        #expect(next.workouts[2][0].sets.allSatisfy { $0.load == 180 })
        #expect(next.workouts[2][1].sets == Array(repeating: PowerJackSetPlan(reps: 16, load: 20), count: 2))
        #expect(next.workouts[3][0].sets.allSatisfy { $0.load == 245 })
        #expect(next.workouts[0][2].sets.map(\.load) == [130, 115, 115, 115, 115])
        // Main lifts aim at 2 reps left in column 2.
        #expect(next.workouts[1][0].target == 2)
    }

    @Test("A big miss cuts 2.5% a rep short, and an easy week adds 2.5% to the ramp")
    func missAndEasy() throws {
        let week = weekLog([[
            entry(squat, tag: .heavy, sets: [(5, 270), (3, 270), (5, 270)], planned: 5, target: 2, loadTarget: 270, tap: 2),
            entry(bench, tag: .volume, sets: [(8, 240), (8, 240)], planned: 8, target: 3, loadTarget: 242.8, tap: 5),
        ]], column: 1)
        let next = try #require(PowerJackEngine.nextWeek(after: [week], context: context()))
        // 2 reps short: 5% off 270 is 256.5, nearest step 255.
        #expect(next.workouts[0][0].sets.first?.load == 255)
        #expect(next.workouts[0][0].reasons.contains(.missCut))
        // 5+ against 3: EASY. 242.8 x ramp x 1.025, from Example 1's week 3.
        #expect(next.workouts[0][1].sets.first?.load == 255)
    }

    @Test("S and A loads jump at the top of the range, at a cost in reps, or the range widens")
    func doubleProgression() throws {
        let week = weekLog([[
            entry(row, sets: [(10, 185), (10, 185), (10, 185)], target: 1, tap: 1),
            entry(lateralRaise, sets: [(20, 15), (20, 15)], target: 1, tap: 1),
        ]], column: 3)
        let next = try #require(PowerJackEngine.nextWeek(after: [week], context: context()))
        #expect(next.workouts[0][0].sets == Array(repeating: PowerJackSetPlan(reps: 9, load: 190), count: 3))
        // +5 lb on 15 lb costs 13 reps, so the range widens instead.
        #expect(next.workouts[0][1].sets == Array(repeating: PowerJackSetPlan(reps: 21, load: 15), count: 2))
        #expect(next.workouts[0][1].reasons.contains(.widenRange))
    }

    // MARK: R6 deloads

    @Test("Without strain the deload is postponed once, then comes at half the sets and 90% load")
    func postponedDeload() throws {
        var weeks: [PowerJackWeekLog] = []
        for (index, column) in [1, 2, 3, 4].enumerated() {
            weeks.append(weekLog([[
                entry(deadlift, tag: .topAndBack, sets: [(5, 355), (8, 320), (8, 320)], planned: nil, target: 1, tap: 1, topRIR: 1),
                entry(lateralRaise, sets: [(19, 20), (20, 20)], target: 1, tap: 1),
            ]], column: column, blockWeek: index + 1))
        }
        let postponed = try #require(PowerJackEngine.nextWeek(after: weeks, context: context(weeks: 10)))
        #expect(postponed.header.type == .build)
        #expect(postponed.header.column == 4)

        weeks.append(weekLog(weeks[3].workouts.map(\.entries), column: 4, blockWeek: 5))
        let deload = try #require(PowerJackEngine.nextWeek(after: weeks, context: context(weeks: 10)))
        #expect(deload.header.type == .deload)
        #expect(deload.workouts[0][0].sets == [PowerJackSetPlan(reps: 5, load: 315), PowerJackSetPlan(reps: 8, load: 285)])
        #expect(deload.workouts[0][0].topSets == 1)
        // 90% of 20 lb rounds to 15, a 25% cut, so the load stays at 60% of the reps.
        #expect(deload.workouts[0][1].sets == [PowerJackSetPlan(reps: 11, load: 20)])
        #expect(deload.workouts[0][1].target == nil)
    }

    @Test("Two strained BUILD weeks after 3 bring the deload forward")
    func earlyDeload() throws {
        let calm = [
            entry(squat, tag: .heavy, sets: [(5, 300), (5, 300)], target: 2, tap: 2),
            entry(bench, tag: .heavy, sets: [(5, 200), (5, 200)], target: 2, tap: 2),
        ]
        let strained = [
            entry(squat, tag: .heavy, sets: [(5, 300), (5, 300)], target: 2, tap: 0),
            entry(bench, tag: .heavy, sets: [(5, 200), (5, 200)], target: 2, tap: 0),
        ]
        let weeks = [
            weekLog([calm], column: 1, blockWeek: 1),
            weekLog([strained], column: 2, blockWeek: 2),
            weekLog([strained], column: 3, blockWeek: 3),
        ]
        let next = try #require(PowerJackEngine.nextWeek(after: weeks, context: context(weeks: 10)))
        #expect(next.header.type == .deload)
    }

    // MARK: R10 pain

    @Test("Moderate pain holds at 2+ reps in reserve, a repeat cuts 10%, and Severe opens the check-in")
    func painLadder() throws {
        let now = Date.now
        func history(_ pains: [LevelOfPain]) -> [PowerJackExposure] {
            pains.enumerated().map { index, pain in
                var logged = entry(squat, tag: .heavy, sets: [(5, 300), (5, 300)], target: 2, tap: 2)
                logged.pain = pain
                return PowerJackExposure(date: now.addingTimeInterval(Double(index - pains.count) * 86_400 * 7), entry: logged, weekType: .build, tag: .heavy)
            }
        }
        func plan(_ pains: [LevelOfPain]) throws -> PowerJackEntryPlan {
            var logged = entry(squat, tag: .heavy, sets: [(5, 300), (5, 300)], target: 2, loadTarget: 300, tap: 2)
            logged.pain = pains.last
            let exposures = history(pains)
            let next = try #require(PowerJackEngine.nextWeek(
                after: [weekLog([[logged]], column: 1)],
                context: context(history: { _ in exposures })
            ))
            return next.workouts[0][0]
        }

        let hold = try plan([.none, .moderate])
        #expect(hold.sets.allSatisfy { $0.load == 300 })
        #expect(try #require(hold.target) >= 2)
        #expect(hold.reasons.contains(.painHold))

        let reduce = try plan([.none, .moderate, .moderate])
        #expect(reduce.sets.allSatisfy { $0.load == 270 })

        let severe = try plan([.none, .severe])
        #expect(severe.checkInPain == .severe)
        #expect(severe.sets.count == 1)

        let rising = try plan([.mild, .noticeable])
        #expect(rising.reasons.contains(.painHold))
        let steady = try plan([.noticeable, .noticeable])
        #expect(!steady.reasons.contains(.painHold))
    }

    // MARK: R9.2 rest

    @Test("The rest table rests longest after heavy main-lift sets")
    func restTable() {
        #expect(PowerJackRules.heavyRest == 240)
        #expect(PowerJackRules.volumeRest == 180)
        #expect(PowerJackRules.accessoryRest(.low) == 90)
    }
}

// MARK: - Fixtures

private extension PowerJackEngineTests {
    func exercise(
        _ id: String,
        _ pattern: PowerJackPattern?,
        multiJoint: Bool = true,
        repsOnly: Bool = false,
        assisted: Bool = false,
        fatigue: FatigueLevel = .high,
        primary: Muscle,
        secondaries: [Muscle] = []
    ) -> PowerJackExercise {
        PowerJackExercise(
            id: id, pattern: pattern, multiJoint: multiJoint, repsOnly: repsOnly, assisted: assisted,
            isBarbell: true, fatigue: fatigue, primary: primary, secondaries: secondaries
        )
    }

    var bench: PowerJackExercise { exercise("bench", .horizontalPush, primary: .chest, secondaries: [.triceps, .shoulders]) }
    var press: PowerJackExercise { exercise("press", .verticalPush, primary: .shoulders, secondaries: [.triceps]) }
    var squat: PowerJackExercise { exercise("squat", .squat, primary: .quads, secondaries: [.glutes]) }
    var deadlift: PowerJackExercise { exercise("deadlift", .hinge, primary: .hamstrings, secondaries: [.glutes, .back]) }
    var romanian: PowerJackExercise { exercise("romanian", .hinge, primary: .hamstrings) }
    var row: PowerJackExercise { exercise("row", .horizontalPull, fatigue: .high, primary: .back, secondaries: [.biceps]) }
    var cableRow: PowerJackExercise { exercise("cable-row", .horizontalPull, fatigue: .moderate, primary: .back) }
    var pulldown: PowerJackExercise { exercise("pulldown", .verticalPull, fatigue: .moderate, primary: .back) }
    var chinUp: PowerJackExercise { exercise("chin-up", .verticalPull, repsOnly: true, primary: .back) }
    var pullUp: PowerJackExercise { exercise("pull-up", .verticalPull, repsOnly: true, primary: .back) }
    var dip: PowerJackExercise { exercise("dip", .verticalPush, repsOnly: true, primary: .chest) }
    var assistedDip: PowerJackExercise { exercise("assisted-dip", .verticalPush, assisted: true, primary: .chest) }
    var inclineDumbbell: PowerJackExercise { exercise("incline-db", .horizontalPush, fatigue: .moderate, primary: .chest) }
    var legPress: PowerJackExercise { exercise("leg-press", .squat, primary: .quads) }
    var lunge: PowerJackExercise { exercise("lunge", .squat, fatigue: .moderate, primary: .quads) }
    var landmine: PowerJackExercise {
        let traits = PowerJackExercise.traits(catalogID: nil, primary: .shoulders, fatigue: .moderate)
        return exercise("landmine", traits.0, multiJoint: traits.1, fatigue: .moderate, primary: .shoulders)
    }
    func single(_ id: String, _ muscle: Muscle) -> PowerJackExercise {
        exercise(id, nil, multiJoint: false, fatigue: .low, primary: muscle)
    }
    var pushdown: PowerJackExercise { single("pushdown", .triceps) }
    var curl: PowerJackExercise { single("curl", .biceps) }
    var hammerCurl: PowerJackExercise { single("hammer", .biceps) }
    var fly: PowerJackExercise { single("fly", .chest) }
    var legCurl: PowerJackExercise { single("leg-curl", .hamstrings) }
    var legExtension: PowerJackExercise { single("leg-extension", .quads) }
    var calfRaise: PowerJackExercise { single("calf", .calves) }
    var seatedCalf: PowerJackExercise { single("seated-calf", .calves) }
    var lateralRaise: PowerJackExercise { single("lateral", .shoulders) }

    /// Template A's main lifts: bench H, overhead press T+B, squat H, deadlift T+B, bench V, squat V.
    var lifts: [[PowerJackExercise]] { [[bench, press], [squat, deadlift], [bench], [squat]] }
    var liftsWithAccessories: [[PowerJackExercise]] { [[bench, row, press], [squat, deadlift], [bench, lateralRaise], [squat]] }

    /// Example 1's H / V anchors, from plans logged 5 days ago. Their logs carry no tap, so they
    /// give only floors and the anchors stand.
    func anchorHistory(_ id: AnyHashable) -> [PowerJackExposure] {
        let anchors: [String: (heavy: Double, volume: Double, tag: PowerJackTag)] = [
            "squat": (315, 305, .heavy), "bench": (235, 225, .heavy),
            "press": (150, 145, .topAndBack), "deadlift": (405, 395, .topAndBack),
        ]
        guard let key = id.base as? String, let anchor = anchors[key] else { return [] }
        let date = Date.now.addingTimeInterval(-5 * 86_400)
        func part(_ e1RM: Double, reps: Int) -> (load: Double, sets: [PowerJackSetLog]) {
            let load = e1RM * PowerJackPercent.percent(reps: Double(reps + 1))! / 100
            return (load, [.done(reps, at: PowerJackSteps().roundDown(load), date: date)])
        }
        let heavy = part(anchor.heavy, reps: 5)
        let volume = part(anchor.volume, reps: 8)
        let base = PowerJackExercise(id: id, pattern: nil, multiJoint: true, repsOnly: false, fatigue: .high, primary: .quads)
        if anchor.tag == .topAndBack {
            let entry = PowerJackEntryLog(
                exercise: base, sets: heavy.sets + volume.sets, topSets: 1, target: 1,
                loadTarget: volume.load, topLoadTarget: heavy.load, pain: LevelOfPain.none
            )
            return [PowerJackExposure(date: date, entry: entry, weekType: .build, tag: .topAndBack)]
        }
        return [
            PowerJackExposure(date: date, entry: PowerJackEntryLog(exercise: base, sets: heavy.sets, target: 1, loadTarget: heavy.load, pain: LevelOfPain.none), weekType: .build, tag: .heavy),
            PowerJackExposure(date: date, entry: PowerJackEntryLog(exercise: base, sets: volume.sets, target: 1, loadTarget: volume.load, pain: LevelOfPain.none), weekType: .build, tag: .volume),
        ]
    }

    func context(weeks: Int = 10, history: @escaping (AnyHashable) -> [PowerJackExposure] = { _ in [] }) -> PowerJackContext {
        PowerJackContext(programWeeks: weeks, history: history)
    }

    func weekLog(_ entries: [[PowerJackEntryLog]], column: Int = 1, blockWeek: Int = 1) -> PowerJackWeekLog {
        PowerJackWeekLog(type: .build, blockNumber: 1, blockWeek: blockWeek, column: column, workouts: entries.map { PowerJackWorkoutLog(entries: $0) })
    }

    /// A plan logged as planned (or at `reps` x `load`), with a tap on every part.
    func logged(_ plan: PowerJackEntryPlan, reps: Int? = nil, load: Double? = nil, tap: Int) -> PowerJackEntryLog {
        PowerJackEntryLog(
            exercise: plan.exercise,
            sets: plan.sets.map { set in
                PowerJackSetLog(
                    plannedReps: set.reps, plannedLoad: set.load,
                    reps: reps ?? set.reps, load: load ?? set.load, isComplete: true, completedAt: .now
                )
            },
            topSets: plan.topSets,
            target: plan.target,
            loadTarget: plan.loadTarget,
            topLoadTarget: plan.topLoadTarget,
            calibrating: plan.calibrating,
            rir: tap,
            topRIR: plan.topSets > 0 ? tap : nil,
            pain: LevelOfPain.none
        )
    }

    func logged(_ plan: PowerJackEntryPlan, sets: [(Int, Double)], tap: Int) -> PowerJackEntryLog {
        var log = logged(plan, tap: tap)
        log.sets = sets.map { PowerJackSetLog.done($0.0, at: $0.1, date: .now) }
        return log
    }

    func entry(
        _ exercise: PowerJackExercise,
        tag: PowerJackTag? = nil,
        sets: [(Int, Double)],
        planned: Int? = nil,
        target: Int,
        loadTarget: Double? = nil,
        tap: Int,
        topRIR: Int? = nil
    ) -> PowerJackEntryLog {
        PowerJackEntryLog(
            exercise: exercise,
            sets: sets.map { PowerJackSetLog.done($0.0, at: $0.1, planned: planned ?? $0.0, date: .now) },
            topSets: tag == .topAndBack ? 1 : 0,
            target: target,
            loadTarget: loadTarget,
            rir: tap,
            topRIR: topRIR,
            pain: LevelOfPain.none
        )
    }
}
