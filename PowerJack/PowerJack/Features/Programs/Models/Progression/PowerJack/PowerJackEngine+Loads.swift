//
//  PowerJackEngine+Loads.swift
//  PowerJack
//
//  Loads and reps for each kind of week: block start (R2.2, R2.4, R9.1), the weeks after it
//  (R2.3, R2.4, R2.6, R6.8, R10.2 to R10.5) and the deload (R6.3).
//

import Foundation

extension PowerJackWeekBuilder {
    // MARK: Block start

    func blockStartPlans() -> [SlotRef: PowerJackEntryPlan] {
        var plans: [SlotRef: PowerJackEntryPlan] = [:]
        let sets = blockStartSetCounts()
        for slot in slots {
            var plan = emptyPlan(slot)
            let count = sets[slot] ?? 2
            switch role(slot).role {
            case .main: startMainLift(&plan, slot: slot, sets: count)
            case .secondary, .accessory: startDoubleProgression(&plan, slot: slot, sets: count)
            }
            plan.reasons.insert(plan.calibrating ? .calibrate : .blockStart, at: 0)
            plans[slot] = plan
        }
        return plans
    }

    /// R2.2: load = anchor x PCT(reps + target), rounded down, or blank for the lifter to load (R8.8).
    private func startMainLift(_ plan: inout PowerJackEntryPlan, slot: SlotRef, sets: Int) {
        let exercise = exercise(slot)
        let steps = PowerJackSteps(origin: lastLoggedLoad(exercise))
        let best = bestRecentLoad(exercise)
        let target = PowerJackRules.rirByColumn(.main, goal)[0]

        func part(_ series: PowerJackSeries, reps: Int, count: Int) -> (sets: [PowerJackSetPlan], loadTarget: Double?, calibrating: Bool) {
            let start = blockStartAnchor(exercise, series)
            guard let anchor = start.anchor,
                  let loadTarget = PowerJackPercent.load(e1RM: anchor, reps: reps, rir: max(target, start.calibrating ? PowerJackRules.calibrationRIR : 0))
            else {
                return (Array(repeating: PowerJackSetPlan(reps: reps), count: count), nil, true)
            }
            let load = steps.capped(steps.roundDown(loadTarget), best: best)
            return (Array(repeating: PowerJackSetPlan(reps: reps, load: load), count: count), loadTarget, start.calibrating)
        }

        switch role(slot).tag {
        case .topAndBack:
            let top = part(.heavy, reps: heavyReps, count: PowerJackRules.topSets)
            let back = part(.volume, reps: volumeReps, count: max(1, sets - PowerJackRules.topSets))
            plan.topSets = PowerJackRules.topSets
            plan.sets = top.sets + back.sets
            plan.topLoadTarget = top.loadTarget
            plan.loadTarget = back.loadTarget
            plan.calibrating = top.calibrating || back.calibrating
        case .volume:
            let straight = part(.volume, reps: volumeReps, count: sets)
            (plan.sets, plan.loadTarget, plan.calibrating) = straight
        case .heavy, nil:
            let straight = part(.heavy, reps: heavyReps, count: sets)
            (plan.sets, plan.loadTarget, plan.calibrating) = straight
        }
    }

    /// R2.4 at block start: keep the load, reset reps by the drop in target. A slot new to the plan
    /// starts from its exercise's own history, or the lifter loads it (R9.1).
    private func startDoubleProgression(_ plan: inout PowerJackEntryPlan, slot: SlotRef, sets: Int) {
        let exercise = exercise(slot)
        let range = repRange(slot)
        let target = PowerJackRules.rirByColumn(role(slot).role, goal)[0]

        if let previous = latestBuildLog(slot) {
            // The same slot last block: keep its load and reps minus the drop in target.
            let drop = target - (previous.target ?? target)
            let load = previous.parts.first?.firstLoad
            let reps = previous.sets.map { max(range.lowerBound, ($0.plannedReps ?? range.lowerBound) - drop) }
            plan.sets = (0..<sets).map { index in
                PowerJackSetPlan(reps: reps.indices.contains(index) ? reps[index] : reps.last ?? range.lowerBound, load: exercise.repsOnly ? nil : load)
            }
            return
        }

        // R9.1: the exercise's newest exposure within 12 weeks, in any program or style.
        let oldest = context.now.addingTimeInterval(-Double(PowerJackRules.historyMaxAgeWeeks) * 7 * 86_400)
        let recent = context.history(exercise.id).last { $0.date >= oldest && $0.entry.hasCompletedSets }
        var load: Double?
        if !exercise.repsOnly, let recent, let value = recent.entry.parts.last?.value?.value,
           let start = PowerJackPercent.load(e1RM: value, reps: range.lowerBound, rir: target) {
            load = PowerJackSteps(origin: recent.entry.parts.last?.firstLoad).roundDown(start)
        }
        plan.calibrating = recent == nil
        plan.sets = Array(repeating: PowerJackSetPlan(reps: range.lowerBound, load: load), count: sets)
    }

    /// The slot's entry in the latest BUILD week of the program.
    func latestBuildLog(_ slot: SlotRef) -> PowerJackEntryLog? {
        for week in weeks.reversed() where week.type == .build {
            if let entry = log(slot, in: week), !workoutSkipped(slot, in: week) { return entry }
        }
        return nil
    }

    func lastLoggedLoad(_ exercise: PowerJackExercise) -> Double? {
        context.history(exercise.id).last { $0.entry.hasCompletedSets }?.entry.sets.last { $0.isComplete }?.load
    }

    /// R2.5: the heaviest completed working load in the last 14 days, else the last completed load.
    func bestRecentLoad(_ exercise: PowerJackExercise) -> Double? {
        let oldest = context.now.addingTimeInterval(-Double(PowerJackRules.lookbackDays) * 86_400)
        let recent = context.history(exercise.id)
            .filter { $0.date >= oldest }
            .flatMap { $0.entry.sets.filter(\.isComplete).compactMap(\.load) }
            .max()
        return recent ?? lastLoggedLoad(exercise)
    }

    // MARK: Later weeks of a block

    func continuedPlans(header: PowerJackWeekPlanHeader) -> [SlotRef: PowerJackEntryPlan] {
        guard let last = weeks.last else { return [:] }
        let cuts = setCuts(header: header)
        let flagged = header.holdFlagged ? flaggedExercises(in: last) : []
        var plans: [SlotRef: PowerJackEntryPlan] = [:]
        for slot in slots {
            var plan = emptyPlan(slot)
            guard let entry = log(slot, in: last) else {
                plans[slot] = plan
                continue
            }
            plan.sets = entry.sets.map { PowerJackSetPlan(reps: $0.plannedReps, load: $0.plannedLoad) }
            plan.topSets = entry.topSets
            plan.loadTarget = entry.loadTarget
            plan.topLoadTarget = entry.topLoadTarget

            // R6.8: a skipped workout is not made up; its slots repeat their plan.
            if workoutSkipped(slot, in: last) || !entry.hasCompletedSets {
                plan.calibrating = entry.calibrating
                plan.reasons.append(.repeatSkipped)
            } else if !applyPain(&plan, slot: slot, entry: entry) {
                let outcomes = classes(slot, in: last) ?? []
                let held = flagged.contains(exercise(slot).id)
                let setFell = cuts.contains(slot)
                switch role(slot).role {
                case .main:
                    progressMainLift(&plan, slot: slot, entry: entry, classes: outcomes, header: header, held: held, setFell: setFell)
                case .secondary, .accessory:
                    let previous = previousBuildWeek(before: last).flatMap { log(slot, in: $0) }
                    let result = doubleProgression(
                        entry.parts[0],
                        previous: previous?.parts.first,
                        outcome: outcomes.first ?? .none,
                        range: repRange(slot),
                        exercise: exercise(slot),
                        caution: header.caution,
                        held: held,
                        setFell: setFell
                    )
                    plan.sets = result.sets
                    plan.reasons.append(result.reason)
                }
            }
            if cuts.contains(slot) { removeSet(&plan) }
            plans[slot] = plan
        }
        addSets(&plans, header: header)
        return plans
    }

    /// R2.3, or R2.2 again right after a calibrating exposure. A TOP + BACK entry moves each part.
    private func progressMainLift(
        _ plan: inout PowerJackEntryPlan,
        slot: SlotRef,
        entry: PowerJackEntryLog,
        classes: [PowerJackClass],
        header: PowerJackWeekPlanHeader,
        held: Bool,
        setFell: Bool
    ) {
        let exercise = exercise(slot)
        let tag = role(slot).tag
        let tNow = entry.target ?? PowerJackRules.calibrationRIR
        let tNext = PowerJackRules.rirByColumn(.main, goal)[max(0, header.column - 1)]
        var newSets: [PowerJackSetPlan] = []
        var reason = PowerJackReason.ramp

        for (index, part) in entry.parts.enumerated() {
            let isTop = entry.isTopAndBack && index == 0
            let series: PowerJackSeries = isTop || tag == .heavy ? .heavy : .volume
            let reps = part.plannedReps ?? (series == .heavy ? heavyReps : volumeReps)
            let L = part.firstLoad
            let steps = PowerJackSteps(origin: L)
            var loadTarget = part.loadTarget
            var load = part.sets.first?.plannedLoad

            if entry.calibrating, classes.indices.contains(index), classes[index] != .none,
               let anchor = calibratedAnchor(part, exercise, series, loggedOn: entry.lastCompletedAt),
               let target = PowerJackPercent.load(e1RM: anchor, reps: reps, rir: tNext) {
                // R8.8: uncapped, straight from the new anchor.
                loadTarget = target
                load = PowerJackSteps(origin: L).roundDown(target)
                reason = .calibrate
            } else if entry.calibrating {
                // No usable calibrating exposure yet (skipped or painful): the next one calibrates.
                plan.calibrating = true
            } else if let L, classes.indices.contains(index), classes[index] != .none {
                var outcome = classes[index]
                if header.caution, outcome == .easy { outcome = .met }
                if steps.step / L * 100 > PowerJackRules.bandModePct {
                    // A step too big for the load: progress reps within reps...reps + 2 instead.
                    let result = doubleProgression(
                        part, previous: nil, outcome: outcome, range: reps...(reps + 2),
                        exercise: exercise, caution: header.caution, held: held, setFell: setFell, limit: reps + 4
                    )
                    newSets += result.sets
                    reason = result.reason
                    continue
                }
                let prescribed = part.sets.first?.plannedLoad
                let base = prescribed == L ? (part.loadTarget ?? L) : L
                let ramp = (PowerJackPercent.percent(reps: Double(reps + tNext)) ?? 1)
                    / (PowerJackPercent.percent(reps: Double(reps + tNow)) ?? 1)
                var target: Double
                switch outcome {
                case .met:
                    target = base * ramp
                case .easy:
                    target = base * ramp * (1 + PowerJackRules.easyStepPct / 100)
                    reason = .easyStep
                case .missBig:
                    let short = part.completed.reduce(0) { $0 + max(0, ($1.plannedReps ?? 0) - ($1.reps ?? 0)) }
                    let cut = min(PowerJackRules.missCutMaxPct, PowerJackRules.missCutPerRepPct * Double(short))
                    target = setFell ? L : min(L * (1 - cut / 100), L - steps.step)
                    reason = setFell ? .hold : .missCut
                case .none, .incomplete, .missSmall, .hard:
                    target = L
                    reason = .hold
                }
                if held { target = min(target, L) }
                if part.source != .tapped { target = min(target, L + steps.step) }
                loadTarget = target
                load = target < L ? steps.roundNearest(target) : steps.capped(steps.roundNearest(target), best: bestRecentLoad(exercise))
            }
            newSets += part.sets.map { _ in PowerJackSetPlan(reps: reps, load: load) }
            if isTop { plan.topLoadTarget = loadTarget } else { plan.loadTarget = loadTarget }
        }
        plan.sets = newSets
        plan.reasons.append(reason)
    }

    /// R2.4 and R2.6: add reps to the top of the range, then a load jump that costs reps.
    func doubleProgression(
        _ part: PowerJackPart,
        previous: PowerJackPart?,
        outcome: PowerJackClass,
        range: ClosedRange<Int>,
        exercise: PowerJackExercise,
        caution: Bool,
        held: Bool,
        setFell: Bool,
        limit customLimit: Int? = nil
    ) -> (sets: [PowerJackSetPlan], reason: PowerJackReason) {
        let planned = part.sets.map { PowerJackSetPlan(reps: $0.plannedReps, load: $0.plannedLoad) }
        let done = part.sets.map { $0.isComplete ? ($0.reps ?? 0) : ($0.plannedReps ?? 0) }
        guard outcome != .none, let first = done.first else { return (planned, .hold) }

        let lo = range.lowerBound
        let hiBase = range.upperBound
        let hi = max(hiBase, part.sets.compactMap(\.plannedReps).max() ?? hiBase)
        let limit = customLimit ?? min(hiBase + PowerJackRules.repRangeExtensionMax, PowerJackRules.bodyweightRepCap)
        let L = exercise.repsOnly ? nil : part.firstLoad
        let step = PowerJackRules.stepPounds
        let r = outcome == .easy && !caution ? PowerJackRules.repsPerStepEasy : PowerJackRules.repsPerStep
        let sets = { (reps: [Int], load: Double?) in reps.map { PowerJackSetPlan(reps: $0, load: load) } }

        // A set below the range: cut 5% on a clear or repeated shortfall, else hold.
        if done.contains(where: { $0 < lo }) {
            let repeated = previous?.completed.contains { ($0.reps ?? lo) < lo } ?? false
            guard first <= lo - 2 || repeated, !setFell else { return (planned, .hold) }
            if let L {
                let cut = min(PowerJackSteps(origin: L).roundDown(L * (1 - PowerJackRules.backoffPct / 100)), L - step)
                return (sets(done.map { _ in lo }, max(step, cut)), .backoff)
            }
            return (sets(done.map { max(1, $0) }, nil), .backoff)
        }
        if outcome == .incomplete || outcome.isMiss || outcome == .hard || held {
            return (planned.map { PowerJackSetPlan(reps: $0.reps, load: L ?? $0.load) }, .hold)
        }
        guard done.min()! >= hiBase else {
            return (sets(done.map { min(exercise.repsOnly ? limit : hi, $0 + r) }, L), .repStep)
        }
        guard let L, !exercise.repsOnly else {
            return (sets(done.map { min(limit, $0 + r) }, nil), .repStep)
        }
        let jumpSteps = max(1, Int((L * PowerJackRules.saJumpPct / 100 / step - 1e-9).rounded(.toNearestOrAwayFromZero)))
        let jump = step * Double(part.source == .tapped ? jumpSteps : 1)
        let drop = max(1, (jump / L * 100 / PowerJackRules.repCostPct).roundedHalfUp)
        if done.min()! - drop >= lo {
            return (sets(done.map { max(lo, $0 - drop) }, L + jump), .loadJump)
        }
        if done.min()! >= limit { return (planned, .hold) }
        let widened = min(hi + 2, limit)
        return (sets(done.map { min(widened, $0 + r) }, L), .widenRange)
    }

    // MARK: Deload

    /// R6.3: the first half of each slot's latest BUILD sets at 90% load and the same reps, or at
    /// 60% of the reps and the old load where the rounded cut passes 20%.
    func deloadPlans() -> [SlotRef: PowerJackEntryPlan] {
        var plans: [SlotRef: PowerJackEntryPlan] = [:]
        // A second deload repeats the first.
        let repeatDeload = weeks.last?.type == .deload
        for slot in slots {
            var plan = emptyPlan(slot)
            plan.reasons = [.deload]
            if repeatDeload, let last = weeks.last, let entry = log(slot, in: last) {
                plan.sets = entry.sets.map { PowerJackSetPlan(reps: $0.plannedReps, load: $0.plannedLoad) }
                plan.topSets = entry.topSets
                plan.loadTarget = entry.loadTarget
                plan.topLoadTarget = entry.topLoadTarget
                plans[slot] = plan
                continue
            }
            guard let base = latestBuildLog(slot) ?? weeks.last.flatMap({ log(slot, in: $0) }) else {
                plans[slot] = plan
                continue
            }
            let count = max(1, (Double(base.sets.count) * PowerJackRules.deloadSetFactor).roundedHalfUp)
            plan.topSets = min(base.topSets, count)
            plan.loadTarget = base.loadTarget
            plan.topLoadTarget = base.topLoadTarget
            plan.sets = base.sets.prefix(count).map { set in
                let reps = set.plannedReps ?? set.reps
                let load = set.isComplete ? (set.load ?? set.plannedLoad) : set.plannedLoad
                let fewerReps = reps.map { max(1, (Double($0) * PowerJackRules.deloadRepFactor).roundedHalfUp) }
                guard let load, !base.exercise.repsOnly, !base.exercise.assisted else {
                    return PowerJackSetPlan(reps: fewerReps, load: load)
                }
                let lighter = PowerJackSteps().roundDown(load * PowerJackRules.deloadLoadFactor)
                if (load - lighter) / load > PowerJackRules.deloadMaxCutPct / 100 {
                    return PowerJackSetPlan(reps: fewerReps, load: load)
                }
                return PowerJackSetPlan(reps: reps, load: lighter)
            }
            plans[slot] = plan
        }
        return plans
    }
}
