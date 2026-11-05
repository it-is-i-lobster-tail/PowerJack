//
//  SyncMerge.swift
//  PowerJack
//
//  Folds one copy of a row into another, child by child, so nothing either copy holds is lost.
//

import Foundation

/// How a row's children find their match in the other copy.
nonisolated enum SyncMatch {
    /// Two copies of the same row: children match by sync ID.
    case syncID
    /// The same day planned on two devices: children match by their place in it.
    case place
}

enum SyncMerge {
    /// Folds `others` into `rows`: each one with a match merges into it, the rest move over.
    static func fold<Row: AnyObject>(
        _ others: [Row],
        into rows: [Row],
        key: (Row) -> AnyHashable?,
        merge: (Row, Row) -> Void,
        move: (Row) -> Void
    ) {
        var byKey: [AnyHashable: Row] = [:]
        for row in rows {
            if let key = key(row), byKey[key] == nil { byKey[key] = row }
        }
        for other in others {
            if let key = key(other), let match = byKey[key] {
                merge(match, other)
            } else {
                move(other)
            }
        }
    }
}
