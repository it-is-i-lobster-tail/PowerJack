//
//  StrengthEstimate.swift
//  PowerJack
//
//  Each lift's estimated one-rep max (module 4): one smoothed value, updated once a week
//  from rated sets with at most 10 reps to failure.
//

import Foundation

enum StrengthEstimate {
    /// A session's e1RM and, for ratings of 4 or 5+, the lower bound it gives instead (4.1).
    struct SessionValue: Equatable {
        var e1rmKg: Double?
        var boundKg: Double?
        /// The value came from a rating, so it counts toward `e1rmConf` (4.5).
        var isRated: Bool
    }

    static func value(of session: StrengthSession, curve: StrengthCurve) -> SessionValue {
        guard !session.plan.kind.isLight, !session.isPainful else {
            return SessionValue(isRated: false)
        }
        if let rated = session.ratedSet, let reps = rated.reps, let load = rated.loadKg, load > 0 {
            let assumed = session.plan.kind == .calibration ? session.plan.rir : nil
            if let rir = session.rir ?? assumed {
                let n = reps + rir
                let isRated = session.rir != nil
                if n <= StrengthRules.e1rmMaxReps {
                    if rir <= StrengthRules.e1rmMaxRIR {
                        return SessionValue(e1rmKg: curve.oneRepMax(loadKg: load, repsToFailure: n), isRated: isRated)
                    }
                    let bound = curve.oneRepMax(loadKg: load, repsToFailure: n)
                    return SessionValue(e1rmKg: missValue(session, curve: curve), boundKg: bound, isRated: isRated)
                }
            }
        }
        return SessionValue(e1rmKg: missValue(session, curve: curve), isRated: false)
    }

    /// Without a usable rating, the short set with the highest load ÷ pct(reps), at RIR 0.
    private static func missValue(_ session: StrengthSession, curve: StrengthCurve) -> Double? {
        session.missedSets.compactMap { set -> Double? in
            guard let reps = set.reps, reps <= StrengthRules.e1rmMaxReps, let load = set.loadKg, load > 0 else {
                return nil
            }
            return curve.oneRepMax(loadKg: load, repsToFailure: reps)
        }.max()
    }

    /// Folds a week's sessions of one lift into its record (4.1-4.5). Returns the weekly value, if any.
    @discardableResult
    static func update(
        _ record: inout StrengthLiftRecord,
        with sessions: [StrengthSession],
        curve: StrengthCurve,
        calibrating: Bool
    ) -> Double? {
        let values = sessions.map { value(of: $0, curve: curve) }
        for (session, value) in zip(sessions, values) where value.isRated && (value.e1rmKg != nil || value.boundKg != nil) {
            if let date = session.date { record.ratedDates.append(date) }
        }
        if let newest = record.ratedDates.max() {
            let start = newest.addingTimeInterval(-Double(StrengthRules.confidenceWindowDays) * 86_400)
            record.ratedDates.removeAll { $0 <= start }
        }

        let weekly = median(values.compactMap(\.e1rmKg))
        let bound = values.compactMap(\.boundKg).max()
        let fast = calibrating || record.fastUpdatesLeft > 0
        let alpha = fast ? StrengthRules.alphaFast : StrengthRules.alpha

        if let weekly {
            smooth(&record, toward: weekly, alpha: alpha, checksOutliers: !calibrating)
        }
        // Bounds are smoothed like weekly values, but only ever raise the estimate (adopted fix 1).
        if let bound, bound > (record.e1rmKg ?? 0) {
            smooth(&record, toward: bound, alpha: alpha, checksOutliers: false)
        }
        if (weekly != nil || bound != nil), record.fastUpdatesLeft > 0 {
            record.fastUpdatesLeft -= 1
        }
        return weekly
    }

    private static func smooth(_ record: inout StrengthLiftRecord, toward value: Double, alpha: Double, checksOutliers: Bool) {
        guard let current = record.e1rmKg else {
            record.e1rmKg = value
            return
        }
        guard checksOutliers else {
            record.e1rmKg = current + alpha * (value - current)
            return
        }
        // A jump of over 12% waits a week; a value within 5% of it next week confirms both (4.3).
        if let suspect = record.suspectKg {
            record.suspectKg = nil
            if abs(value - suspect) <= StrengthRules.outlierConfirmShare * suspect {
                let confirmed = current + alpha * (suspect - current)
                record.e1rmKg = confirmed + alpha * (value - confirmed)
                return
            }
        }
        if abs(value - current) > StrengthRules.outlierShare * current {
            record.suspectKg = value
            return
        }
        record.e1rmKg = current + alpha * (value - current)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
