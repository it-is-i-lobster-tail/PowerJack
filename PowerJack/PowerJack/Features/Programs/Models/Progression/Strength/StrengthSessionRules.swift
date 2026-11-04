//
//  StrengthSessionRules.swift
//  PowerJack
//
//  Rules that run during the week rather than at its end: a lift coming back from a break,
//  checked when its workout starts (12.1-12.2), and the miss rule after a short set (6.2).
//

import Foundation

enum StrengthSessionRules {
    /// 12.2's row for the days since the lift was last trained: 1 for 15-28, 2 for 29-56, 3 for 57-90
    /// and 4 for more. `nil` for 14 days or fewer, which is not a break (12.1).
    static func returnBand(daysOff: Int) -> Int? {
        switch daysOff {
        case ...StrengthRules.breakMinDays: nil
        case ...28: 1
        case ...56: 2
        case ...90: 3
        default: 4
        }
    }

    static func daysOff(since lastTrained: Date?, at date: Date) -> Int? {
        guard let lastTrained else { return nil }
        return Calendar.current.dateComponents([.day], from: lastTrained, to: date).day
    }

    /// 12.2, week 1 back: lighter and a set fewer by the length of the break. Over 90 days the lift
    /// restarts from 75% of its e1RM with 2 more reps in reserve and calibrates again.
    static func applyReturn(
        band: Int,
        to plan: inout StrengthSlotPlan,
        preBreakKg: Double?,
        e1rmKg: Double?,
        curve: StrengthCurve,
        grid: LoadGrid
    ) {
        let (cut, rirAdd): (Double, Int) = switch band {
        case 1: (0.05, 0)
        case 2: (0.10, 1)
        case 3: (0.15, 2)
        default: (0, 2)
        }
        plan.kind = .returnWeek1
        plan.returnBand = band
        plan.rir += rirAdd
        plan.repOffset = 0
        // A top set is already planned from e1RM at this week's reps, so it cuts from that; straight sets cut
        // from the last load before the break.
        let base = plan.topSets > 0 ? plan.intendedKg ?? preBreakKg : preBreakKg ?? plan.intendedKg
        var intended = (base ?? plan.loadKg).map { $0 * (1 - cut) }
        if band >= 4, let e1rmKg {
            intended = e1rmKg * 0.75 * curve.share(repsToFailure: plan.reps + plan.rir)
        }
        plan.intendedKg = intended
        if plan.topSets > 0 {
            // The top set takes the cut and the back-offs follow it, one fewer.
            let share = plan.backShare
            let top = intended.map(grid.nearest)
            let backs = plan.sets.dropFirst(plan.topSets)
            plan.sets = StrengthSlotPlan.topAndBack(
                reps: plan.reps,
                loadKg: top,
                backSets: max(StrengthRules.minBackSets, backs.count - 1),
                backReps: backs.first?.reps ?? plan.reps,
                backLoadKg: top.map { grid.nearest($0 * share) }
            )
        } else {
            plan.sets = StrengthSlotPlan.uniform(plan.sets.count - 1, reps: plan.reps, loadKg: intended.map(grid.nearest))
        }
        // A near-max top set keeps its spotter reminder (5.2).
        plan.rules = ["12.1", "12.2"] + plan.rules.filter { $0 == "5.2" }
    }

    /// 6.2: after a set short of its target reps, the sets still to do drop 4% per missing rep,
    /// at most 10% under their plan, and always by at least one step.
    static func loadAfterMiss(setLoadKg: Double, missingReps: Int, plannedKg: Double, grid: LoadGrid) -> Double {
        let cut = setLoadKg * (1 - StrengthRules.missDrop * Double(missingReps))
        let floor = plannedKg * (1 - 0.10)
        let load = grid.nearest(max(cut, floor))
        return load < setLoadKg - LoadGrid.storedTolerance ? load : grid.moved(setLoadKg, bySteps: -1)
    }

    /// 5.10: the back-off weight after a top set of `reps` (of `plannedReps`) at `topKg`, rated `rated` reps left
    /// against `aim`: `share` of it, 2.5% more per rep easier (up to 2), 4% less per rep harder or missed (up to 3).
    static func backOffLoad(topKg: Double, share: Double, reps: Int, plannedReps: Int, rated: Int, aim: Int, grid: LoadGrid) -> Double {
        let gap = reps < plannedReps ? -(aim + plannedReps - reps) : rated - aim
        let change = gap > 0
            ? StrengthRules.backEasyStep * Double(min(gap, StrengthRules.backEasyMaxReps))
            : -StrengthRules.backHardStep * Double(min(-gap, StrengthRules.backHardMaxReps))
        return grid.nearest(topKg * share * (1 + change))
    }
}
