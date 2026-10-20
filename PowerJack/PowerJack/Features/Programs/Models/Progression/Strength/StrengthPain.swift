//
//  StrengthPain.swift
//  PowerJack
//
//  Pain always outranks progression (module 15). Moderate pain cuts the next session 10% and a set,
//  Severe or worse opens a check-in (Lighter or Skip), then the lift ramps back a step per easy session.
//  The app asks nothing about health: these rules read only the 0-5 pain rating (Decisions).
//

import Foundation

enum StrengthPain {
    /// Moves a lift's pain state through one of its sessions, in date order.
    static func record(_ state: inout StrengthPainState, session: StrengthSession) {
        // The session after a check-in or a cut uses it up; the ramp starts with the one after (15.1).
        let usedPending = state.pending != nil && session.trained
        if usedPending, let pending = state.pending {
            state.pending = nil
            let share = pending == .lighter ? 1 - StrengthRules.painCut : 1 - StrengthRules.painModerateCut
            state.capShare = min(state.capShare ?? 1, share)
        }

        // Without a rating, no pain rule fires and nothing advances.
        guard let rating = session.pain else { return }
        state.ratings = Array((state.ratings + [rating]).suffix(3))

        if rating >= StrengthRules.painStop.rawValue {
            state.pending = .lighter
            state.rirFloor = true
            let lighterSets = StrengthRules.painReturnSets
            state.setsDropped = max(state.setsDropped, session.plan.sets.count - lighterSets)
        } else if rating >= StrengthRules.painHold.rawValue {
            state.pending = .cut
            state.setsDropped = max(state.setsDropped, 1)
        } else if !usedPending, state.isRamping, rating <= LevelOfPain.mild.rawValue {
            // Each easy session gives back a set, then 5% of the load cap (15.7).
            if state.setsDropped > 0 {
                state.setsDropped -= 1
            } else if let cap = state.capShare {
                let raised = cap * (1 + StrengthRules.painReturnStep)
                state.capShare = raised >= 1 ? nil : raised
                if state.capShare == nil { state.rirFloor = false }
            }
        }
    }

    /// Lowers a slot's plan for the lift's pain before its session starts (15.4-15.7).
    /// - Returns: `true` when the slot must open with a check-in.
    static func apply(
        _ state: StrengthPainState,
        to plan: inout StrengthSlotPlan,
        lastSession: StrengthSession?,
        grid: LoadGrid?
    ) -> Bool {
        let base = plan.intendedKg ?? plan.loadKg ?? lastSession?.ratedSet?.loadKg
        func capped(_ share: Double) -> Double? {
            guard let base else { return plan.loadKg }
            let load = base * share
            return grid.map { $0.down(load) } ?? load
        }

        switch state.pending {
        case .lighter:
            plan.kind = .painLighter
            plan.rir = max(plan.rir, StrengthRules.painReturnRIR)
            plan.sets = StrengthSlotPlan.uniform(
                StrengthRules.painReturnSets,
                reps: plan.targetReps,
                loadKg: capped(1 - StrengthRules.painCut)
            )
            plan.rules.append("15.4")
            return true
        case .cut:
            plan.kind = .painCut
            plan.sets = StrengthSlotPlan.uniform(
                plan.sets.count - 1,
                reps: plan.targetReps,
                loadKg: capped(1 - StrengthRules.painModerateCut)
            )
            plan.rules.append("15.5")
            return false
        case nil:
            break
        }

        if state.isRamping {
            plan.kind = .painCut
            if state.rirFloor { plan.rir = max(plan.rir, StrengthRules.painReturnRIR) }
            let load = [plan.loadKg, state.capShare.flatMap { capped($0) }].compactMap { $0 }.min()
            plan.sets = StrengthSlotPlan.uniform(plan.sets.count - state.setsDropped, reps: plan.targetReps, loadKg: load)
            plan.rules.append("15.7")
        }
        if state.holds, let last = lastSession, last.trained {
            // Hold load and sets: nothing rises past the last session (15.6).
            let lastLoad = last.ratedSet?.loadKg
            let load = [plan.loadKg, lastLoad].compactMap { $0 }.min()
            plan.sets = StrengthSlotPlan.uniform(min(plan.sets.count, last.completedSets.count), reps: plan.targetReps, loadKg: load)
            if let lastLoad, let intended = plan.intendedKg { plan.intendedKg = min(intended, lastLoad) }
            plan.rules.append("15.6")
        }
        return false
    }
}
