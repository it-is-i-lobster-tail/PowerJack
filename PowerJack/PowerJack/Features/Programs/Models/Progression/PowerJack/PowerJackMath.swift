//
//  PowerJackMath.swift
//  PowerJack
//
//  The reps-to-%1RM table (R8.1) and load steps and rounding (R2.5). Loads are pounds.
//

import Foundation

enum PowerJackPercent {
    /// (reps to failure, % of 1RM), joined by straight lines.
    private static let anchors: [(reps: Double, percent: Double)] = [
        (1, 100), (3.3, 95), (4.9, 90), (9.8, 80), (14.8, 70), (19.5, 60), (26.0, 50), (35.8, 40),
    ]

    /// The percent of 1RM that allows `reps` to failure, or nil outside the table.
    static func percent(reps: Double) -> Double? {
        guard let first = anchors.first, let last = anchors.last,
              reps >= first.reps, reps <= last.reps
        else { return nil }
        for (low, high) in zip(anchors, anchors.dropFirst()) where reps <= high.reps {
            return low.percent + (high.percent - low.percent) * (reps - low.reps) / (high.reps - low.reps)
        }
        return last.percent
    }

    static func e1RM(load: Double, reps: Int, rir: Int) -> Double? {
        guard load > 0, let pct = percent(reps: Double(reps + min(rir, PowerJackRules.rirCensor))) else { return nil }
        return load / (pct / 100)
    }

    static func load(e1RM: Double, reps: Int, rir: Int) -> Double? {
        percent(reps: Double(reps + rir)).map { e1RM * $0 / 100 }
    }
}

/// Load steps on a lattice through the last logged load (R2.5).
struct PowerJackSteps {
    var step: Double = PowerJackRules.stepPounds
    /// The last logged load. Nil puts the lattice on multiples of the step.
    var origin: Double?

    /// The highest lattice load at or below `value`, and at least one step.
    func roundDown(_ value: Double) -> Double {
        let base = origin ?? 0
        let steps = ((value - base) / step + 1e-9).rounded(.down)
        return max(step, base + steps * step)
    }

    /// The nearest lattice load, ties to the lower one.
    func roundNearest(_ value: Double) -> Double {
        let base = origin ?? 0
        let exact = (value - base) / step
        let lower = (exact + 1e-9).rounded(.down)
        let steps = exact - lower > 0.5 + 1e-9 ? lower + 1 : lower
        return max(step, base + steps * step)
    }

    /// No automatic rise passes max(10% over the best recent load, one step) (R2.5).
    func capped(_ load: Double, best: Double?) -> Double {
        guard let best, best > 0 else { return load }
        let limit = max(PowerJackSteps(step: step).roundDown(best * (1 + PowerJackRules.maxJumpPct / 100)), best + step)
        return min(load, limit)
    }
}

extension Double {
    /// Half up, as the rulebook's `round_half_up`.
    var roundedHalfUp: Int { Int((self + 1e-9).rounded(.toNearestOrAwayFromZero)) }
}
