//
//  Collection+Active.swift
//  PowerJack
//
//  Created by Codex on 7/17/26.
//

import OSLog

extension Collection where Element: StatusProviding {
    /// The collection's active element, or `nil` when no element is active.
    ///
    /// A collection is expected to contain at most one active element. If sync ever
    /// produces two, the first one wins.
    var active: Element? {
        var activeElement: Element?

        for element in self where element.status == .active {
            guard activeElement == nil else {
                // Two devices can each start one while offline. Keep the first instead of crashing.
                Logger.persistence.warning("Found more than one active \(Element.self); using the first.")
                return activeElement
            }

            activeElement = element
        }

        return activeElement
    }
}
