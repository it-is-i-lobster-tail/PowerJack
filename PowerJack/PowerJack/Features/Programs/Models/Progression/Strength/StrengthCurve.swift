//
//  StrengthCurve.swift
//  PowerJack
//
//  The share of a one-rep max at which the average lifter fails after n reps (rule 4.7).
//

import Foundation

enum StrengthCurve: String, Codable {
    /// Every lift except the flat bench press.
    case main
    case bench

    /// Rules only read n = 1-15 (reps + reps in reserve); anything outside is clamped.
    func share(repsToFailure n: Int) -> Double {
        let table = self == .bench ? Self.benchTable : Self.mainTable
        return table[min(max(n, 1), table.count) - 1]
    }

    /// Estimated one-rep max from a set: load ÷ pct(reps + RIR).
    func oneRepMax(loadKg: Double, repsToFailure n: Int) -> Double {
        loadKg / share(repsToFailure: n)
    }

    /// pct(n′) ÷ pct(n): how a load scales when reps to failure change (rule 9.3).
    func scale(from n: Int, to newN: Int) -> Double {
        share(repsToFailure: newN) / share(repsToFailure: n)
    }

    // From Nuzzo 2024a, n = 1...15.
    private static let mainTable = [
        1.000, 0.971, 0.954, 0.926, 0.898, 0.874, 0.853, 0.832, 0.813, 0.795, 0.775, 0.756, 0.736, 0.715, 0.695,
    ]
    private static let benchTable = [
        1.000, 0.964, 0.934, 0.903, 0.876, 0.855, 0.833, 0.814, 0.796, 0.776, 0.759, 0.740, 0.720, 0.701, 0.681,
    ]
}
