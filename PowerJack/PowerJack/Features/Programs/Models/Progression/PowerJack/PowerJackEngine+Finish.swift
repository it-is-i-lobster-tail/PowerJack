//
//  PowerJackEngine+Finish.swift
//  PowerJack
//
//  Pain gates (R10.2 to R10.5), then the last steps of the weekly loop: target RIR with floors
//  (R4.3), planned rep-outs (R4.4) and warm-ups from the first working load (R10.8).
//

import Foundation

extension PowerJackWeekBuilder {
    // MARK: Pain

    /// Applies the exercise's pain state to the slot. Returns false when R2 should decide instead.
    func applyPain(_ plan: inout PowerJackEntryPlan, slot: SlotRef, entry: PowerJackEntryLog) -> Bool {
        let state = painState(exercise(slot))
        let steps = PowerJackSteps()
        switch state.action {
        case .progress:
            return false
        case .hold:
            plan.reasons.append(.painHold)
            return true
        case .reduce:
            for (index, part) in entry.parts.enumerated() {
                guard let last = part.heaviestLoad, !entry.exercise.repsOnly else {
                    removeSet(&plan)
                    break
                }
                let floor = prePainLoad(slot, part: index, episodeStart: state.episodeStart, fallback: last) * (1 - PowerJackRules.painMaxTotalCutPct / 100)
                let cut = PowerJackSteps(origin: last).roundDown(last - max(last * PowerJackRules.painCutPct / 100, steps.step))
                if cut >= floor { setLoad(&plan, part: index, of: entry, to: cut) }
            }
            plan.reasons.append(.painReduce)
            return true
        case .checkIn(let pain):
            // The check-in's Continue: 10% lighter, half the sets, the same reps (R10.4).
            for (index, part) in entry.parts.enumerated() {
                guard let last = part.heaviestLoad, !entry.exercise.repsOnly else { continue }
                let cut = PowerJackSteps(origin: last).roundDown(last - max(last * PowerJackRules.painCutPct / 100, steps.step))
                setLoad(&plan, part: index, of: entry, to: cut)
            }
            let keep = max(1, Int((Double(plan.sets.count) * PowerJackRules.painContinueSetFactor).rounded(.up)))
            plan.sets = Array(plan.sets.prefix(max(keep, plan.topSets > 0 ? plan.topSets + 1 : 1)))
            plan.checkInPain = pain
            plan.reasons.append(.painCheckIn)
            return true
        case .returning:
            let outcomes = weeks.last.flatMap { classes(slot, in: $0) } ?? []
            var climbed = false
            for (index, part) in entry.parts.enumerated() {
                guard let last = part.firstLoad, !entry.exercise.repsOnly else { return false }
                let prePain = prePainLoad(slot, part: index, episodeStart: state.episodeStart, fallback: last)
                guard last < prePain else { return false }
                let outcome = outcomes.indices.contains(index) ? outcomes[index] : .none
                let allDone = part.completed.allSatisfy { ($0.reps ?? 0) >= ($0.plannedReps ?? 0) }
                if outcome == .missBig { return false }
                if outcome.rises || (outcome == .none && allDone) {
                    let next = PowerJackSteps(origin: last).roundDown(last + max(steps.step, last * PowerJackRules.painReturnStepPct / 100))
                    setLoad(&plan, part: index, of: entry, to: min(prePain, next))
                    climbed = true
                }
            }
            plan.reasons.append(climbed ? .painReturn : .painHold)
            return true
        }
    }

    private func setLoad(_ plan: inout PowerJackEntryPlan, part: Int, of entry: PowerJackEntryLog, to load: Double) {
        let range = entry.isTopAndBack ? (part == 0 ? 0..<entry.topSets : entry.topSets..<plan.sets.count) : 0..<plan.sets.count
        for index in range where plan.sets.indices.contains(index) { plan.sets[index].load = load }
    }

    /// The slot's load from its last BUILD week before the episode opened, else the first painful one.
    private func prePainLoad(_ slot: SlotRef, part: Int, episodeStart: Date?, fallback: Double) -> Double {
        guard let episodeStart else { return fallback }
        let entries = weeks.filter { $0.type == .build }.compactMap { log(slot, in: $0) }
        let before = entries.last { ($0.lastCompletedAt ?? .distantFuture) < episodeStart }
        let first = entries.first { ($0.lastCompletedAt ?? .distantPast) >= episodeStart }
        let load = (before ?? first).flatMap { $0.parts.indices.contains(part) ? $0.parts[part].heaviestLoad : nil }
        return load ?? fallback
    }

    // MARK: Targets, rep-outs and warm-ups

    func finish(_ plans: inout [SlotRef: PowerJackEntryPlan], header: PowerJackWeekPlanHeader) {
        let last = weeks.last
        for slot in slots {
            guard var plan = plans[slot] else { continue }
            let pain = painState(exercise(slot))
            if header.type == .build {
                var target = PowerJackRules.rirByColumn(role(slot).role, goal)[min(3, max(0, header.column - 1))]
                let reps = plan.sets.last?.reps ?? 0
                if reps > PowerJackRules.highRepThreshold { target += PowerJackRules.highRepOffset }
                if reps > PowerJackRules.veryHighRepThreshold { target = min(target, 1) }
                target = max(target, 1)
                if plan.calibrating { target = max(target, PowerJackRules.calibrationRIR) }
                if pain.inEpisode { target = max(target, PowerJackRules.painRIRFloor) }
                plan.target = target
            }
            plan.warmups = warmups(for: plan, slot: slot, inPain: pain.action != .progress)
            plans[slot] = plan
        }

        // R4.4: in the block's final column, the last 2 eligible Low-fatigue accessories a session
        // take their last set to failure.
        guard header.type == .build, header.column == 4 else { return }
        for workout in structure.indices {
            let eligible = structure[workout].indices.map { SlotRef(workout: workout, entry: $0) }.filter { slot in
                guard let plan = plans[slot] else { return false }
                return role(slot).role == .accessory
                    && exercise(slot).fatigue == .low
                    && !plan.calibrating
                    && !header.caution
                    && !plan.reasons.contains(.addedSet)
                    && painState(exercise(slot)).action == .progress
                    && !(last.map { strainSign(slot, in: $0) } ?? false)
            }
            for slot in eligible.suffix(PowerJackRules.maxRepOutsPerSession) {
                plans[slot]?.target = 0
                plans[slot]?.repOut = true
            }
        }
    }

    /// R10.8: 0-3 warm-ups by role, tag and place in the session, from the first working load.
    private func warmups(for plan: PowerJackEntryPlan, slot: SlotRef, inPain: Bool) -> [PowerJackSetPlan] {
        let exercise = exercise(slot)
        let earlier = structure[slot.workout].prefix(slot.entry)
        let isBackEntry = role(slot).role == .main && earlier.contains { $0.id == exercise.id }
        guard !plan.warmupsDisabled, !exercise.repsOnly, !exercise.assisted, !isBackEntry,
              let first = plan.sets.first
        else { return [] }

        let heavy = role(slot).tag == .heavy || role(slot).tag == .topAndBack || (first.reps ?? 0) <= 6
        let isFirst = !earlier.contains { $0.primary == exercise.primary }
        var count = switch role(slot).role {
        case .main: heavy ? 3 : 2
        case .secondary: isFirst ? 2 : 1
        case .accessory: isFirst ? 1 : 0
        }
        if inPain { count = max(count, 2) }
        let ladder: [(percent: Double, reps: Int)] = switch count {
        case 3: [(50, 5), (70, 3), (85, 1)]
        case 2: [(50, 5), (75, 3)]
        case 1: [(60, 5)]
        default: []
        }
        let reps = { (ladderReps: Int) in min(ladderReps, first.reps ?? ladderReps) }
        guard let working = first.load else {
            return ladder.map { PowerJackSetPlan(reps: reps($0.reps)) }
        }

        let steps = PowerJackSteps()
        var sets: [PowerJackSetPlan] = []
        for rung in ladder {
            var load = (rung.percent / 100 * working / steps.step + 1e-9).rounded(.down) * steps.step
            if exercise.isBarbell { load = max(load, PowerJackRules.barPounds) }
            guard load > 0, load < working - steps.step - 1e-9, load != sets.last?.load else { continue }
            sets.append(PowerJackSetPlan(reps: reps(rung.reps), load: load))
        }
        return sets
    }
}
