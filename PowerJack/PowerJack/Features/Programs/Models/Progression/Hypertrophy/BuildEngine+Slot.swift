//
//  BuildEngine+Slot.swift
//  PowerJack
//
//  One exercise's plan: pain (L1), returns (L2), deloads (L3), load and reps (L5) and block re-baselines.
//

import Foundation

//
// Pain (L1)
//
extension BuildEngine {
    /// The plan pain decides on its own, or nil when the slot is free to progress (PAIN-01, PAIN-02).
    static func painPlan(_ context: BuildContext, _ index: Int) -> BuildSlotPlan? {
        guard let exposure = context.latestDone(index) else { return nil }
        let exercise = context.slots[index].exercise
        let state = context.states[index]
        let reps = exposure.repTarget ?? exposure.repsDone
        let load = exercise.repsOnly ? nil : exposure.load
        guard let pain = exposure.pain else {
            // Only a pain tap releases a hold, so an exposure left unrated keeps the slot where it is (PAIN-03).
            guard state.painHold else { return nil }
            let held = state.previousPain ?? BuildRules.holdAt
            return BuildSlotPlan(sets: exposure.plannedSets, reps: reps, load: load, rirTarget: 0, reason: .painHold(held))
        }

        if pain.rawValue >= BuildRules.checkInAt.rawValue {
            let cut = lighter(load: load, reps: reps, pct: BuildRules.severeCutPct)
            let lasting = pain == .extreme || (state.previousPain?.rawValue ?? 0) >= BuildRules.checkInAt.rawValue
            return BuildSlotPlan(
                sets: scaled(exposure.plannedSets, by: BuildRules.severeSetFactor),
                reps: cut.reps,
                load: cut.load,
                rirTarget: 0,
                reason: .painCheckIn(pain, advice: lasting),
                checkInPain: pain
            )
        }
        guard state.painHold else { return nil }
        if state.painStreak >= BuildRules.streakToReduce, state.painStreak.isMultiple(of: BuildRules.streakToReduce) {
            let cut = lighter(load: load, reps: reps, pct: BuildRules.reducePct)
            return BuildSlotPlan(sets: exposure.plannedSets, reps: cut.reps, load: cut.load, rirTarget: 0, reason: .painReduce)
        }
        return BuildSlotPlan(sets: exposure.plannedSets, reps: reps, load: load, rirTarget: 0, reason: .painHold(pain))
    }

    /// Settles a held slot, or records the limits pain puts on the layers below (PAIN-01, PAIN-03).
    static func painLayer(_ context: BuildContext, _ index: Int, _ draft: inout Draft) {
        if let plan = painPlan(context, index) {
            draft.plan = plan
            draft.failureBlocked = true
            return
        }
        guard let exposure = context.latestDone(index) else { return }
        let state = context.states[index]
        if exposure.pain == nil, !state.painHold {
            draft.caps.smallStep = true
            draft.caps.noJump = true
            draft.caps.noRamp = true
        }
        if state.painRose {
            draft.caps.noIncrease = true
            draft.caps.noRamp = true
        }
        if state.inPostHold {
            draft.caps.noJump = true
            draft.caps.noRamp = true
        }
        // Sets a severe cut took come back one per exposure once the hold clears (PAIN-02), after an exposure with
        // a pain tap: an unrated one never gains a set (ENG-02).
        if state.exposuresSinceRelease != nil,
           let target = state.setsBeforePainCut,
           exposure.plannedSets < target,
           exposure.pain != nil,
           !draft.caps.noIncrease {
            let exercise = context.slots[index].exercise
            draft.plan = BuildSlotPlan(
                sets: exposure.plannedSets + 1,
                reps: exposure.repTarget ?? exposure.repsDone,
                load: exercise.repsOnly ? nil : exposure.load,
                rirTarget: 0,
                reason: .painSetBack
            )
            draft.addedSet = true
        }
    }
}

//
// Load and reps (L5)
//
extension BuildEngine {
    static func progress(_ context: BuildContext, _ index: Int, _ draft: Draft, week: BuildWeek) -> BuildSlotPlan {
        guard let exposure = context.latestDone(index) else { return repeatPlan(context, index) }
        let exercise = context.slots[index].exercise
        let caps = draft.caps
        let reading = context.reading(index, exposure)
        let current = exposure.repTarget ?? exposure.repsDone ?? exercise.minReps
        let load = exercise.repsOnly ? nil : exposure.load
        let step = Step(
            exposure: exposure,
            exercise: exercise,
            reading: reading,
            current: current,
            load: load,
            aim: aim(for: week, exercise: exercise, reps: current, failureBlocked: draft.failureBlocked),
            smallStep: caps.smallStep
        )

        var plan: BuildSlotPlan
        if context.isCalibration(index, exposure), let calibrated = calibrate(context, index, exposure, aim: step.aim) {
            plan = calibrated
        } else if context.states[index].missStreak >= BuildRules.missStreakForBackoff, !caps.noBackoff {
            plan = backOff(step)
        } else if exposure.missed {
            plan = step.plan(reps: current, load: load, reason: .holdMiss)
        } else if reading.kind == .harder {
            plan = step.plan(reps: current, load: load, reason: .holdHard(rir: reading.rir, aim: reading.target))
        } else if reading.kind == .unrated {
            plan = unratedStep(context, index, step)
        } else if !exercise.repsOnly,
                  reading.gap >= BuildRules.easyJumpByRirGap,
                  reading.gap > reading.band,
                  !caps.noJump {
            plan = easyJump(context, index, step)
        } else if isReady(step) {
            plan = loadStep(step)
        } else {
            plan = addReps(step)
        }

        // Rising pain blocks every increase (PAIN-01).
        if caps.noIncrease, (plan.load ?? 0) > (load ?? 0) || (plan.reps ?? 0) > current || plan.sets > exposure.plannedSets {
            plan = step.plan(reps: current, load: load, reason: .painRising)
        }
        // The first block after a return keeps loads near the return load; reps climb instead of a raise past
        // it (BLK-07). A hold at the lifter's own heavier load stays a hold.
        if let cap = caps.loadCap, let planned = plan.load, planned > cap, let load, planned > load {
            let reps = min(max(current, (exposure.repsDone ?? current) + BuildRules.repsPerStep), extendedCeiling(exercise))
            plan = step.plan(reps: reps, load: load, reason: .returnCap)
        }
        return plan
    }

    /// What every L5 step reads.
    struct Step {
        let exposure: BuildExposure
        let exercise: BuildExercise
        let reading: EffortReading
        /// This week's rep target, or the fewest reps done when there was none.
        let current: Int
        /// Nil for bodyweight exercises.
        let load: Int?
        /// Next week's aim, for rep targets after a load change (LOAD-05).
        let aim: Int
        let smallStep: Bool

        var repsDone: Int { exposure.repsDone ?? current }
        var ceiling: Int { BuildEngine.repCeiling(exercise, repTarget: current) }

        func plan(reps: Int?, load: Int?, reason: BuildReason) -> BuildSlotPlan {
            BuildSlotPlan(sets: exposure.plannedSets, reps: reps, load: load, rirTarget: 0, reason: reason)
        }

        /// LOAD-05's rep target at a new load, clamped to the exercise's range.
        func reps(at newLoad: Int) -> Int {
            let predicted = exposure.estimatedMax?.reps(atTenths: newLoad, leaving: aim) ?? exercise.minReps
            return min(max(predicted, exercise.minReps), exercise.maxReps)
        }
    }

    /// Every set hit the top of the range with at least the planned reps left (LOAD-03). A light lift whose
    /// range LOAD-04 extended re-checks the step every week the reps are made.
    static func isReady(_ step: Step) -> Bool {
        guard !step.exercise.repsOnly, step.reading.gap >= 0 else { return false }
        if step.current > step.exercise.maxReps { return true }
        return step.exposure.done.allSatisfy { ($0.reps ?? $0.plannedReps ?? 0) >= step.ceiling }
    }

    /// Same load, more reps (LOAD-02, LOAD-09).
    static func addReps(_ step: Step) -> BuildSlotPlan {
        if step.exercise.repsOnly, step.current >= BuildRules.bodyweightRepCap {
            return step.plan(reps: BuildRules.bodyweightRepCap, load: nil, reason: .repCap)
        }
        let size = step.reading.kind == .easier && !step.smallStep ? BuildRules.repsPerStepEasy : BuildRules.repsPerStep
        let next = min(max(step.current, step.repsDone + size, step.exercise.minReps), step.ceiling)
        guard next > step.current else {
            return step.plan(
                reps: step.current,
                load: step.load,
                reason: .holdAtTop(reps: step.current, rir: step.reading.rir, aim: step.reading.target)
            )
        }
        return step.plan(
            reps: next,
            load: step.load,
            reason: .repsUp(by: next - step.current, rir: step.reading.rir, aim: step.reading.target)
        )
    }

    /// One 5 lb step when the reps after it still reach the bottom of the range; otherwise a light lift's reps
    /// climb past the range first (LOAD-04). A slot at the heaviest load a set can log climbs the same way.
    static func loadStep(_ step: Step) -> BuildSlotPlan {
        guard let load = step.load else { return addReps(step) }
        let newLoad = load + BuildRules.stepTenths
        let atMax = newLoad > BuildRules.maxLoad
        let predicted = step.exposure.estimatedMax?.reps(atTenths: newLoad, leaving: step.aim) ?? step.exercise.minReps
        if predicted >= step.exercise.minReps, !atMax {
            return step.plan(
                reps: step.reps(at: newLoad),
                load: newLoad,
                reason: .loadUp(by: BuildRules.stepTenths, reps: step.repsDone, rir: step.reading.rir)
            )
        }
        let extended = extendedCeiling(step.exercise)
        guard step.current < extended else {
            let reason: BuildReason = atMax ? .holdAtMaxLoad(reps: step.current) : .stepTooLarge(reps: step.current)
            return step.plan(reps: step.current, load: load, reason: reason)
        }
        let size = step.reading.kind == .easier && !step.smallStep ? BuildRules.repsPerStepEasy : BuildRules.repsPerStep
        let next = min(max(step.current, step.repsDone + size), extended)
        let reason: BuildReason = atMax ? .repsAtMaxLoad(next) : .repsBeforeStep(next, jumpPct: jumpPct(load))
        return step.plan(reps: next, load: load, reason: reason)
    }

    /// Far too easy: one step, or after two such weeks a jump sized by the estimated max, at most 20% (LOAD-06).
    static func easyJump(_ context: BuildContext, _ index: Int, _ step: Step) -> BuildSlotPlan {
        guard let load = step.load else { return addReps(step) }
        let maxLoad = min(load + max(BuildRules.stepTenths, floorToStep(Double(load) * BuildRules.easyJumpMaxPct / 100)), BuildRules.maxLoad)
        let previousWasEasy = context.doneExposure(index, before: step.exposure).map { previous in
            let reading = context.reading(index, previous)
            return reading.tapped && !previous.missed
                && reading.gap >= BuildRules.easyJumpByRirGap && reading.gap > reading.band
        } ?? false
        let stepFitsCap = Double(BuildRules.stepTenths) <= Double(load) * BuildRules.easyJumpMaxPct / 100

        if previousWasEasy, stepFitsCap, step.reading.rir <= 4, load + BuildRules.stepTenths <= maxLoad,
           let estimatedMax = step.exposure.estimatedMax, !estimatedMax.isLowerBound {
            var jumped = load + BuildRules.stepTenths
            var candidate = jumped + BuildRules.stepTenths
            while candidate <= maxLoad,
                  let reps = estimatedMax.reps(atTenths: candidate, leaving: step.aim),
                  reps >= step.repsDone {
                jumped = candidate
                candidate += BuildRules.stepTenths
            }
            return step.plan(
                reps: step.reps(at: jumped),
                load: jumped,
                reason: .easyStep(by: jumped - load, rir: step.reading.rir, aim: step.reading.target, twice: true)
            )
        }
        var plan = loadStep(step)
        if (plan.load ?? 0) > load {
            plan.reason = .easyStep(by: BuildRules.stepTenths, rir: step.reading.rir, aim: step.reading.target, twice: false)
        }
        return plan
    }

    /// Without a tapped rating, a rep at a time, and 5 lb only after two weeks in a row at the top (ENG-02).
    static func unratedStep(_ context: BuildContext, _ index: Int, _ step: Step) -> BuildSlotPlan {
        let exercise = step.exercise
        if exercise.repsOnly {
            guard step.current < BuildRules.bodyweightRepCap else {
                return step.plan(reps: BuildRules.bodyweightRepCap, load: nil, reason: .repCap)
            }
            let next = min(max(step.current, step.repsDone + BuildRules.repsPerStep), BuildRules.bodyweightRepCap)
            return step.plan(reps: next, load: nil, reason: .unratedRep)
        }
        guard atTop(step.exposure, exercise) else {
            let next = min(max(step.current, step.repsDone + BuildRules.repsPerStep, exercise.minReps), step.ceiling)
            return step.plan(reps: next, load: step.load, reason: next > step.current ? .unratedRep : .unratedHold)
        }
        let previousAtTop = context.doneExposure(index, before: step.exposure).map { atTop($0, exercise) } ?? false
        guard previousAtTop, let load = step.load else {
            return step.plan(reps: step.current, load: step.load, reason: .unratedHold)
        }
        let newLoad = load + BuildRules.stepTenths
        guard newLoad <= BuildRules.maxLoad else {
            let next = min(step.current + BuildRules.repsPerStep, extendedCeiling(exercise))
            return step.plan(reps: next, load: load, reason: next > step.current ? .repsAtMaxLoad(next) : .holdAtMaxLoad(reps: next))
        }
        return step.plan(reps: step.reps(at: newLoad), load: newLoad, reason: .unratedLoad)
    }

    /// Two misses in a row: 5% lighter, at least one step, and reps reset for the new load (LOAD-07).
    static func backOff(_ step: Step) -> BuildSlotPlan {
        let exercise = step.exercise
        guard let load = step.load else {
            return step.plan(reps: max(step.repsDone, exercise.minReps), load: nil, reason: .loadDown(by: nil))
        }
        // On a light lift one step is too big a cut, so the reps come down instead.
        if Double(BuildRules.stepTenths) > Double(load) * BuildRules.maxJumpPct / 100, step.repsDone >= exercise.minReps {
            return step.plan(reps: step.repsDone, load: load, reason: .loadDown(by: nil))
        }
        guard let lighter = cut(load, pct: BuildRules.backoffPct) else {
            return step.plan(reps: step.current, load: load, reason: .holdMiss)
        }
        return step.plan(reps: step.reps(at: lighter), load: lighter, reason: .loadDown(by: load - lighter))
    }

    /// After a calibration exposure, sets the load from what was lifted, rising at most 25% (START-05).
    /// Returns nil when calibration ends unrated, so the slot takes ENG-02's small steps.
    static func calibrate(_ context: BuildContext, _ index: Int, _ exposure: BuildExposure, aim: Int) -> BuildSlotPlan? {
        let exercise = context.slots[index].exercise
        let reps = exposure.repTarget ?? exposure.repsDone
        let load = exercise.repsOnly ? nil : exposure.load
        func plan(_ reps: Int?, _ load: Int?, _ reason: BuildReason) -> BuildSlotPlan {
            BuildSlotPlan(sets: exposure.plannedSets, reps: reps, load: load, rirTarget: 0, reason: reason)
        }

        guard let rir = exposure.tappedRIR else {
            // An unrated calibration gets one more try, once.
            if let previous = context.doneExposure(index, before: exposure), context.isCalibration(index, previous) {
                return nil
            }
            return plan(reps, load, .calibrate(repsOnly: exercise.repsOnly))
        }
        let repsDone = exposure.repsDone ?? exercise.minReps
        if exercise.repsOnly {
            let capacity = (exposure.done.last?.reps ?? repsDone) + rir
            return plan(min(max(capacity - aim, exercise.minReps), BuildRules.bodyweightRepCap), nil, .calibrated)
        }
        guard let load, let estimatedMax = exposure.estimatedMax else {
            return plan(min(max(repsDone, exercise.minReps), exercise.maxReps), load, .calibrated)
        }
        let target = min(max(repsDone, exercise.minReps), exercise.maxReps)
        let solved = estimatedMax.loadTenths(forReps: target, leaving: aim).map { max(BuildRules.stepTenths, floorToStep($0)) } ?? load
        let newLoad = min(solved, load + floorToStep(Double(load) * BuildRules.calibrationMaxJumpPct / 100), BuildRules.maxLoad)
        let newReps = estimatedMax.reps(atTenths: newLoad, leaving: aim) ?? target
        return plan(min(max(newReps, exercise.minReps), exercise.maxReps), newLoad, .calibrated)
    }

    /// Every completed set reached the slot's rep ceiling.
    static func atTop(_ exposure: BuildExposure, _ exercise: BuildExercise) -> Bool {
        let ceiling = repCeiling(exercise, repTarget: exposure.repTarget)
        return exposure.isDone && exposure.done.allSatisfy { ($0.reps ?? $0.plannedReps ?? 0) >= ceiling }
    }
}

//
// Deloads, returns and new blocks
//
extension BuildEngine {
    /// Half the sets at 90% of the build load, same reps. Where 90% rounds to more than a 20% cut, the load
    /// stays and reps drop to 60% instead (BLK-04).
    static func deloadPlan(_ context: BuildContext, _ index: Int, reactive: Bool) -> BuildSlotPlan {
        let exercise = context.slots[index].exercise
        guard let build = context.latest(index, in: .build) ?? context.latest(index) else {
            return repeatPlan(context, index)
        }
        let reps = build.repTarget ?? build.repsDone
        var load = exercise.repsOnly ? nil : build.load
        var deloadReps = reps
        let fewerReps = { (reps: Int) in max(1, Int((Double(reps) * BuildRules.deloadRepFactor).rounded())) }
        if let buildLoad = load {
            let lighter = floorToStep(Double(buildLoad) * BuildRules.deloadLoadFactor)
            if lighter <= 0 || Double(buildLoad - lighter) / Double(buildLoad) * 100 > BuildRules.deloadMaxCutPct {
                deloadReps = reps.map(fewerReps)
            } else {
                load = lighter
            }
        } else {
            deloadReps = reps.map(fewerReps)
        }
        return BuildSlotPlan(
            sets: scaled(build.plannedSets, by: BuildRules.deloadSetFactor),
            reps: deloadReps,
            load: load,
            rirTarget: BuildRules.deloadRIR,
            reason: .deload(reactive: reactive)
        )
    }

    /// Return weeks after a break: lighter loads, and half the sets in the first (BLK-07). Loads come from the last
    /// build week before the break, or from the return weeks when another break cut them short.
    static func returnPlan(_ context: BuildContext, _ index: Int, band: Int, week: Int, fromReturn: Bool = false) -> BuildSlotPlan {
        let exercise = context.slots[index].exercise
        guard let before = context.latest(index, in: .build) ?? context.latest(index) else {
            return repeatPlan(context, index)
        }
        let reference = fromReturn ? context.latest(index, in: .return) ?? before : before
        let bandIndex = min(max(band, 1), 3) - 1
        let keep = (100 - BuildRules.returnLoadCutPct[bandIndex]) / 100
        return BuildSlotPlan(
            sets: week == 1 ? scaled(before.plannedSets, by: BuildRules.returnSetFactor[bandIndex]) : before.plannedSets,
            reps: reference.repTarget ?? reference.repsDone,
            load: exercise.repsOnly ? nil : reference.load.map { max(BuildRules.stepTenths, floorToStep(Double($0) * keep)) },
            rirTarget: BuildRules.startRIR,
            reason: .returnWeek(week)
        )
    }

    /// Block week 1 keeps the last build load and resets reps for 3 reps left (BLK-06).
    static func rebaseline(_ context: BuildContext, _ index: Int, afterReturn: Bool, caps: Caps) -> BuildSlotPlan {
        let exercise = context.slots[index].exercise
        let kind: WeekKind = afterReturn ? .return : .build
        guard let base = context.latest(index, in: kind) ?? context.latest(index) else {
            return repeatPlan(context, index)
        }
        let current = base.repTarget ?? base.repsDone ?? exercise.minReps
        // Reps leave week 1's entry of the effort ramp, before any high-rep or bodyweight offset to the aim.
        let target = BuildRules.rirByWeek[0]
        // Return week 1's half sets were part of the way back; the block holds the sets from before the break (VOL-05),
        // unless pain is rising, which blocks every increase (PAIN-01).
        let preBreak = afterReturn && !caps.noIncrease ? context.latest(index, in: .build)?.plannedSets ?? 0 : 0
        let sets = max(base.plannedSets, preBreak)
        // A calibration from before return weeks never sizes the block after them; their plan does (BLK-07).
        if let latest = context.latestDone(index), context.isCalibration(index, latest),
           !afterReturn || context.weeks[latest.weekIndex].kind == .return,
           var calibrated = calibrate(context, index, latest, aim: target) {
            calibrated.sets = afterReturn ? max(calibrated.sets, sets) : calibrated.sets
            return calibrated
        }
        let load = exercise.repsOnly ? nil : base.load
        func plan(_ reps: Int, _ load: Int?) -> BuildSlotPlan {
            BuildSlotPlan(sets: sets, reps: reps, load: load, rirTarget: 0, reason: .blockRebase)
        }
        // A hold that ended this week resumes from its last exposure, never the load from before the pain (PAIN-03).
        if context.states[index].exposuresSinceRelease == 0, let latest = context.latestDone(index) {
            return plan(latest.repTarget ?? latest.repsDone ?? current, exercise.repsOnly ? nil : latest.load)
        }
        // Rising pain resumes from where it is (PAIN-01).
        guard !caps.noIncrease else { return plan(current, load) }
        // Only a rating of 0 to 4 sets a baseline; 5+ is a floor (RIR-05).
        guard let rated = context.slots[index].history.last(where: {
            context.weeks[$0.weekIndex].kind == kind && $0.isDone && ($0.tappedRIR ?? 5) <= 4
        }) else {
            return plan(current, load)
        }
        if exercise.repsOnly {
            let capacity = (rated.done.last?.reps ?? current) + (rated.tappedRIR ?? 0)
            return plan(min(max(capacity - target, exercise.minReps), BuildRules.bodyweightRepCap), nil)
        }
        guard
            let load,
            let estimatedMax = rated.estimatedMax,
            let toFailure = estimatedMax.repsToFailure(atTenths: load),
            let predicted = estimatedMax.reps(atTenths: load, leaving: target)
        else {
            return plan(current, load)
        }
        let ceiling = repCeiling(exercise, repTarget: current)
        if predicted > ceiling {
            // Past the top: LOAD-04 decides between a step and longer sets.
            let stepped = load + BuildRules.stepTenths
            if stepped <= BuildRules.maxLoad, let reps = estimatedMax.reps(atTenths: stepped, leaving: target), reps >= exercise.minReps {
                return plan(min(reps, exercise.maxReps), stepped)
            }
            return plan(min(predicted, extendedCeiling(exercise)), load)
        }
        if predicted < exercise.minReps {
            // Keep the load at the bottom of the range while that still leaves a rep; else drop one step.
            if toFailure - Double(exercise.minReps) >= 1 || load - BuildRules.stepTenths < BuildRules.stepTenths {
                return plan(exercise.minReps, load)
            }
            let lighter = load - BuildRules.stepTenths
            let reps = estimatedMax.reps(atTenths: lighter, leaving: target) ?? exercise.minReps
            return plan(min(max(reps, exercise.minReps), ceiling), lighter)
        }
        return plan(predicted, load)
    }

    /// The first block after return weeks caps loads at the last return load plus 10%, at least 5 lb (BLK-07).
    static func returnLoadCap(_ context: BuildContext, _ index: Int) -> Int? {
        let block = context.blocks[context.lastIndex]
        guard block > 0 else { return nil }
        let returnWeeks = context.weekIndexes(inBlock: block - 1)
        guard
            !returnWeeks.isEmpty,
            returnWeeks.allSatisfy({ context.weeks[$0].kind == .return }),
            let last = context.slots[index].history.last(where: { returnWeeks.contains($0.weekIndex) }),
            let load = last.load
        else {
            return nil
        }
        return load + max(BuildRules.stepTenths, floorToStep(Double(load) * BuildRules.firstBlockLoadCapPct / 100))
    }
}

//
// Rounding
//
extension BuildEngine {
    /// Rounds a load down to whole 5 lb steps.
    static func floorToStep(_ tenths: Double) -> Int {
        Int((tenths / Double(BuildRules.stepTenths)).rounded(.down)) * BuildRules.stepTenths
    }

    /// `load` minus `pct`, rounded down to whole steps but at least one. Nil when that leaves under one step.
    static func cut(_ load: Int, pct: Double) -> Int? {
        let lighter = load - max(BuildRules.stepTenths, floorToStep(Double(load) * pct / 100))
        return lighter >= BuildRules.stepTenths ? lighter : nil
    }

    /// Cuts the load by `pct`, or the reps when there's no load to cut (PAIN-01, PAIN-02).
    static func lighter(load: Int?, reps: Int?, pct: Double) -> (load: Int?, reps: Int?) {
        if let load, let cutLoad = cut(load, pct: pct) {
            return (cutLoad, reps)
        }
        return (load, reps.map { max(1, $0 - max(1, Int(Double($0) * pct / 100))) })
    }

    /// Scales a set count, rounding up and keeping at least one set.
    static func scaled(_ sets: Int, by factor: Double) -> Int {
        max(1, Int((Double(sets) * factor).rounded(.up)))
    }

    /// One 5 lb step as a percent of `load`.
    static func jumpPct(_ load: Int) -> Int {
        Int((Double(BuildRules.stepTenths) / Double(max(load, 1)) * 100).rounded())
    }
}
