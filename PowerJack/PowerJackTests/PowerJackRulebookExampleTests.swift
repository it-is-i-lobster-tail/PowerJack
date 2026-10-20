//
//  PowerJackRulebookExampleTests.swift
//  PowerJackTests
//
//  The PowerJacking rulebook's own worked numbers (revision 2), ported from its examples-sim.py checks,
//  and its worked examples 1 and 2 run week by week through the engine. Checks for rules the app doesn't
//  build yet (R2.7's pre-fill, R5.5-R5.6's max test, R6.6's rungs, R7.3, R8.5, R8.9, per-exercise steps
//  and kg mode) are left out.
//

import Foundation
import Testing
@testable import PowerJack

extension PowerJackEngineTests {
    // MARK: R8.1 and R2.1

    @Test("R8.1's table and its worked e1RM and load")
    func rulebookTable() throws {
        #expect(try #require(PowerJackPercent.percent(reps: 7)).roundedHalfUp == 86)
        let reps: [Double] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 20, 30]
        #expect(try reps.map { try tenth(#require(PowerJackPercent.percent(reps: $0))) }
            == [100, 97.8, 95.7, 92.8, 89.8, 87.8, 85.7, 83.7, 81.6, 79.6, 77.6, 75.6, 69.6, 59.2, 45.9])
        let e1RM = try #require(PowerJackPercent.e1RM(load: 245, reps: 5, rir: 2))
        #expect(tenth(e1RM) == 285.8 && PowerJackSteps().roundDown(e1RM) == 285)
        let load = try #require(PowerJackPercent.load(e1RM: e1RM, reps: 3, rir: 2))
        #expect(tenth(load) == 256.7 && PowerJackSteps().roundDown(load) == 255)
    }

    @Test("R2.1's %e1RM bands by slider, and one RIR step on Balanced's ramps (R2.3)")
    func rulebookRepBands() throws {
        let goals: [PowerJackGoal] = [.stronger, .balanced, .bigger]
        let band = { (reps: Int) in "\(self.percent(reps + 3))-\(self.percent(reps + 1))" }
        #expect(goals.map { band(PowerJackRules.heavyReps($0)) } == ["86-90", "84-88", "82-86"])
        #expect(goals.map { band(PowerJackRules.volumeReps($0)) } == ["82-86", "78-82", "74-78"])
        #expect(goals.map { percent(PowerJackRules.volumeReps($0) + 2) } == [84, 80, 76])
        let steps = try [5, 8].flatMap { reps in
            try [2, 1].map { rir in
                try tenth((#require(PowerJackPercent.percent(reps: Double(reps + rir))) / #require(PowerJackPercent.percent(reps: Double(reps + rir + 1))) - 1) * 100)
            }
        }
        #expect(steps.min() == 2.4 && steps.max() == 2.6)
    }

    // MARK: R1 reference templates

    @Test("R1's reference templates A, B and C read as the rulebook lists them")
    func rulebookTemplates() {
        let a = describe(referenceA)
        #expect(a.mains == ["Bench press", "Overhead press", "Back squat", "Deadlift"])
        #expect(a.rows == [
            "Bench press M H; Barbell row S; Overhead press M T+B; Lat pulldown S; Triceps pushdown A; Barbell curl A",
            "Back squat M H; Deadlift M T+B; Leg press S; Lying leg curl A; Standing calf raise A",
            "Bench press M V; Chin-up S; Incline dumbbell press S; Seated cable row S; Lateral raise A; Hammer curl A",
            "Back squat M V; Romanian deadlift S; Walking lunge S; Leg extension A; Seated calf raise A",
        ])
        let b = describe(referenceB)
        #expect(b.mains == ["Back squat", "Bench press", "Overhead press", "Deadlift"])
        #expect(b.rows == [
            "Back squat M H; Bench press M H; Barbell row S; Dip S; Lying leg curl A; Barbell curl A",
            "Back squat M V; Overhead press M T+B; Deadlift M T+B; Pull-up S; Lateral raise A; Triceps pushdown A",
            "Back squat M H; Bench press M V; Leg press S; Chest-supported row S; Standing calf raise A; Hammer curl A",
        ])
        let c = describe(referenceC)
        #expect(c.mains == ["Bench press", "Deadlift", "Back squat", "Overhead press"])
        #expect(c.rows == [
            "Bench press M TOP entry (H); Bench press M BACK entry (V); Incline dumbbell press S; Cable fly A; Assisted dip S",
            "Deadlift M T+B; Weighted pull-up S; Barbell row S; Seated cable row S; Barbell shrug A",
            "Back squat M T+B; Romanian deadlift S; Leg press S; Leg extension A; Lying leg curl A; Standing calf raise A",
            "Overhead press M T+B; Landmine press A; Lateral raise A; Rear delt fly A",
            "Close-grip bench press S; Barbell curl A; Skull crusher A; Hammer curl A; Triceps pushdown A",
        ])
    }

    @Test("R1's template edits: a Romanian deadlift first, workouts reordered, a front squat, no overhead press")
    func rulebookTemplateEdits() {
        var rdlFirst = referenceA
        rdlFirst[1][1] = "Romanian deadlift"
        rdlFirst[3][1] = "Deadlift"
        let rdl = describe(rdlFirst)
        #expect(rdl.mains[3] == "Romanian deadlift")
        #expect(rdl.rows[1].contains("Romanian deadlift M T+B") && rdl.rows[3].contains("Deadlift S"))

        let reordered = describe([referenceA[2], referenceA[0], referenceA[1], referenceA[3]])
        #expect(reordered.rows[0].hasPrefix("Bench press M H") && reordered.rows[1].hasPrefix("Bench press M V"))

        let front = describe(referenceA.map { $0.map { $0 == "Back squat" ? "Front squat" : $0 } })
        #expect(front.rows[1].hasPrefix("Front squat M H") && front.rows[3].hasPrefix("Front squat M V"))

        var noPress = referenceB
        noPress[1].removeAll { $0 == "Overhead press" }
        let b = describe(noPress)
        #expect(b.mains == ["Back squat", "Bench press", "Deadlift"])
        #expect(b.rows[1] == "Back squat M V; Deadlift M T+B; Pull-up S; Lateral raise A; Triceps pushdown A")

        var incline = referenceC
        incline[0] = ["Bench press", "Incline dumbbell press", "Bench press", "Cable fly", "Assisted dip"]
        #expect(describe(incline).rows[0].hasPrefix("Bench press M TOP entry (H); Incline dumbbell press S; Bench press M BACK entry (V)"))
        #expect(describe(referenceC, landmine: library("Landmine press", multiJoint: true)).rows[3].contains("Landmine press S"))
    }

    // MARK: R2 loads

    @Test("R2.2's block-start loads and R4.6's TOP and BACK sets from a 315 / 300 lb squat")
    func rulebookBlockStart() throws {
        let heavy = try #require(PowerJackPercent.load(e1RM: 315, reps: 5, rir: 3))
        #expect(tenth(heavy) == 263.6 && PowerJackSteps().roundDown(heavy) == 260)
        let volume = try #require(PowerJackPercent.load(e1RM: 315, reps: 8, rir: 3))
        #expect(tenth(volume) == 244.4 && PowerJackSteps().roundDown(volume) == 240)

        // R4.6: a Balanced squat trained once a week takes 5 lift sets, 1 x 5 TOP then 4 x 8 BACK.
        let plan = PowerJackEngine.firstWeek([[squat]], context: context(history: anchors(["squat": (315, 300, .topAndBack)])))
        let entry = plan.workouts[0][0]
        #expect(entry.topSets == 1)
        #expect(entry.sets == [PowerJackSetPlan(reps: 5, load: 260)] + Array(repeating: PowerJackSetPlan(reps: 8, load: 230), count: 4))
        #expect(try tenth(#require(entry.topLoadTarget)) == 263.6 && tenth(#require(entry.loadTarget)) == 232.8)
    }

    @Test("R2.4 and R2.5: where a light raise or curl's load jump comes, and where it never fits")
    func rulebookJumpPoints() {
        // Lateral raise at 15 lb, 12-20: +5 lb is 33% and costs 13 reps, so the jump waits for 25 reps, planned at 12.
        #expect(jumpPoint(lateralRaise, load: 15) == .jump(at: 25, planned: 12))
        // Curl at 25 lb, 10-15: +5 lb is 20% and costs 8, so the jump comes at 18, planned at 10.
        #expect(jumpPoint(single("curl", .biceps, fatigue: .moderate), load: 25) == .jump(at: 18, planned: 10))
        // Lateral raise at 10 lb: +5 lb is 50% and costs 20 reps, so it holds at 30.
        #expect(jumpPoint(lateralRaise, load: 10) == .holds(at: 30))
        // R2.5's table: band mode when one step is over 5% of the load.
        let bandMode = [(5.0, 315.0), (5, 95), (5, 100)].map { step, load in step / load * 100 > PowerJackRules.bandModePct }
        #expect(bandMode == [false, true, false])
    }

    // MARK: R3 volume

    @Test("R3.1's ledger: a 4-rep TOP set credits half, secondaries half a set")
    func rulebookLedger() {
        // Bench TOP 1 x 4 + BACK 3 x 6, incline dumbbell press 3 x 10, overhead press 3 x 6, pushdown 2 x 12 (Stronger).
        let structure = [[press], [bench, bench, inclineDumbbellPress, press, pushdown]]
        let builder = PowerJackWeekBuilder(context: PowerJackContext(programWeeks: 10, goal: .stronger), weeks: [], structure: structure, warmupsDisabled: [])
        let counts: [SlotRef: Int] = [
            SlotRef(workout: 1, entry: 0): 1, SlotRef(workout: 1, entry: 1): 3, SlotRef(workout: 1, entry: 2): 3,
            SlotRef(workout: 1, entry: 3): 3, SlotRef(workout: 1, entry: 4): 2,
        ]
        let credits = builder.credits(counts, workout: 1)
        #expect(credits[.chest] == 6.5 && credits[.triceps] == 6.75 && credits[.shoulders] == 6.25)
    }

    @Test("R3.3's lift sets: 3 + 3 Balanced, 5 + 4 Stronger, a once-a-week deadlift 1 + 2 or 1 + 4, 9 becomes 5")
    func rulebookLiftSets() {
        func sets(_ structure: [[PowerJackExercise]], _ goal: PowerJackGoal) -> [Int] {
            let builder = PowerJackWeekBuilder(context: PowerJackContext(programWeeks: 10, goal: goal), weeks: [], structure: structure, warmupsDisabled: [])
            let counts = builder.liftSetCounts()
            return builder.slots.compactMap { counts[$0] }
        }
        #expect(sets([[squat], [squat]], .balanced) == [3, 3])
        #expect(sets([[squat], [squat]], .stronger) == [5, 4])
        #expect(sets([[deadlift]], .balanced) == [3] && sets([[deadlift]], .stronger) == [5])
        #expect(sets([[squat]], .stronger) == [5])
        // R3.5: a muscle may add 20% of its block start, at least 1: 2 for starts of 8-12, 3 for 13-17.
        let limit = { (start: Int) in max(1, (PowerJackRules.blockAddPct / 100 * Double(start)).roundedHalfUp) }
        #expect(Set((8...12).map(limit)) == [2] && Set((13...17).map(limit)) == [3])
    }

    @Test("R3.7: a Balanced chest starts at 10, gains a set, starts the next block at 11, then 10 after a cut")
    func rulebookVolumeAcrossBlocks() {
        let structure = [[bench, inclineDumbbellPress]]
        func week(_ block: Int, _ blockWeek: Int, incline sets: Int) -> PowerJackWeekLog {
            var week = weekLog([[
                entry(bench, sets: [(5, 200), (5, 200), (5, 200)], target: 2, tap: 2),
                entry(inclineDumbbellPress, sets: Array(repeating: (8, 60), count: sets), target: 2, tap: 2),
            ]], blockWeek: blockWeek)
            week.blockNumber = block
            return week
        }
        func deload(_ block: Int) -> PowerJackWeekLog {
            PowerJackWeekLog(type: .deload, blockNumber: block, blockWeek: 0, column: 0, workouts: [PowerJackWorkoutLog(entries: [])])
        }
        let added = [week(1, 1, incline: 3), week(1, 2, incline: 3), week(1, 3, incline: 4), week(1, 4, incline: 4), deload(1)]
        #expect(builder(added, structure: structure).blockStart(.chest) == 11)
        let cut = added + [week(2, 1, incline: 4), week(2, 2, incline: 4), week(2, 3, incline: 3), week(2, 4, incline: 3), deload(2)]
        #expect(builder(cut, structure: structure).blockStart(.chest) == 10)
    }

    // MARK: R4 effort

    @Test("R4.3: main lifts aim at 3 reps left in week 1 and 1 in the last BUILD week, on every slider")
    func rulebookTargets() {
        let targets = { (k: Int) in
            (1...k).map { PowerJackRules.rirByColumn(.main, .balanced)[PowerJackCalendar.column(week: $0, of: k, lastColumn: 0) - 1] }
        }
        #expect([3, 4, 5, 6].map(targets) == [[3, 2, 1], [3, 2, 2, 1], [3, 2, 2, 2, 1], [3, 2, 2, 2, 2, 1]])
        #expect(PowerJackGoal.allCases.map { PowerJackRules.rirByColumn(.main, $0)[3] } == [1, 1, 1])
    }

    // MARK: R5 layouts

    @Test("R5.4's re-layouts in a 10-week program: an early deload, a partial week 3 and a postponed deload")
    func rulebookRelayouts() {
        let text = { (weeks: [PowerJackWeekType]) in weeks.map { $0 == .build ? "B" : "D" }.joined() }
        #expect(text([.deload] + PowerJackCalendar.layout(weeks: 6, carry: 0)) == "DBBBBBD")
        #expect(text(PowerJackCalendar.layout(weeks: 7, carry: 2)) == "BBDBBBD")
        #expect(text([.build, .deload] + PowerJackCalendar.layout(weeks: 4, carry: 0)) == "BDBBBD")
    }

    // MARK: R6 deloads and breaks

    @Test("R6.3's deloads: half the sets at 90%, or 60% of the reps where 90% would cut over 20%")
    func rulebookDeloads() {
        #expect((1...5).map { max(1, (Double($0) * PowerJackRules.deloadSetFactor).roundedHalfUp) } == [1, 1, 2, 2, 3])
        // Squat 1 x 5 at 285 + 3 x 6 at 250 becomes 1 x 5 at 255 + 1 x 6 at 225.
        var squatWeek = entry(squat, tag: .topAndBack, sets: [(5, 285), (6, 250), (6, 250), (6, 250)], target: 1, tap: 1, topRIR: 1)
        squatWeek.role = PowerJackSlotRole(role: .main, tag: .topAndBack)
        let squatDeload = builder([weekLog([[squatWeek]])], structure: [[squat]]).build(header: deloadHeader)
        #expect(squatDeload.workouts[0][0].sets == [PowerJackSetPlan(reps: 5, load: 255), PowerJackSetPlan(reps: 6, load: 225)])
        // Lateral raise 4 x 12 at 20 lb with a 5-lb step: 15 lb would cut 25%, so 2 x 7 at 20.
        let raise = weekLog([[entry(lateralRaise, sets: Array(repeating: (12, 20), count: 4), target: 1, tap: 1)]])
        #expect(builder([raise], structure: [[lateralRaise]]).build(header: deloadHeader).workouts[0][0].sets
            == Array(repeating: PowerJackSetPlan(reps: 7, load: 20), count: 2))
    }

    @Test("R6.7 and R8.8: a lift's own gap of 14, 28 and 84 days cuts its anchor 0, 10 and 20%")
    func rulebookGaps() throws {
        let cuts = [8, 13, 14, 27, 28, 83, 84].map { days in
            builder([], structure: [[squat]], history: lastSquat(daysAgo: Double(days))).gapCut(squat)
        }
        #expect(cuts == [nil, nil, 0, 0, 10, 10, 20])
        // A band-2 gap from a 300 lb anchor loads the next block from 270: 5 reps at 3 left is 225.
        let start = PowerJackEngine.firstWeek([[squat], [squat]], context: context(history: lastSquat(daysAgo: 31)))
        #expect(start.workouts[0][0].calibrating && start.workouts[0][0].sets.first?.load == 225)
    }

    // MARK: R8 values and anchors

    @Test("R8.2: a TOP set and BACK sets each give their own value and floor")
    func rulebookValues() throws {
        let top = try #require(PowerJackPart(sets: [.done(5, at: 275)], tap: 2).value)
        let back = try #require(PowerJackPart(sets: Array(repeating: .done(8, at: 240), count: 4), tap: 3).value)
        // The chapter shows each to 0.1 (306.25 as 306.2).
        #expect(near(top.value, 320.8) && near(top.floor, 306.2) && near(back.value, 309.3) && near(back.floor, 286.8))
    }

    @Test("R8.4: the anchor is the median of the newest 3 estimates, rising at most 7.5% a block")
    func rulebookAnchor() throws {
        // Estimates of 301.2, 296.0 and 312.5 lb, then a 5+ tap with a floor near 298, after an anchor of 285.
        let estimates = [(301.2, 14.0), (296.0, 7.0), (312.5, 3.0)].map { exposure(e1RM: $0.0, daysAgo: $0.1, tap: 2) }
        let floor = exposure(e1RM: 298, daysAgo: 1, tap: 5)
        let previous = exposure(e1RM: 285, daysAgo: 20, tap: nil, loadTarget: true)
        let history = { (id: AnyHashable) in id == self.squat.id ? [previous] + estimates + [floor] : [] }
        let builder = builder([], structure: [[squat], [squat]], history: history)
        #expect(try tenth(#require(builder.currentE1RM(squat, .heavy, previous: 285))) == 301.2)
        #expect(try tenth(#require(builder.blockStartAnchor(squat, .heavy).anchor)) == 301.2)
        // Had the median been 320, the anchor would stop at 285 x 1.075 = 306.4.
        let higher = { (id: AnyHashable) in id == self.squat.id ? [previous] + [320.0, 320, 320].map { self.exposure(e1RM: $0, daysAgo: 2, tap: 2) } : [] }
        #expect(try tenth(#require(self.builder([], structure: [[squat], [squat]], history: higher).blockStartAnchor(squat, .heavy).anchor)) == 306.4)
    }

    @Test("R8.8: a new squat at 225 x 5 with 3 left anchors at 268.9, and a tap of 4 after a gap stays under the old anchor")
    func rulebookCalibration() throws {
        let part = PowerJackPart(sets: [.done(5, at: 225)], tap: 3)
        let anchor = try #require(part.value?.value)
        #expect(tenth(anchor) == 268.9)
        let next = try #require(PowerJackPercent.load(e1RM: anchor, reps: 5, rir: 2))
        #expect(tenth(next) == 230.5 && PowerJackSteps().roundDown(next) == 230)
        let afterGap = try #require(PowerJackPart(sets: [.done(5, at: 225)], tap: 4).value?.value)
        #expect(tenth(afterGap) == 275.6 && afterGap < 300)
    }

    // MARK: R10.8 warm-ups

    @Test("R10.8: an H slot at 315 lb warms up 155 x 5, 220 x 3, 265 x 1")
    func rulebookWarmups() {
        let plan = PowerJackEngine.firstWeek([[squat], [squat]], context: context(history: anchors(["squat": (378.1, 360, .heavy)])))
        #expect(plan.workouts[0][0].sets.first?.load == 315)
        #expect(plan.workouts[0][0].warmups == [
            PowerJackSetPlan(reps: 5, load: 155), PowerJackSetPlan(reps: 3, load: 220), PowerJackSetPlan(reps: 1, load: 265),
        ])
    }

    // MARK: Worked examples

    @Test("Worked example 1: Balanced, Template A, block 1 and its deload, week by week")
    func workedExampleOne() throws {
        let structure = referenceA.map { $0.map { library($0) } }
        let context = PowerJackContext(programWeeks: 10, history: anchors([
            "Back squat": (315, 305, .heavy), "Bench press": (235, 225, .heavy),
            "Overhead press": (150, 145, .topAndBack), "Deadlift": (405, 395, .topAndBack),
        ]))
        // Main-lift slots: bench H (workout 1), squat H and deadlift (2), bench V (3), squat V (4).
        let lifts = [SlotRef(workout: 0, entry: 0), SlotRef(workout: 1, entry: 0), SlotRef(workout: 1, entry: 1), SlotRef(workout: 2, entry: 0), SlotRef(workout: 3, entry: 0)]
        let expected: [[String]] = [
            ["3x5@195", "3x5@260", "1x5@335 2x8@305", "3x8@170", "3x8@235"],
            ["3x5@195", "3x5@270", "1x5@345 2x8@315", "3x8@180", "3x8@245"],
            ["2x5@195", "3x5@270", "1x5@345 2x8@315", "3x8@180", "3x8@245"],
            ["2x5@200", "3x5@275", "1x5@355 2x8@320", "3x8@185", "3x8@255"],
            ["2x5@200", "3x5@275", "1x5@355 2x8@320", "3x8@185", "3x8@255"],
            ["1x5@180", "2x5@245", "1x5@315 1x8@285", "2x8@165", "2x8@225"],
        ]
        var plan = PowerJackEngine.firstWeek(structure, context: context)
        var weeks: [PowerJackWeekLog] = []
        for (index, want) in expected.enumerated() {
            #expect(lifts.map { sets(plan[$0]) } == want, "week \(index + 1)")
            guard index < expected.count - 1 else { break }
            weeks.append(asPlanned(plan, load: 50) { slot, entry in
                switch (index, slot) {
                // Week 1: heavy bench rated 1 against 3, HARD. Week 2: a set 2 reps short, MISS_BIG.
                case (0, lifts[0]): self.retap(entry, 1)
                case (1, lifts[0]): self.redo(entry, [(5, 195), (3, 195), (5, 175)])
                // Week 3: volume squat rated 4 against 2, EASY.
                case (2, lifts[4]): self.retap(entry, 4)
                default: entry
                }
            })
            plan = try #require(PowerJackEngine.nextWeek(after: weeks, context: context))
        }
        // Week 5 is the postponed BUILD week, at the final column (R6.2).
        #expect(weeks[4].type == .build && weeks[4].column == 4 && plan.header.type == .deload)
    }

    @Test("Worked example 2: Stronger, Template B, block 1 with a skipped Monday, then its deload")
    func workedExampleTwo() throws {
        let structure = referenceB.map { $0.map { library($0) } }
        let context = PowerJackContext(programWeeks: 10, goal: .stronger, history: anchors([
            "Back squat": (365, 355, .heavy), "Bench press": (275, 265, .heavy),
            "Overhead press": (165, 160, .topAndBack), "Deadlift": (455, 445, .topAndBack),
        ]))
        // Squat H (Monday), bench H (Monday), deadlift (Wednesday), squat H (Friday), bench V (Friday).
        let lifts = [SlotRef(workout: 0, entry: 0), SlotRef(workout: 0, entry: 1), SlotRef(workout: 1, entry: 2), SlotRef(workout: 2, entry: 0), SlotRef(workout: 2, entry: 1)]
        let expected: [[String]] = [
            ["3x4@310", "5x4@235", "1x4@390 4x6@360", "3x4@310", "4x6@215"],
            ["3x4@320", "5x4@240", "1x4@400 4x6@370", "3x4@320", "4x6@220"],
            ["3x4@320", "5x4@240", "1x4@400 4x6@370", "3x4@320", "4x6@220"],
            ["3x4@320", "5x4@240", "1x4@410 4x6@380", "3x4@330", "4x6@225"],
            ["2x4@285", "3x4@215", "1x4@365 2x6@340", "2x4@295", "2x6@200"],
        ]
        var plan = PowerJackEngine.firstWeek(structure, context: context)
        var weeks: [PowerJackWeekLog] = []
        for (index, want) in expected.enumerated() {
            #expect(lifts.map { sets(plan[$0]) } == want, "week \(index + 1)")
            guard index < expected.count - 1 else { break }
            var week = asPlanned(plan, load: 50) { slot, entry in
                // Week 4: Friday's heavy squat rated 0 against 1, HARD, so the deload isn't postponed.
                index == 3 && slot == lifts[3] ? self.retap(entry, 0) : entry
            }
            if index == 2 {
                // Week 3: Monday is skipped. Its slots repeat their plan in week 4, at week 4's target.
                week.workouts[0] = PowerJackWorkoutLog(entries: plan.workouts[0].map { skipped($0) }, skipped: true)
            }
            weeks.append(week)
            plan = try #require(PowerJackEngine.nextWeek(after: weeks, context: context))
            if index == 2 {
                #expect(plan[lifts[0]].target == 1 && plan[lifts[0]].reasons.contains(.repeatSkipped))
            }
        }
        #expect(plan.header.type == .deload)
    }
}

// MARK: - Fixtures

extension PowerJackEngineTests {
    /// R1's reference templates, by exercise name.
    var referenceA: [[String]] {
        [
            ["Bench press", "Barbell row", "Overhead press", "Lat pulldown", "Triceps pushdown", "Barbell curl"],
            ["Back squat", "Deadlift", "Leg press", "Lying leg curl", "Standing calf raise"],
            ["Bench press", "Chin-up", "Incline dumbbell press", "Seated cable row", "Lateral raise", "Hammer curl"],
            ["Back squat", "Romanian deadlift", "Walking lunge", "Leg extension", "Seated calf raise"],
        ]
    }

    var referenceB: [[String]] {
        [
            ["Back squat", "Bench press", "Barbell row", "Dip", "Lying leg curl", "Barbell curl"],
            ["Back squat", "Overhead press", "Deadlift", "Pull-up", "Lateral raise", "Triceps pushdown"],
            ["Back squat", "Bench press", "Leg press", "Chest-supported row", "Standing calf raise", "Hammer curl"],
        ]
    }

    var referenceC: [[String]] {
        [
            ["Bench press", "Bench press", "Incline dumbbell press", "Cable fly", "Assisted dip"],
            ["Deadlift", "Weighted pull-up", "Barbell row", "Seated cable row", "Barbell shrug"],
            ["Back squat", "Romanian deadlift", "Leg press", "Leg extension", "Lying leg curl", "Standing calf raise"],
            ["Overhead press", "Landmine press", "Lateral raise", "Rear delt fly"],
            ["Close-grip bench press", "Barbell curl", "Skull crusher", "Hammer curl", "Triceps pushdown"],
        ]
    }

    var inclineDumbbellPress: PowerJackExercise { library("Incline dumbbell press") }

    /// The examples' library data (examples-sim.py, reading G17): every exercise is loaded and multi-joint
    /// with its pattern unless single-joint, bodyweight or assisted. The landmine press has no pattern or
    /// multi-joint data, so R1.1's fallbacks read it.
    func library(_ name: String, multiJoint: Bool? = nil) -> PowerJackExercise {
        let (primary, secondaries, fatigue, pattern, kind): (Muscle, [Muscle], FatigueLevel, PowerJackPattern?, String) = switch name {
        case "Bench press", "Incline dumbbell press": (.chest, [.triceps, .shoulders], .high, .horizontalPush, "")
        case "Barbell row", "Chest-supported row": (.back, [.biceps, .shoulders], .high, .horizontalPull, "")
        case "Overhead press": (.shoulders, [.triceps], .high, .verticalPush, "")
        case "Lat pulldown", "Weighted pull-up": (.back, [.biceps], .high, .verticalPull, "")
        case "Seated cable row": (.back, [.biceps], .high, .horizontalPull, "")
        case "Chin-up", "Pull-up": (.back, [.biceps], .high, .verticalPull, "bw")
        case "Back squat", "Front squat", "Leg press", "Walking lunge": (.quads, [.glutes], .high, .squat, "")
        case "Deadlift", "Romanian deadlift": (.hamstrings, [.glutes, .back], .high, .hinge, "")
        case "Dip": (.chest, [.triceps, .shoulders], .high, .verticalPush, "bw")
        case "Assisted dip": (.chest, [.triceps, .shoulders], .high, .verticalPush, "as")
        case "Close-grip bench press": (.triceps, [.chest, .shoulders], .high, .horizontalPush, "")
        case "Triceps pushdown": (.triceps, [], .low, nil, "")
        case "Barbell curl", "Hammer curl": (.biceps, [.forearms], .low, nil, "")
        case "Lying leg curl": (.hamstrings, [], .moderate, nil, "")
        case "Standing calf raise", "Seated calf raise": (.calves, [], .low, nil, "")
        case "Lateral raise": (.shoulders, [], .low, nil, "")
        case "Leg extension": (.quads, [], .moderate, nil, "")
        case "Cable fly": (.chest, [], .low, nil, "")
        case "Barbell shrug": (.back, [.forearms], .moderate, nil, "")
        case "Rear delt fly": (.shoulders, [.back], .low, nil, "")
        case "Skull crusher": (.triceps, [], .moderate, nil, "")
        case "Landmine press": (.shoulders, [.triceps], .moderate, PowerJackExercise.traits(catalogID: nil, primary: .shoulders, fatigue: .moderate).0, "")
        default: (.chest, [], .moderate, nil, "")
        }
        let isLandmine = name == "Landmine press"
        return PowerJackExercise(
            id: name,
            pattern: pattern,
            multiJoint: multiJoint ?? (isLandmine ? fatigue == .high : pattern != nil),
            repsOnly: kind == "bw",
            assisted: kind == "as",
            isBarbell: true,
            fatigue: fatigue,
            primary: primary,
            secondaries: secondaries
        )
    }

    /// Main lifts in the order R1.1 finds them, and each workout's slots as the rulebook lists them.
    func describe(_ workouts: [[String]], landmine: PowerJackExercise? = nil) -> (mains: [String], rows: [String]) {
        let structure = workouts.map { $0.map { $0 == "Landmine press" ? landmine ?? library($0) : library($0) } }
        let roles = PowerJackRoles.assign(structure)
        var mains: [String] = []
        let rows = workouts.indices.map { w in
            workouts[w].indices.map { e in
                let name = workouts[w][e]
                let role = roles[w][e]
                guard role.role == .main else { return "\(name) \(role.role == .secondary ? "S" : "A")" }
                if !mains.contains(name) { mains.append(name) }
                let entries = workouts[w].indices.filter { workouts[w][$0] == name }
                let kind = switch role.tag {
                case _ where entries.count > 1: entries.first == e ? "TOP entry (H)" : "BACK entry (V)"
                case .topAndBack: "T+B"
                case .heavy: "H"
                default: "V"
                }
                return "\(name) M \(kind)"
            }.joined(separator: "; ")
        }
        return (mains, rows)
    }

    /// Plans logged 5 days ago that imply these H and V anchors, as `anchorHistory` does for example 1.
    func anchors(_ table: [String: (heavy: Double, volume: Double, tag: PowerJackTag)]) -> (AnyHashable) -> [PowerJackExposure] {
        { id in
            guard let key = id.base as? String, let anchor = table[key] else { return [] }
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
    }

    /// A squat last trained `daysAgo`, from a plan that implies a 300 lb H anchor.
    func lastSquat(daysAgo: Double) -> (AnyHashable) -> [PowerJackExposure] {
        let date = Date.now.addingTimeInterval(-daysAgo * 86_400)
        let load = 300 * PowerJackPercent.percent(reps: 7)! / 100
        let entry = PowerJackEntryLog(exercise: squat, sets: [.done(5, at: PowerJackSteps().roundDown(load), date: date)], target: 2, loadTarget: load, pain: LevelOfPain.none)
        return { id in id == self.squat.id ? [PowerJackExposure(date: date, entry: entry, weekType: .build, tag: .heavy)] : [] }
    }

    /// An H exposure of the squat whose value is `e1RM`: 5 reps tapped `tap`, or with a stored target when
    /// `loadTarget` (which implies `e1RM` as an anchor).
    func exposure(e1RM: Double, daysAgo: Double, tap: Int?, loadTarget: Bool = false) -> PowerJackExposure {
        let date = Date.now.addingTimeInterval(-daysAgo * 86_400)
        let load = e1RM * PowerJackPercent.percent(reps: Double(5 + min(tap ?? 2, PowerJackRules.rirCensor)))! / 100
        let entry = PowerJackEntryLog(
            exercise: squat, sets: [.done(5, at: load, date: date)], target: 2, loadTarget: loadTarget ? load : nil,
            rir: loadTarget ? nil : tap, pain: LevelOfPain.none
        )
        return PowerJackExposure(date: date, entry: entry, weekType: .build, tag: .heavy)
    }

    /// R2.4 run from every set at the top of the range, MET each week, until the load jumps or holds.
    enum JumpPoint: Equatable {
        case jump(at: Int, planned: Int)
        case holds(at: Int)
    }

    func jumpPoint(_ exercise: PowerJackExercise, load: Double) -> JumpPoint? {
        let builder = builder([], structure: [[exercise]])
        let range = PowerJackRules.accessoryRange(exercise.fatigue)
        var reps = [range.upperBound, range.upperBound]
        for _ in 0..<40 {
            let part = PowerJackPart(sets: reps.map { .done($0, at: load) }, tap: 2)
            let result = builder.doubleProgression(part, previous: nil, outcome: .met, range: range, exercise: exercise, caution: false, held: false, setFell: false)
            switch result.reason {
            case .loadJump: return .jump(at: reps.min()!, planned: result.sets[0].reps!)
            case .hold: return .holds(at: reps.min()!)
            default: reps = result.sets.map { $0.reps! }
            }
        }
        return nil
    }

    func single(_ id: String, _ muscle: Muscle, fatigue: FatigueLevel) -> PowerJackExercise {
        exercise(id, nil, multiJoint: false, fatigue: fatigue, primary: muscle)
    }

    /// "3x5@195", or "1x5@335 2x8@305" for a TOP set and BACK sets.
    func sets(_ entry: PowerJackEntryPlan) -> String {
        var runs: [(count: Int, set: PowerJackSetPlan)] = []
        for set in entry.sets {
            if let last = runs.last, last.set == set { runs[runs.count - 1].count += 1 } else { runs.append((1, set)) }
        }
        return runs.map { "\($0.count)x\($0.set.reps ?? 0)@\(PowerJackSimText.pounds($0.set.load))" }.joined(separator: " ")
    }

    /// A week logged as planned and tapped at its targets, with `change` for the slots the example logs otherwise.
    func asPlanned(_ plan: PowerJackWeekPlan, load: Double, change: (SlotRef, PowerJackEntryLog) -> PowerJackEntryLog) -> PowerJackWeekLog {
        var week = asPlanned(plan, load: load)
        for w in week.workouts.indices {
            for e in week.workouts[w].entries.indices {
                week.workouts[w].entries[e] = change(SlotRef(workout: w, entry: e), week.workouts[w].entries[e])
            }
        }
        return week
    }

    func retap(_ entry: PowerJackEntryLog, _ tap: Int) -> PowerJackEntryLog {
        var entry = entry
        entry.rir = tap
        entry.topRIR = entry.topSets > 0 ? tap : nil
        return entry
    }

    /// The same slot with these sets done, against the planned reps and load.
    func redo(_ entry: PowerJackEntryLog, _ done: [(reps: Int, load: Double)]) -> PowerJackEntryLog {
        var entry = entry
        entry.sets = zip(entry.sets, done).map { set, done in
            var set = set
            (set.reps, set.load) = (done.reps, done.load)
            return set
        }
        return entry
    }

    /// A slot of a skipped workout: nothing done.
    func skipped(_ plan: PowerJackEntryPlan) -> PowerJackEntryLog {
        PowerJackEntryLog(
            exercise: plan.exercise,
            sets: plan.sets.map { PowerJackSetLog(plannedReps: $0.reps, plannedLoad: $0.load, isSkipped: true) },
            topSets: plan.topSets, target: plan.target, loadTarget: plan.loadTarget, topLoadTarget: plan.topLoadTarget,
            calibrating: plan.calibrating
        )
    }

    func near(_ value: Double, _ shown: Double) -> Bool {
        abs(value - shown) <= 0.05 + 1e-9
    }

    func tenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    func percent(_ reps: Int) -> Int {
        PowerJackPercent.percent(reps: Double(reps))!.roundedHalfUp
    }
}

extension PowerJackWeekPlan {
    subscript(slot: SlotRef) -> PowerJackEntryPlan { workouts[slot.workout][slot.entry] }
}
