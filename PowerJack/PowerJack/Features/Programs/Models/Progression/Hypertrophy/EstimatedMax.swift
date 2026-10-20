//
//  EstimatedMax.swift
//  PowerJack
//
//  Estimated one-rep max from a set's load, reps and reps left (RIR-05).
//

import Foundation

/// Reps to failure at a share of one-rep max, from a pooled table of 6,970 lifters (AUTO-12),
/// joined by straight lines.
enum RepTable {
    private static let rows: [(reps: Double, fraction: Double)] = [
        (1, 1.0), (3.3, 0.95), (4.9, 0.90), (9.8, 0.80), (14.8, 0.70), (19.5, 0.60), (26.0, 0.50), (35.8, 0.40),
    ]

    /// The share of one-rep max a lifter can lift for `repsToFailure` reps, or nil past the table.
    static func fraction(repsToFailure reps: Double) -> Double? {
        for (low, high) in zip(rows, rows.dropFirst()) where reps >= low.reps && reps <= high.reps {
            let progress = (reps - low.reps) / (high.reps - low.reps)
            return low.fraction + progress * (high.fraction - low.fraction)
        }
        return nil
    }

    /// Reps to failure at `fraction` of one-rep max. Below 1 when the load is over the max, nil under the table.
    static func repsToFailure(fraction: Double) -> Double? {
        guard fraction >= rows[rows.count - 1].fraction else { return nil }
        let segments = Array(zip(rows, rows.dropFirst()))
        // Over the max, the first segment's slope carries on down to zero reps.
        let (low, high) = segments.first { fraction >= $0.1.fraction } ?? segments[0]
        let progress = (low.fraction - fraction) / (low.fraction - high.fraction)
        return max(0, low.reps + progress * (high.reps - low.reps))
    }
}

/// An estimated one-rep max, in tenths of a pound.
struct EstimatedMax: Equatable {
    let tenths: Double
    /// From a "5+" rating, so the real max is at least this.
    let isLowerBound: Bool

    init?(loadTenths: Int, reps: Int, repsInReserve: Int) {
        guard
            loadTenths > 0,
            reps > 0,
            let fraction = RepTable.fraction(repsToFailure: Double(reps + min(repsInReserve, 5)))
        else {
            return nil
        }
        tenths = Double(loadTenths) / fraction
        isLowerBound = repsInReserve >= 5
    }

    /// Reps to failure at `loadTenths`.
    func repsToFailure(atTenths loadTenths: Int) -> Double? {
        RepTable.repsToFailure(fraction: Double(loadTenths) / tenths)
    }

    /// Reps that leave `repsInReserve` on the last set at `loadTenths`, rounded with ties going down (LOAD-05).
    func reps(atTenths loadTenths: Int, leaving repsInReserve: Int) -> Int? {
        repsToFailure(atTenths: loadTenths).map { Int(($0 - Double(repsInReserve) - 0.5).rounded(.up)) }
    }

    /// The load, unrounded, that leaves `repsInReserve` after `reps`.
    func loadTenths(forReps reps: Int, leaving repsInReserve: Int) -> Double? {
        RepTable.fraction(repsToFailure: Double(reps + repsInReserve)).map { tenths * $0 }
    }
}
