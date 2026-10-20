//
//  StrengthPrescriber.swift
//  PowerJack
//
//  Plans one slot of the next strength week (the weekly loop, step 5): deload, return, micro-deload,
//  new block or weekly progression, then the zone caps, the e1RM ceiling and rounding to real plates.
//

import Foundation

/// One slot of the week being planned, with everything the rules read about it.
struct StrengthSlotContext {
    var key: String
    var role: StrengthRole
    var zone: StrengthZone?
    var curve: StrengthCurve
    /// `nil` for bodyweight exercises, which progress by reps only (1.3).
    var grid: LoadGrid?
    var needsSpotter: Bool
    /// The exercise's own rep range, which accessories progress within.
    var repRange: ClosedRange<Int>
    /// This slot's earlier sessions in the program, newest first.
    var history: [StrengthSession]
    /// For a close variant: its parent's record and the variant's share of it (2.3).
    var parent: (record: StrengthLiftRecord, ratio: Double)?
}

enum StrengthPrescriber {
    static func plan(
        _ slot: StrengthSlotContext,
        record: StrengthLiftRecord,
        clock: StrengthClock,
        at now: Date
    ) -> StrengthSlotPlan {
        if slot.role == .accessory || slot.grid == nil {
            var plan = accessoryPlan(slot, deload: clock.upcoming == .deload)
            if slot.grid == nil { plan.sets = plan.sets.map(\.repsOnly) }
            return plan
        }
        var plan = loadedPlan(slot, record: record, clock: clock, at: now)
        plan.warmups = warmups(for: plan, slot: slot, record: record)
        return plan
    }

    // MARK: Targets

    /// R and I for the week: module 5's slot targets, block type and RIR wave (9.2), a stall's rep shift
    /// (11.5), the zone caps and spotter rule (5.2), and the pain RIR floor, which comes before scaling (fix 3).
    static func targets(
        _ slot: StrengthSlotContext,
        record: StrengthLiftRecord,
        clock: StrengthClock
    ) -> (reps: Int, rir: Int) {
        var reps: Int
        var rir = 2
        if slot.role == .secondary {
            reps = 6
        } else {
            let advanced = clock.experience == .advanced
            let base = slot.zone == .moderate ? (advanced ? 5 : 6) : (advanced ? 3 : 4)
            reps = base
            if clock.blockType == .b { reps -= StrengthRules.blockBRepShift }
            if slot.zone != .moderate, record.repShiftActive { reps -= StrengthRules.stallRepShift }
            reps = max(reps, min(base, StrengthRules.repsMinNormal))
            let week = min(max(clock.blockWeek, 1), StrengthRules.rirWave.count)
            rir += StrengthRules.rirWave[week - 1]
        }
        let cap = slot.role == .secondary ? StrengthRules.secondaryRepsToFailureMax : StrengthRules.primaryRepsToFailureMax
        rir = max(StrengthRules.rirMin, min(rir, cap - reps))
        if slot.needsSpotter, reps + rir <= StrengthRules.spotterRepsToFailure {
            // No spotter check is built yet, so near-max squat and bench sets are planned as if it said No.
            rir = max(rir, StrengthRules.spotterRepsToFailure + 1 - reps, 2)
        }
        if record.pain.rirFloor { rir = max(rir, StrengthRules.painReturnRIR) }
        return (reps, rir)
    }

    // MARK: Loaded slots

    private static func loadedPlan(
        _ slot: StrengthSlotContext,
        record: StrengthLiftRecord,
        clock: StrengthClock,
        at now: Date
    ) -> StrengthSlotPlan {
        let (reps, rir) = targets(slot, record: record, clock: clock)
        // Weeks the exercise ran as an accessory, before a swap made it a priority lift, set no load to build on.
        let history = slot.history.filter { $0.plan.kind != .accessory }
        // The last real week to build on: one that had a load, so a week skipped before it was prepared is passed over.
        let lastNormal = history.first { ($0.plan.kind == .normal || $0.plan.kind == .calibration) && $0.hasLoad }
        // A slot with no load yet, such as one whose first week was skipped before it started, plans as a new
        // lift does: from the lift's e1RM when it has one (2.6), otherwise by feel (2.2).
        guard let last = history.first, history.contains(where: \.hasLoad) else {
            let first = firstPlan(slot, record: record, reps: reps, rir: rir, at: now)
            // A new program that starts on a deload week deloads from the e1RM plan. A lift with no e1RM
            // calibrates by feel instead, so its next week has a load to build on.
            guard clock.upcoming == .deload, first.loadKg != nil else { return first }
            return deload(first, loggedLoadKg: nil, grid: slot.grid)
        }
        let sets = setCount(from: lastNormal ?? last, step: clock.startsBlock ? record.stepThisWeek : nil)

        if clock.upcoming == .deload {
            let source = lastNormal ?? last
            return deload(source.plan, loggedLoadKg: source.ratedSet?.loadKg, grid: slot.grid)
        }
        if last.plan.kind == .returnWeek1, last.trained {
            return returnWeek2(after: last, preBreak: lastNormal, slot: slot, record: record, clock: clock, at: now)
        }
        if record.flagged, last.plan.kind == .normal {
            return microDeload(from: last, slot: slot)
        }
        if clock.startsBlock, !record.isCalibrating {
            if let lastNormal {
                return newBlock(from: lastNormal, slot: slot, record: record, clock: clock, reps: reps, rir: rir, sets: sets, at: now)
            }
            // No normal week before the deload to restart from, so the block starts from e1RM as a new lift does (2.6, 9.4).
            if record.e1rmKg != nil {
                return firstPlan(slot, record: record, reps: reps, rir: rir, at: now)
            }
        }
        return progress(
            slot, record: record, clock: clock, last: last, lastNormal: lastNormal,
            reps: reps, rir: rir, sets: sets, at: now
        )
    }

    /// Normal weeks keep last week's sets; a stall step adds or removes one per slot (8.4, 11.4, 11.5).
    private static func setCount(from session: StrengthSession, step: StallStep?) -> Int {
        let sets = session.plan.kind == .calibration || session.plan.kind == .normal
            ? session.plan.sets.count
            : StrengthRules.slotSets
        switch step {
        case .sets: return min(sets + 1, StrengthRules.maxSlotSets)
        case .fewerSets: return max(sets - 1, StrengthRules.minSlotSets)
        default: return sets
        }
    }

    /// A slot's first week: loads from the lift's e1RM when it has one (2.6), from its parent for a close
    /// variant (2.3), otherwise picked by feel to the RIR target (2.2).
    private static func firstPlan(
        _ slot: StrengthSlotContext,
        record: StrengthLiftRecord,
        reps: Int,
        rir: Int,
        at now: Date
    ) -> StrengthSlotPlan {
        let kind: StrengthSlotKind = record.isCalibrating ? .calibration : .normal
        if let e1rm = record.e1rmKg, let grid = slot.grid {
            let intended = e1rm * slot.curve.share(repsToFailure: reps + rir)
            return make(kind, reps: reps, rir: rir, sets: StrengthRules.slotSets, intended: intended, load: grid.down(intended), rules: ["2.6", "5.1"])
        }
        if let parent = slot.parent, let parentE1rm = parent.record.e1rmKg,
           parent.record.confidence(at: now) >= StrengthRules.confidenceMin, let grid = slot.grid {
            let variantRIR = rir + StrengthRules.variantRIRAdd
            let intended = parent.ratio * parentE1rm * StrengthRules.variantFactor
                * slot.curve.share(repsToFailure: reps + variantRIR)
            return make(.calibration, reps: reps, rir: variantRIR, sets: StrengthRules.slotSets, intended: intended, load: grid.down(intended), rules: ["2.3"])
        }
        return make(.calibration, reps: reps, rir: rir, sets: StrengthRules.slotSets, intended: nil, load: nil, rules: ["2.2"])
    }

    /// 10.6: half the sets, 90% of the load, 2 more reps in reserve (at least 3), same reps.
    static func deload(_ source: StrengthSlotPlan, loggedLoadKg: Double?, grid: LoadGrid?) -> StrengthSlotPlan {
        let intended = lighterBase(intended: source.intendedKg, bar: source.loadKg ?? loggedLoadKg).map { $0 * StrengthRules.deloadLoadFactor }
        let sets = max(1, Int(Double(source.sets.count) * StrengthRules.deloadSetFactor))
        var plan = make(
            .deload,
            reps: source.reps,
            rir: max(source.rir + StrengthRules.deloadRIRAdd, StrengthRules.deloadRIRMin),
            sets: sets,
            intended: intended,
            load: intended.flatMap { grid?.nearest($0) },
            rules: ["10.6"]
        )
        plan.repOffset = source.repOffset
        plan.sets = StrengthSlotPlan.uniform(sets, reps: plan.targetReps, loadKg: plan.loadKg)
        return plan
    }

    /// 10.3: one light week for a flagged lift: 5% lighter, a set fewer (at least 2), same reps and RIR.
    private static func microDeload(from last: StrengthSession, slot: StrengthSlotContext) -> StrengthSlotPlan {
        let base = lighterBase(intended: last.plan.intendedKg, bar: last.plan.loadKg ?? last.ratedSet?.loadKg)
        let intended = base.map { $0 * (1 - StrengthRules.microLoadCut) }
        let sets = max(StrengthRules.microMinSets, last.plan.sets.count - StrengthRules.microSetCut)
        var plan = make(
            .microDeload,
            reps: last.plan.reps,
            rir: last.plan.rir,
            sets: sets,
            intended: intended,
            load: intended.flatMap { slot.grid?.nearest($0) },
            rules: ["10.2", "10.3"]
        )
        plan.repOffset = last.plan.repOffset
        plan.sets = StrengthSlotPlan.uniform(sets, reps: plan.targetReps, loadKg: plan.loadKg)
        return plan
    }

    /// What a lighter week cuts from: the intended load, or the bar when a cap kept the bar under it, so a
    /// deload is never heavier than the week it follows (10.3, 10.6).
    private static func lighterBase(intended: Double?, bar: Double?) -> Double? {
        [intended, bar].compactMap { $0 }.min()
    }

    /// 12.2-12.3: week 2 back from a break. A missed rep or Δ ≤ −2 in week 1 repeats it.
    private static func returnWeek2(
        after last: StrengthSession,
        preBreak: StrengthSession?,
        slot: StrengthSlotContext,
        record: StrengthLiftRecord,
        clock: StrengthClock,
        at now: Date
    ) -> StrengthSlotPlan {
        var plan = last.plan
        plan.kind = .returnWeek2
        if !last.missedSets.isEmpty || (last.delta ?? 0) <= StrengthRules.flagDelta {
            plan.rules = ["12.3"]
            // The stored plan holds any set the lifter added, which had no target: repeat it evenly, on the grid as
            // it is now in case the unit or step changed (1.4).
            let load = plan.loadKg.map { slot.grid?.down($0 + LoadGrid.storedTolerance) ?? $0 }
            plan.sets = StrengthSlotPlan.uniform(plan.sets.count, reps: plan.targetReps, loadKg: load)
            return plan
        }
        let cut: Double
        let rirAdd: Int
        switch last.plan.returnBand {
        case 2: (cut, rirAdd) = (0.05, 0)
        case 3: (cut, rirAdd) = (0.10, 1)
        default:
            // Short breaks and recalibrated lifts go straight back to weekly progression.
            let (reps, rir) = targets(slot, record: record, clock: clock)
            return progress(
                slot, record: record, clock: clock, last: last, lastNormal: preBreak,
                reps: reps, rir: rir, sets: preBreak?.plan.sets.count ?? StrengthRules.slotSets, at: now
            )
        }
        let (reps, rir) = targets(slot, record: record, clock: clock)
        let base = preBreak?.plan.intendedKg ?? last.plan.intendedKg
        let intended = base.map { $0 * (1 - cut) }
        plan = make(
            .returnWeek2,
            reps: reps,
            rir: rir + rirAdd,
            sets: preBreak?.plan.sets.count ?? StrengthRules.slotSets,
            intended: intended,
            load: intended.flatMap { slot.grid?.nearest($0) },
            rules: ["12.2"]
        )
        plan.returnBand = last.plan.returnBand
        return plan
    }

    /// 9.4: block week 1 restarts from e1RM, capped at the last pre-deload load scaled to the new targets.
    private static func newBlock(
        from lastNormal: StrengthSession,
        slot: StrengthSlotContext,
        record: StrengthLiftRecord,
        clock: StrengthClock,
        reps: Int,
        rir: Int,
        sets: Int,
        at now: Date
    ) -> StrengthSlotPlan {
        guard let grid = slot.grid, let previous = lastNormal.plan.intendedKg ?? lastNormal.ratedSet?.loadKg else {
            return make(.normal, reps: reps, rir: rir, sets: sets, intended: nil, load: nil, rules: ["9.4"])
        }
        let scaled = previous * slot.curve.scale(from: lastNormal.plan.repsToFailure, to: reps + rir)
        var intended = scaled * StrengthRules.newBlockFactor
        if let e1rm = record.e1rmKg, record.confidence(at: now) >= StrengthRules.confidenceMin {
            let fromE1rm = e1rm * slot.curve.share(repsToFailure: reps + rir) * StrengthRules.newBlockFactor
            intended = min(fromE1rm, scaled * (1 + capUp(clock: clock, record: record, lastKind: .normal)))
        }
        var rules = ["9.4"]
        switch record.stepThisWeek {
        case .reset:
            intended *= 1 - StrengthRules.resetCut
            rules.append("11.5")
        case .sets:
            // Load holds in a week that adds a set (principle 5).
            intended = min(intended, scaled)
            rules.append("11.5")
        case .repZone:
            rules.append("11.5")
        case .fewerSets:
            rules.append("11.4")
        case nil:
            break
        }
        return make(.normal, reps: reps, rir: rir, sets: sets, intended: intended, load: grid.nearest(intended), rules: rules)
    }

    /// Module 7: next week's load is this week's × (1 + d), with d set by Δ, the rep error on the rated set.
    private static func progress(
        _ slot: StrengthSlotContext,
        record: StrengthLiftRecord,
        clock: StrengthClock,
        last: StrengthSession,
        lastNormal: StrengthSession?,
        reps: Int,
        rir: Int,
        sets: Int,
        at now: Date
    ) -> StrengthSlotPlan {
        let kind: StrengthSlotKind = record.isCalibrating ? .calibration : .normal
        guard let grid = slot.grid else {
            return make(kind, reps: reps, rir: rir, sets: sets, intended: nil, load: nil, rules: ["1.3"])
        }
        let confident = record.confidence(at: now) >= StrengthRules.confidenceMin

        // 7.4: nothing that may feed Δ repeats the last real plan, scaled to this week's targets, d = 0.
        guard
            last.trained, !last.plan.kind.isLight, !last.isPainful,
            let delta = last.delta, let rated = last.ratedSet, let ratedLoad = rated.loadKg, ratedLoad > 0
        else {
            let source = lastNormal ?? last
            guard let base = source.plan.intendedKg ?? source.ratedSet?.loadKg else {
                // Nothing to repeat a load from: a lift with an e1RM loads from it, as in a new program (2.6).
                guard record.e1rmKg == nil else { return firstPlan(slot, record: record, reps: reps, rir: rir, at: now) }
                return make(kind, reps: reps, rir: rir, sets: sets, intended: nil, load: nil, rules: ["7.4"])
            }
            var intended = base * slot.curve.scale(from: source.plan.repsToFailure, to: reps + rir)
            var rules = ["7.4", "9.3"]
            if confident, let e1rm = record.e1rmKg {
                let ceiling = e1rm * slot.curve.share(repsToFailure: reps + rir - StrengthRules.ceilingReps)
                if intended > ceiling {
                    intended = ceiling
                    rules.append("7.6")
                }
            }
            return make(kind, reps: reps, rir: rir, sets: sets, intended: intended, load: grid.nearest(intended), rules: rules)
        }

        let capUp = capUp(clock: clock, record: record, lastKind: last.plan.kind)
        if grid.isCoarse(at: ratedLoad) || last.plan.repOffset < 0 {
            return repsMode(slot, last: last, rated: rated, ratedLoad: ratedLoad, delta: delta, clock: clock, kind: kind, reps: reps, rir: rir, sets: sets, grid: grid)
        }

        // 7.3: each rep easier than planned adds 2.5%, on target nudges up, 1-2 short holds, more cuts.
        var d: Double
        if delta >= 1 {
            d = min(StrengthRules.kRep * Double(min(delta, StrengthRules.deltaMax)), capUp)
        } else if delta == 0 {
            d = min(clock.experience == .advanced ? StrengthRules.nudgeAdvanced : StrengthRules.nudgeIntermediate, capUp)
        } else if delta >= -StrengthRules.deadbandReps {
            d = 0
        } else {
            d = max(StrengthRules.kRep * Double(delta + StrengthRules.deadbandReps), -StrengthRules.capDown)
        }
        // 7.4: under half the planned sets done means no increase.
        if Double(last.completedSets.count) < StrengthRules.minDoneShare * Double(last.plan.sets.count) {
            d = min(d, 0)
        }

        // 7.5: the base is the rated set's load if it was changed from the plan, else last week's intended load.
        let changed = rated.plannedLoadKg.map { abs($0 - ratedLoad) > 0.05 } ?? true
        let base = changed ? ratedLoad : (last.plan.intendedKg ?? ratedLoad)
        var factor = slot.curve.scale(from: last.plan.repsToFailure, to: reps + rir)
        if d < 0, factor > 1 { factor = 1 }
        let change = min(max((1 + d) * factor - 1, -StrengthRules.capDown), capUp)
        var intended = base * (1 + change)
        var rules = ["7.3"]
        if factor != 1 { rules.append("9.3") }

        // 4.5: until 3 rated sessions back the estimate, a rise is at most one step.
        if !confident, intended > base {
            intended = min(intended, base + grid.stepKilograms)
            rules.append("4.5")
        }
        // 7.6: never above e1RM × pct(R + I − 1).
        var ceilingBound = false
        if confident, let e1rm = record.e1rmKg {
            let ceiling = e1rm * slot.curve.share(repsToFailure: reps + rir - StrengthRules.ceilingReps)
            if intended > ceiling {
                intended = ceiling
                ceilingBound = true
                rules.append("7.6")
            }
        }

        var load = grid.nearest(intended)
        // Last week's bar, rounded down to the grid in case the unit or step changed since (1.4).
        if ceilingBound, d >= 0 { load = max(load, grid.down(ratedLoad + LoadGrid.storedTolerance)) }
        if load > ratedLoad {
            // 1.1: after rounding, a rise is at most last week's bar × (1 + CAP_UP) rounded down, or one step.
            let limit = max(grid.down(ratedLoad * (1 + capUp)), grid.moved(ratedLoad, bySteps: 1))
            if load > limit {
                load = limit
                rules.append("1.1")
            }
        }
        return make(kind, reps: reps, rir: rir, sets: sets, intended: intended, load: load, rules: rules)
    }

    /// 1.2: when one step is over 7.5% of the load, reps rise (up to 3) before the load takes a step.
    private static func repsMode(
        _ slot: StrengthSlotContext,
        last: StrengthSession,
        rated: StrengthSession.LoggedSet,
        ratedLoad: Double,
        delta: Int,
        clock: StrengthClock,
        kind: StrengthSlotKind,
        reps: Int,
        rir: Int,
        sets: Int,
        grid: LoadGrid
    ) -> StrengthSlotPlan {
        let load = grid.nearest(ratedLoad)
        let lastOffset = clock.startsBlock ? 0 : last.plan.repOffset
        var offset = lastOffset

        // fit(L): the most reps, minus I, that load L allows on the lifter's curve, from the rated set and misses.
        let ratedRIR = (rated.reps ?? 0) < last.plan.targetReps ? 0 : (last.rir ?? last.plan.rir)
        let estimates = [(load: ratedLoad, n: (rated.reps ?? 0) + ratedRIR)]
            + last.missedSets.compactMap { set in set.loadKg.map { (load: $0, n: set.reps ?? 0) } }
        let e = estimates.filter { $0.n > 0 }
            .map { $0.load / slot.curve.share(repsToFailure: min($0.n, 15)) }
            .min() ?? ratedLoad
        func fit(_ kilograms: Double) -> Int {
            let ratio = kilograms / e
            let n = (1...StrengthRules.fitMaxReps).last { slot.curve.share(repsToFailure: $0) >= ratio } ?? 1
            return max(1, n - rir)
        }

        var newLoad = load
        if delta >= 0 {
            let up = grid.moved(load, bySteps: 1)
            let fitUp = fit(up)
            if fitUp >= reps {
                newLoad = up
                offset = 0
            } else if offset < StrengthRules.repOffsetMax {
                offset += 1
            } else if slot.role == .primary, fitUp < StrengthRules.repsMinNormal {
                // The next step would leave too few reps; hold until smaller plates exist.
            } else {
                newLoad = up
                offset = fitUp - reps
            }
        } else if delta < -StrengthRules.deadbandReps {
            offset -= -delta - StrengthRules.deadbandReps
            if reps + offset < 1 {
                let down = grid.moved(load, bySteps: -1)
                newLoad = down
                offset = min(fit(down), reps + lastOffset) - reps
            }
        }

        var plan = make(kind, reps: reps, rir: rir, sets: sets, intended: newLoad, load: newLoad, rules: ["1.2"])
        // Out of reps mode once a step fits again and reps are back to R (1.2).
        if !grid.isCoarse(at: newLoad), offset >= 0 { offset = 0 }
        plan.repOffset = offset
        plan.sets = StrengthSlotPlan.uniform(sets, reps: plan.targetReps, loadKg: newLoad)
        return plan
    }

    /// CAP_UP: 7.5%, 5% for advanced lifters and calibration weeks, and the nudge while rebuilding after a reset.
    private static func capUp(clock: StrengthClock, record: StrengthLiftRecord, lastKind: StrengthSlotKind) -> Double {
        if record.rebuildWeeksLeft > 0 {
            return clock.experience == .advanced ? StrengthRules.nudgeAdvanced : StrengthRules.nudgeIntermediate
        }
        if clock.experience == .advanced || lastKind == .calibration || record.isCalibrating {
            return StrengthRules.capUpCautious
        }
        return StrengthRules.capUp
    }

    private static func make(
        _ kind: StrengthSlotKind,
        reps: Int,
        rir: Int,
        sets: Int,
        intended: Double?,
        load: Double?,
        rules: [String]
    ) -> StrengthSlotPlan {
        StrengthSlotPlan(
            kind: kind,
            reps: reps,
            rir: rir,
            sets: StrengthSlotPlan.uniform(sets, reps: reps, loadKg: load),
            // Past what a set can log, sub-step rises would build up out of reach (1.1).
            intendedKg: intended.map { min($0, LoadGrid.capKilograms) },
            rules: rules
        )
    }

    // MARK: Accessories

    /// Today's double progression with the strength load steps: a rep a week until every set reaches
    /// 85% of the range's top, then a step. It never adds sets (5.1).
    private static func accessoryPlan(_ slot: StrengthSlotContext, deload: Bool) -> StrengthSlotPlan {
        let last = slot.history.first { !$0.plan.kind.isLight }
        let first = StrengthSlotPlan(
            kind: .accessory,
            reps: slot.repRange.lowerBound,
            rir: 2,
            sets: StrengthSlotPlan.uniform(WorkoutExercise.initialSets, reps: nil, loadKg: nil)
        )
        let logged = last?.completedSets ?? []
        // Last time's sets as they were done, and any skipped as they were planned, so an accessory keeps its sets.
        var sets = logged.isEmpty ? (last?.plan ?? first).sets : carried(last)
        // A deload week halves the sets whether or not last week's were logged (10.6).
        if deload {
            let kept = max(1, Int(Double(sets.count) * StrengthRules.deloadSetFactor))
            sets = sets.prefix(kept).map { set in
                StrengthPlannedSet(
                    reps: set.reps,
                    loadKg: set.loadKg.map { slot.grid?.nearest($0 * StrengthRules.deloadLoadFactor) ?? $0 }
                )
            }
            return StrengthSlotPlan(kind: .deload, reps: sets.first?.reps ?? slot.repRange.lowerBound, rir: 2, sets: sets, rules: ["10.6"])
        }
        guard let last else { return first }
        guard !logged.isEmpty else {
            var repeated = last.plan
            repeated.kind = .accessory
            return repeated
        }

        var rules = ["5.1"]
        if last.isPainful || last.rir == 0 {
            rules.append("hold")
        } else if sets.contains(where: { ($0.reps ?? .max) < slot.repRange.lowerBound }) {
            // Short of the range: back to its bottom at the same weight, as today's double progression does.
            sets = sets.map { StrengthPlannedSet(reps: $0.reps.map { max($0, slot.repRange.lowerBound) }, loadKg: $0.loadKg) }
            rules.append("hold")
        } else {
            let loadReady = Int((0.85 * Double(slot.repRange.upperBound)).rounded(.up))
            if let grid = slot.grid, logged.allSatisfy({ ($0.reps ?? 0) >= loadReady && ($0.loadKg ?? 0) > 0 }) {
                sets = sets.map { StrengthPlannedSet(reps: $0.reps, loadKg: $0.loadKg.map { grid.moved($0, bySteps: 1) }) }
            } else {
                sets = sets.map { StrengthPlannedSet(reps: $0.reps.map { min($0 + 1, slot.repRange.upperBound) }, loadKg: $0.loadKg) }
            }
        }
        return StrengthSlotPlan(
            kind: .accessory,
            reps: sets.first?.reps ?? slot.repRange.lowerBound,
            rir: 2,
            sets: sets,
            rules: rules
        )
    }

    /// A session's sets as done, with any it skipped as they were planned, or as the last set done when they had
    /// no target.
    private static func carried(_ session: StrengthSession?) -> [StrengthPlannedSet] {
        guard let session else { return [] }
        let lastDone = session.completedSets.last
        return session.sets.enumerated().map { index, set in
            if set.completed, (set.reps ?? 0) > 0 {
                return StrengthPlannedSet(reps: set.reps, loadKg: set.loadKg)
            }
            let planned = session.plan.sets.indices.contains(index) ? session.plan.sets[index] : StrengthPlannedSet()
            return StrengthPlannedSet(reps: planned.reps ?? lastDone?.reps, loadKg: planned.loadKg ?? lastDone?.loadKg)
        }
    }

    // MARK: Warm-ups

    /// 5.7: 50% × 5, 70% × 3 and 85% × 1 of the first working load on primary slots (the 85% one only when
    /// that load is 80% of e1RM or more), 50% × 5 and 75% × 3 on secondary slots. Calibration keeps today's.
    static func warmups(for plan: StrengthSlotPlan, slot: StrengthSlotContext, record: StrengthLiftRecord) -> [StrengthPlannedSet]? {
        guard plan.kind != .calibration, let load = plan.loadKg, let grid = slot.grid else { return nil }
        let scheme = slot.role == .primary ? StrengthRules.primaryWarmups : StrengthRules.secondaryWarmups
        var warmups: [StrengthPlannedSet] = []
        for (share, reps) in scheme {
            if share > StrengthRules.heavyWarmupGate, let e1rm = record.e1rmKg, load < StrengthRules.heavyWarmupGate * e1rm {
                continue
            }
            let warmup = grid.nearest(load * share)
            // Warm-ups at the bar, or that round to the same load, merge into one set.
            guard warmup < load - LoadGrid.storedTolerance, warmup != warmups.last?.loadKg else { continue }
            warmups.append(StrengthPlannedSet(reps: reps, loadKg: warmup))
        }
        return Array(warmups.prefix(WorkoutExercise.maxWarmupSets))
    }
}
