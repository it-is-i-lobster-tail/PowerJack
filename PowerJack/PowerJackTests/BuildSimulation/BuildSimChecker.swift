//
//  BuildSimChecker.swift
//  PowerJackTests
//
//  The rules every week the Build planner writes must keep, whatever the lifter did. Each check names the
//  rulebook rule it guards. Checks read the stored week, the engine's own view of the logs, and the plan
//  the engine gives for the same logs.
//

import Foundation
@testable import PowerJack

struct BuildSimViolation: CustomStringConvertible {
    var rule: String
    var place: String
    var detail: String

    var description: String { "[\(rule)] \(place): \(detail)" }
}

/// One planned exercise as stored in a program week.
struct BuildSimSlot {
    let workoutExercise: WorkoutExercise
    let exercise: Exercise

    var info: BuildExercise { BuildPlanner.exerciseInfo(exercise) }
    var sets: Int { workoutExercise.workingSets.count }
    var reps: Int? { workoutExercise.workingSets.first?.repsPlanned }
    var load: Int? { workoutExercise.workingSets.first?.weightTenthsPlannedPounds }
    var code: BuildReason.Code? { workoutExercise.progressionCode.flatMap(BuildReason.Code.init(rawValue:)) }
    var name: String { exercise.exerciseName }

    /// Slots in engine order: by workout, then by place in the workout.
    static func all(in week: ProgramWeek, plannedOnly: Bool = false) -> [BuildSimSlot] {
        week.workouts
            .filter { !plannedOnly || $0.status == .planned }
            .flatMap(\.workoutExercises)
            .compactMap { workoutExercise in
                workoutExercise.exercise.map { BuildSimSlot(workoutExercise: workoutExercise, exercise: $0) }
            }
    }
}

@MainActor
struct BuildSimChecker {
    /// Where the lifter is, for messages: program, template and week.
    var place = ""
    private(set) var violations: [BuildSimViolation] = []
    private(set) var weeksChecked = 0

    // MARK: Entry points

    /// A new program's week 1: block week 1, each exercise seeded from history or calibrating (START-03, START-04).
    mutating func checkFirstWeek(of program: Program) {
        guard let week = program.programWeeks.first else {
            fail("PROGRAM", "a new program has no weeks")
            return
        }
        weeksChecked += 1
        let here = "\(place) week 1"
        expect(week.weekKind == .build && week.blockWeek == 1 && week.returnBand == 0, "BLK-02", here,
               "week 1 is \(BuildSimText.describe(week)), not build week 1")
        let weekOne = BuildWeek(
            kind: .build,
            blockWeek: 1,
            buildWeeks: ProgramBlocks.buildWeeks(blockStart: 0, programWeeks: program.programLengthWeeks)
        )
        for slot in BuildSimSlot.all(in: week) {
            checkSlot(slot, in: weekOne, at: here)
            expect(slot.code == .calibrate || slot.code == .startHistory, "START-04", "\(here) \(slot.name)",
                   "week 1 code is \(slot.code?.rawValue ?? "none")")
            let aim = BuildEngine.aim(for: weekOne, exercise: slot.info, reps: slot.reps, failureBlocked: true,
                                      calibrating: slot.code == .calibrate)
            expect(slot.workoutExercise.rirTarget == aim, "START-03", "\(here) \(slot.name)",
                   "aims for \(slot.workoutExercise.rirTarget.map(String.init) ?? "nothing") reps left, not \(aim)")
        }
    }

    /// A week the planner just built from the finished week before it.
    mutating func checkBuild(of program: Program, week index: Int) {
        let weeks = program.programWeeks
        guard weeks.indices.contains(index), index > 0 else { return }
        weeksChecked += 1
        let here = "\(place) week \(index + 1)"
        let entries = weeks[index - 1].workouts.flatMap { workout in
            workout.workoutExercises.filter { $0.exercise != nil }.map { (workout, $0) }
        }
        let input = BuildPlanner.input(for: program, through: index - 1, slots: entries)
        let context = BuildContext(input)
        let plan = BuildEngine.plan(input)
        let slots = BuildSimSlot.all(in: weeks[index])

        checkStored(slots, week: weeks[index], against: plan, at: here)
        checkClock(context, next: plan.week, at: here)
        checkFit(program, next: plan, at: index, here: here)
        for (index, slot) in zip(plan.slots.indices, slots) {
            checkSlot(slot, in: plan.week, at: "\(here) \(slot.name)")
            checkProgression(context, index, plan.slots[index], week: plan.week, at: "\(here) \(slot.name)")
        }
        checkVolume(context, plan, at: here)
    }

    /// A week replanned at its first workout after a long break (CLOCK 0, BLK-07, BLK-08).
    mutating func checkBreak(in program: Program, week index: Int, band: Int, replanned: Bool) {
        let weeks = program.programWeeks
        guard weeks.indices.contains(index) else { return }
        let week = weeks[index]
        let here = "\(place) week \(index + 1) after a band \(band) break"
        expect(week.returnBand == band, "BLK-07", here, "the week records band \(week.returnBand)")
        guard replanned, index > 0 else { return }
        weeksChecked += 1
        let planned = week.workouts.filter { $0.status == .planned }
        let entries = planned.flatMap { workout in
            workout.workoutExercises.filter { $0.exercise != nil }.map { (workout, $0) }
        }
        let input = BuildPlanner.input(for: program, through: index - 1, slots: entries)
        let plan = BuildEngine.planAfterBreak(input, band: band)
        let slots = BuildSimSlot.all(in: week, plannedOnly: true)
        checkStored(slots, week: week, against: plan, at: here)

        let context = BuildContext(input)
        let expected = band >= 2 ? BuildWeek(kind: .return, blockWeek: 1, returnBand: band) : context.nextBuildWeek(blockWeek: 1)
        expect(plan.week == expected, "BLK-07", here, "the week became \(BuildSimText.describe(plan.week))")
        for (index, slot) in zip(plan.slots.indices, slots) {
            checkSlot(slot, in: plan.week, at: "\(here) \(slot.name)")
            if band >= 2 {
                checkReturn(context, index, plan.slots[index], week: plan.week, at: "\(here) \(slot.name)")
            }
        }
    }

    // MARK: Checks

    /// The planner stored exactly what the engine plans from the same logs (ENG-04): same sets, reps, load,
    /// aim and code, and the week's place in its block.
    private mutating func checkStored(_ slots: [BuildSimSlot], week: ProgramWeek, against plan: BuildPlan, at here: String) {
        expect(slots.count == plan.slots.count, "ENG-04", here, "stored \(slots.count) exercises, the engine planned \(plan.slots.count)")
        expect(week.weekKind == plan.week.kind && week.blockWeek == plan.week.blockWeek, "ENG-04", here,
               "stored as \(BuildSimText.describe(week)), the engine planned \(BuildSimText.describe(plan.week))")
        for (slot, slotPlan) in zip(slots, plan.slots) {
            let storedReps = slotPlan.reps.flatMap { WorkoutSet.isValidReps($0) ? $0 : nil }
            expect(slot.sets == min(slotPlan.sets, WorkoutExercise.maxSets) && slot.reps == storedReps && slot.load == slotPlan.load
                   && slot.workoutExercise.rirTarget == slotPlan.rirTarget && slot.code == slotPlan.reason.code,
                   "ENG-04", "\(here) \(slot.name)",
                   "stored \(BuildSimText.describe(slot)), the engine planned \(BuildSimText.describe(slotPlan))")
            expect(slotPlan.reps.map(WorkoutSet.isValidReps) ?? true, "ENG-01", "\(here) \(slot.name)",
                   "planned \(slotPlan.reps ?? 0) reps, which a set can't hold")
        }
    }

    /// What every planned exercise must look like, whatever came before (ENG-01, ENG-03, EFF-01, LOAD-09).
    private mutating func checkSlot(_ slot: BuildSimSlot, in week: BuildWeek, at here: String) {
        let info = slot.info
        let workoutExercise = slot.workoutExercise
        expect(slot.code != nil, "ENG-03", here, "no reason code (stored \(workoutExercise.progressionCode ?? "nil"))")
        expect(!(workoutExercise.progressionNote ?? "").isEmpty, "ENG-03", here, "no reason line")
        if let rir = workoutExercise.rirTarget {
            let allowed = week.kind == .build ? 0...BuildRules.startRIR : BuildRules.deloadRIR...BuildRules.deloadRIR
            expect(allowed.contains(rir), "EFF-01", here, "aims for \(rir) reps left in a \(week.kind.rawValue) week")
            if rir == 0 {
                expect(week.blockWeek == week.buildWeeks && BuildRules.failureFatigueLevels.contains(info.fatigueLevel),
                       "EFF-04", here, "failure offered in block week \(week.blockWeek) to a \(info.fatigueLevel.name) fatigue exercise")
            }
        } else {
            fail("EFF-01", here, "no reps-left aim")
        }

        let sets = workoutExercise.workingSets
        expect((1...WorkoutExercise.maxSets).contains(sets.count), "ENG-01", here, "\(sets.count) working sets")
        expect(Set(sets.map(\.repsPlanned)).count <= 1 && Set(sets.map(\.weightTenthsPlannedPounds)).count <= 1,
               "LOAD-01", here, "sets planned unevenly: \(sets.map { "\($0.repsPlanned ?? 0)@\($0.weightTenthsPlannedPounds ?? 0)" })")

        if let reps = slot.reps, week.kind == .build {
            let ceiling = BuildEngine.repCeiling(info, repTarget: reps)
            expect((info.minReps...max(info.minReps, ceiling)).contains(reps), "ENG-01", here,
                   "\(reps) reps, outside \(info.minReps)-\(ceiling)")
        }
        if info.repsOnly {
            expect(slot.load == nil, "LOAD-09", here, "a bodyweight exercise planned at \(BuildSimText.pounds(slot.load))")
        } else if let load = slot.load {
            expect(load > 0 && load <= WorkoutSet.maxWeightPounds * 10, "LIMITS", here,
                   "planned \(BuildSimText.pounds(load)), outside what a set can log (0-\(WorkoutSet.maxWeightPounds) lb)")
        }
        if slot.code == .painCheckIn {
            expect(workoutExercise.checkIn == .pending && (workoutExercise.checkInSourcePain?.rawValue ?? 0) >= BuildRules.checkInAt.rawValue,
                   "PAIN-01", here, "a pain check-in that isn't waiting (\(workoutExercise.checkIn.rawValue))")
        }
    }

    /// The block clock (BLK-02, BLK-03, BLK-05, BLK-07, FREQ-06).
    private mutating func checkClock(_ context: BuildContext, next: BuildWeek, at here: String) {
        let last = context.lastWeek
        let trained = context.slots.indices.contains { context.exposure($0, inWeek: context.lastIndex)?.isDone == true }
        let deload = BuildWeek(kind: .deload, blockWeek: last.blockWeek + 1)
        let weekOne = context.nextBuildWeek(blockWeek: 1)
        let expected: [BuildWeek] = switch last.kind {
        case .build where !trained:
            [context.nextBuildWeek(blockWeek: last.blockWeek)]
        case .build where last.blockWeek >= last.buildWeeks:
            [deload]
        case .build:
            [context.nextBuildWeek(blockWeek: last.blockWeek + 1), deload]
        case .deload:
            [weekOne]
        case .return where !trained:
            [last]
        case .return where last.returnBand == 3 && last.blockWeek < BuildRules.returnWeeks[2]:
            [BuildWeek(kind: .return, blockWeek: last.blockWeek + 1, returnBand: 3)]
        case .return:
            [weekOne]
        }
        expect(expected.contains(next), "BLK-02", here,
               "after \(trained ? "" : "an untrained ")\(BuildSimText.describe(last)) came \(BuildSimText.describe(next)), expected \(expected.map(BuildSimText.describe).joined(separator: " or "))")
        expect(next.kind != .build || next.blockWeek <= next.buildWeeks, "BLK-02", here,
               "build week \(next.blockWeek) of a \(next.buildWeeks)-week block")
        expect(next.kind != .build || (ProgramBlocks.minBuildWeeks...ProgramBlocks.maxBuildWeeks).contains(next.buildWeeks),
               "BLK-02", here, "a block of \(next.buildWeeks) build weeks")
    }

    /// A program run without a repeated week, a break or an early deload keeps the blocks laid out to fit its
    /// length, so it ends on a deload (BLK-02).
    private mutating func checkFit(_ program: Program, next plan: BuildPlan, at index: Int, here: String) {
        let weeks = program.programWeeks.prefix(index)
        let reactive = { (codes: [BuildReason.Code?]) in codes.contains(.deloadReactive) }
        var lastBlockWeek = 0
        for week in weeks {
            guard week.returnBand == 0, week.weekKind != .return else { return }
            if week.weekKind == .deload {
                guard !reactive(BuildSimSlot.all(in: week).map(\.code)) else { return }
                lastBlockWeek = 0
            } else {
                guard week.blockWeek == lastBlockWeek + 1 else { return }
                lastBlockWeek = week.blockWeek
            }
        }
        guard !reactive(plan.slots.map(\.reason.code)) else { return }
        let planned = ProgramBlocks.layout(weeks: program.programLengthWeeks, carry: 0)
        guard planned.indices.contains(index) else { return }
        expect(plan.week.kind == planned[index], "BLK-02", here,
               "week \(index + 1) of \(program.programLengthWeeks) is a \(plan.week.kind.rawValue) week, laid out as \(planned[index].rawValue)")
    }

    /// One exercise's plan against its own log: what may rise, what must hold and what must fall.
    private mutating func checkProgression(_ context: BuildContext, _ index: Int, _ plan: BuildSlotPlan, week: BuildWeek, at here: String) {
        let exercise = context.slots[index].exercise
        let state = context.states[index]
        let code = plan.reason.code
        guard let latest = context.latest(index) else { return }
        let done = context.latestDone(index)

        switch week.kind {
        case .deload:
            // BLK-04: half the build week's sets at no more than its load, 3 reps left.
            guard let build = context.latest(index, in: .build) ?? context.latest(index) else { return }
            expect(plan.sets <= BuildEngine.scaled(build.plannedSets, by: BuildRules.deloadSetFactor), "BLK-04", here,
                   "deload keeps \(plan.sets) of \(build.plannedSets) sets")
            expect(lighterOrSame(plan.load, than: build.load), "BLK-04", here,
                   "deload at \(BuildSimText.pounds(plan.load)) after a build week at \(BuildSimText.pounds(build.load))")
            // A slot waiting on a pain check-in keeps that reason (PAIN-02).
            expect([.deloadPlanned, .deloadReactive, .painCheckIn].contains(code) || plan.checkInPain != nil, "BLK-04", here,
                   "deload code \(code.rawValue)")
            return
        case .return:
            checkReturn(context, index, plan, week: week, at: here)
            return
        case .build:
            break
        }

        let newBlock = week.blockWeek == 1
        // FREQ-06: inside a block, an exercise with nothing logged last time repeats that plan.
        if !latest.isDone, !newBlock {
            let reps = latest.repTarget.map { min(max($0, exercise.minReps), BuildEngine.repCeiling(exercise, repTarget: $0)) }
            expect(plan.sets == min(max(latest.plannedSets, 1), BuildRules.maxSetsPerExercise) && plan.reps == reps && plan.load == latest.plannedLoad,
                   "FREQ-06", here, "nothing was logged after \(BuildSimText.describe(latest)), but planned \(BuildSimText.describe(plan))")
            return
        }
        guard let done else { return }
        // A new block starts from the block's last build week, or its last return week, not from the deload.
        let rebaseKind: WeekKind = context.lastWeek.kind == .return ? .return : .build
        let blockBase = newBlock ? context.latest(index, in: rebaseKind) ?? done : done
        let reference = state.painHold ? done : blockBase
        let current = reference.repTarget ?? reference.repsDone ?? exercise.minReps
        // Reps clamped up to the bottom of the range are not an increase (ENG-01).
        let rose = (plan.load ?? 0) > (reference.load ?? 0) || (plan.reps ?? 0) > max(current, exercise.minReps)
            || plan.sets > reference.plannedSets

        // PAIN-01, PAIN-03: a held or rising-pain exercise never gets more of anything, and a new block doesn't
        // lift a held one.
        if state.painHold || state.painRose {
            expect(!rose, "PAIN-01", here,
                   "pain \(done.pain?.label ?? "untapped")\(state.painHold ? " (held)" : "")\(state.painRose ? " (rising)" : ""), but \(BuildSimText.describe(reference)) became \(BuildSimText.describe(plan))")
        }
        // PAIN-01: Severe pain or worse cuts the next exposure behind a check-in.
        if latest.isDone, let pain = done.pain, pain.rawValue >= BuildRules.checkInAt.rawValue {
            expect(plan.checkInPain != nil, "PAIN-01", here, "\(pain.label) pain after \(BuildSimText.describe(done)), but no check-in")
        }
        // LOAD-07: a miss holds, and two in a row never earn more.
        if done.missed, !newBlock, !state.painHold, !context.isCalibration(index, done), ![.loadDown, .painSetBack].contains(code) {
            expect(!rose, "LOAD-07", here, "a set fell short in \(BuildSimText.describe(done)), but it became \(BuildSimText.describe(plan))")
        }
        if state.missStreak >= BuildRules.missStreakForBackoff, !newBlock, !state.painHold {
            expect(![.repsUp, .loadUp, .unratedStep, .volumeRamp, .volumeUp].contains(code), "LOAD-07", here,
                   "miss streak \(state.missStreak) after \(BuildSimText.describe(done)), but planned \(BuildSimText.describe(plan))")
        }
        // ENG-02: without a tapped rating, one rep or one 5 lb step at most, and never a set.
        if context.reading(index, done).kind == .unrated, !newBlock, !context.isCalibration(index, done) {
            let repCap = max(current, (done.repsDone ?? current) + BuildRules.repsPerStep, exercise.minReps)
            expect((plan.reps ?? 0) <= repCap && (plan.load ?? 0) <= (done.load ?? 0) + BuildRules.stepTenths && plan.sets <= done.plannedSets,
                   "ENG-02", here, "unrated \(BuildSimText.describe(done)) became \(BuildSimText.describe(plan))")
        }
        // BLK-07, VOL-05: the block after return weeks holds the sets from before the break; only pain cuts them.
        if newBlock, context.lastWeek.kind == .return, let preBreak = context.latest(index, in: .build), !state.painHold, !state.painRose,
           ![.painCheckIn, .painHold, .painReduce, .painRising, .calibrate, .calibrated].contains(code) {
            expect(plan.sets >= min(preBreak.plannedSets, BuildRules.maxSetsPerExercise), "BLK-07", here,
                   "the block after return weeks plans \(plan.sets) sets, fewer than the \(preBreak.plannedSets) from before the break")
        }
        // BLK-07: through the first block after return weeks, the engine raises no load past 10% (at least 5 lb) over
        // the last return load. A heavier weight the lifter chose stays theirs.
        if let cap = firstBlockCap(context, index, newBlock: newBlock), let load = plan.load {
            expect(load <= max(cap, done.load ?? 0), "BLK-07", here, "planned \(BuildSimText.pounds(load)) in the first block after a return, over \(BuildSimText.pounds(cap))")
        }
        // PAIN-03, BLK-06: a hold released in the week that ends a block resumes from its last exposure.
        if newBlock, state.exposuresSinceRelease == 0, code == .blockRebase, !exercise.repsOnly {
            expect(lighterOrSame(plan.load, than: done.load), "PAIN-03", here,
                   "released after \(BuildSimText.describe(done)), but the new block starts at \(BuildSimText.describe(plan))")
        }
        // START-06, LOAD-04, LOAD-06: how far a load may rise in one week. A new block measures from its last build
        // week, except where pain or a released hold keeps the slot where its last exposure left it.
        let fromLast = !newBlock || [.painCheckIn, .painHold, .painReduce, .painRising, .painSetBack].contains(code)
            || state.exposuresSinceRelease == 0
        if let load = plan.load, let base = fromLast ? done.load : max(blockBase.load ?? 0, done.load ?? 0), load > base {
            let cap: Int = switch code {
            case .calibrated: base + BuildEngine.floorToStep(Double(base) * BuildRules.calibrationMaxJumpPct / 100)
            case .loadUp: base + max(BuildRules.stepTenths, BuildEngine.floorToStep(Double(base) * BuildRules.easyJumpMaxPct / 100))
            case .unratedStep, .blockRebase, .volumeDown: base + BuildRules.stepTenths
            case .repeatNotDone, .calibrate: max(base, latest.plannedLoad ?? base)
            default: base
            }
            expect(load <= cap, "START-06", here, "\(code.rawValue) raised \(BuildSimText.pounds(base)) to \(BuildSimText.pounds(load)), past \(BuildSimText.pounds(cap))")
        }
        // ENG-01, VOL-07: a set and more weight never come in the same week.
        if !newBlock, plan.sets > done.plannedSets, let load = plan.load, let base = done.load {
            expect(load <= base, "VOL-07", here, "\(BuildSimText.describe(done)) became \(BuildSimText.describe(plan)): a set and \(BuildSimText.pounds(load - base)) more at once")
        }
    }

    /// The most a slot may lift in the first block after return weeks: the last return load plus the larger of
    /// 5 lb and 10% (BLK-07). Nil outside that block.
    private func firstBlockCap(_ context: BuildContext, _ index: Int, newBlock: Bool) -> Int? {
        let block = context.blocks[context.lastIndex] + (newBlock ? 1 : 0)
        let returnWeeks = context.weekIndexes(inBlock: block - 1)
        guard
            !returnWeeks.isEmpty,
            returnWeeks.allSatisfy({ context.weeks[$0].kind == .return }),
            let load = context.slots[index].history.last(where: { returnWeeks.contains($0.weekIndex) })?.load
        else {
            return nil
        }
        return load + max(BuildRules.stepTenths, BuildEngine.floorToStep(Double(load) * BuildRules.firstBlockLoadCapPct / 100))
    }

    /// Return weeks keep a share of the pre-break load and sets (BLK-07). A break that cuts return weeks short
    /// measures from the return weeks instead.
    private mutating func checkReturn(_ context: BuildContext, _ index: Int, _ plan: BuildSlotPlan, week: BuildWeek, at here: String) {
        guard let before = context.latest(index, in: .build) else { return }
        let band = min(max(week.returnBand, 1), 3)
        let keep = (100 - BuildRules.returnLoadCutPct[band - 1]) / 100
        let nested = week.blockWeek == 1 && context.lastWeek.kind == .return
        let reference = nested ? context.latest(index, in: .return) ?? before : before
        if let load = plan.load, let preBreak = reference.load {
            let cap = max(BuildRules.stepTenths, BuildEngine.floorToStep(Double(preBreak) * keep))
            expect(load <= cap, "BLK-07", here, "return week at \(BuildSimText.pounds(load)), over \(BuildSimText.pounds(cap)) (\(Int(keep * 100))% of \(BuildSimText.pounds(preBreak)))")
        }
        let sets = week.blockWeek == 1
            ? BuildEngine.scaled(before.plannedSets, by: BuildRules.returnSetFactor[band - 1])
            : before.plannedSets
        expect(plan.sets <= sets, "BLK-07", here, "return week \(week.blockWeek) has \(plan.sets) sets, more than \(sets)")
        expect(plan.rirTarget == BuildRules.startRIR, "BLK-07", here, "return week aims for \(plan.rirTarget) reps left")
    }

    /// No automatic increase takes a muscle past its weekly ceiling or 12 sets in one workout (VOL-03, FREQ-02),
    /// and ramp-in keeps its pace (VOL-02).
    private mutating func checkVolume(_ context: BuildContext, _ plan: BuildPlan, at here: String) {
        guard
            plan.week.kind == .build,
            let reference = context.weeks.indices.last(where: { context.weeks[$0].kind == .build })
        else {
            return
        }
        // Sets each slot had in the last build week, the base any increase is measured from (VOL-04).
        let before = context.slots.indices.map { context.exposure($0, inWeek: reference)?.plannedSets ?? context.latest($0)?.plannedSets ?? 0 }
        let added = plan.slots.indices.filter { [.volumeRamp, .volumeUp].contains(plan.slots[$0].reason.code) }
        for muscle in Muscle.allCases {
            let planned = credits(of: muscle, context, plan.slots.indices, sets: plan.slots.map(\.sets))
            let earlier = credits(of: muscle, context, context.slots.indices, sets: before)
            let ceiling = context.input.focus.contains(muscle) ? BuildRules.focusCeiling : BuildRules.ceiling
            if planned > earlier, added.contains(where: { context.slots[$0].exercise.credits[muscle] != nil }) {
                expect(planned <= ceiling, "VOL-03", here, "\(muscle.rawValue) rose from \(earlier) to \(planned) credits, past \(ceiling)")
            }
            let ramped = added.filter { plan.slots[$0].reason.code == .volumeRamp && context.slots[$0].exercise.primary == muscle }
            expect(ramped.count <= BuildRules.rampInPerWeek, "VOL-02", here, "\(muscle.rawValue) ramped in \(ramped.count) sets in one week")
        }
        // VOL-02, FAT-02: per block, at most one ramp-in set per slot, two per muscle, and one fatigue cut per muscle.
        if plan.week.blockWeek > 1 {
            let block = context.blocks[context.lastIndex]
            let counts = { (code: BuildReason.Code, slot: Int) in
                context.slots[slot].history.count { context.blocks[$0.weekIndex] == block && $0.code == code }
                    + (plan.slots[slot].reason.code == code ? 1 : 0)
            }
            for muscle in Muscle.allCases {
                let primary = context.slots.indices.filter { context.slots[$0].exercise.primary == muscle }
                let ramps = primary.map { counts(.volumeRamp, $0) }
                expect(ramps.allSatisfy { $0 <= 1 } && ramps.reduce(0, +) <= BuildRules.rampInMaxPerBlock, "VOL-02", here,
                       "\(muscle.rawValue) took ramp-in sets \(ramps) this block")
                let cuts = primary.reduce(0) { $0 + counts(.fatigueCut, $1) }
                expect(cuts <= BuildRules.localCutSets, "FAT-02", here, "\(muscle.rawValue) took \(cuts) fatigue cuts this block")
            }
        }
        for workout in Set(context.slots.map(\.workout)).sorted() {
            let indexes = context.slots.indices.filter { context.slots[$0].workout == workout }
            for muscle in Muscle.allCases where added.contains(where: { indexes.contains($0) && context.slots[$0].exercise.credits[muscle] != nil }) {
                let planned = credits(of: muscle, context, indexes, sets: plan.slots.map(\.sets))
                let earlier = credits(of: muscle, context, indexes, sets: before)
                if planned > earlier {
                    expect(planned <= BuildRules.maxCreditsPerSessionPerMuscle, "FREQ-02", here,
                           "\(muscle.rawValue) rose from \(earlier) to \(planned) credits in workout \(workout + 1)")
                }
            }
        }
    }

    // MARK: Helpers

    private func credits(of muscle: Muscle, _ context: BuildContext, _ indexes: some Sequence<Int>, sets: [Int]) -> Double {
        indexes.reduce(0.0) { $0 + (context.slots[$1].exercise.credits[muscle] ?? 0) * Double(sets[$1]) }
    }

    private func lighterOrSame(_ load: Int?, than other: Int?) -> Bool {
        guard let load, let other else { return true }
        return load <= other
    }

    private mutating func expect(_ condition: Bool, _ rule: String, _ place: String, _ detail: @autoclosure () -> String) {
        guard !condition else { return }
        fail(rule, place, detail())
    }

    private mutating func fail(_ rule: String, _ place: String, _ detail: String = "") {
        violations.append(BuildSimViolation(rule: rule, place: place, detail: detail))
    }
}

//
// Text for messages and traces
//
enum BuildSimText {
    /// "225", "47.5", or "bw" for no load.
    static func pounds(_ tenths: Int?) -> String {
        guard let tenths else { return "bw" }
        return tenths % 10 == 0 ? "\(tenths / 10)" : String(format: "%.1f", Double(tenths) / 10)
    }

    static func describe(_ week: BuildWeek) -> String {
        "\(week.kind.rawValue) \(week.blockWeek)\(week.returnBand > 0 ? " band \(week.returnBand)" : "")"
    }

    static func describe(_ week: ProgramWeek) -> String {
        "\(week.weekKind?.rawValue ?? "unset") \(week.blockWeek)\(week.returnBand > 0 ? " band \(week.returnBand)" : "")"
    }

    static func describe(_ slot: BuildSimSlot) -> String {
        "\(slot.sets)×\(slot.reps.map(String.init) ?? "?")@\(pounds(slot.load)) aim \(slot.workoutExercise.rirTarget.map(String.init) ?? "?") "
            + (slot.code?.rawValue ?? "nil")
    }

    static func describe(_ plan: BuildSlotPlan) -> String {
        "\(plan.sets)×\(plan.reps.map(String.init) ?? "?")@\(pounds(plan.load)) aim \(plan.rirTarget) \(plan.reason.code.rawValue)"
    }

    static func describe(_ exposure: BuildExposure) -> String {
        let reps = exposure.done.map { String($0.reps ?? $0.plannedReps ?? 0) }.joined(separator: ",")
        return "\(exposure.plannedSets)×\(exposure.repTarget.map(String.init) ?? "?")@\(pounds(exposure.plannedLoad)) did \(reps)@\(pounds(exposure.load))"
    }
}
