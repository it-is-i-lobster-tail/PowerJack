//
//  SetReferee.swift
//  PowerJack
//
//  Decides whose log of a set stands when the iPhone and the watch both logged it.
//  Together, the iPhone referees: the first log wins, a log at the same moment goes to the
//  iPhone, and fixing a set that was already logged wins over a plain log. Apart, through
//  iCloud, the latest log wins, judged by when it was logged rather than when it uploaded.
//

import Foundation

/// One device's log of a set.
struct SetLog: Codable, Equatable {
    var weightTenthsPounds: Int?
    var reps: Int?
    var completedAt: Date
    /// The set was already logged when this log was made, so it fixes the weight or reps.
    var isCorrection = false

    /// Logs this close together count as made at the same time.
    static let sameMoment: TimeInterval = 2

    func holdsSameValues(as other: SetLog) -> Bool {
        weightTenthsPounds == other.weightTenthsPounds && reps == other.reps
    }
}

enum SetReferee {
    enum Winner: Equatable {
        case iPhone
        case watch
    }

    /// Whose log the set keeps when the watch's log reaches an iPhone that may have logged it too.
    /// - Parameter together: whether the watch could reach the iPhone when it logged. A log made apart
    ///   follows the iCloud rule, even when it reaches the iPhone directly.
    static func winner(iPhone: SetLog?, watch: SetLog, together: Bool = true) -> Winner {
        guard let iPhone else { return .watch }
        // The same weight and reps: nothing to change.
        if iPhone.holdsSameValues(as: watch) { return .iPhone }
        guard together else {
            return watch.completedAt.timeIntervalSince(iPhone.completedAt) > SetLog.sameMoment ? .watch : .iPhone
        }

        switch (iPhone.isCorrection, watch.isCorrection) {
        case (true, false): return .iPhone
        case (false, true): return .watch
        case (true, true):
            // Two fixes: the later one stands.
            return watch.completedAt.timeIntervalSince(iPhone.completedAt) > SetLog.sameMoment ? .watch : .iPhone
        case (false, false):
            // Two first logs: the earlier one stands.
            return iPhone.completedAt.timeIntervalSince(watch.completedAt) > SetLog.sameMoment ? .watch : .iPhone
        }
    }

    /// Apart: the log made last, whichever device made it and whenever it uploaded.
    static func latest(_ logs: [SetLog]) -> SetLog? {
        logs.max { $0.completedAt < $1.completedAt }
    }
}
