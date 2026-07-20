//
//  Collection+Active.swift
//  PowerJack
//
//  Created by Codex on 7/17/26.
//

extension Collection where Element: StatusProviding {
    /// The collection's active element, or `nil` when no element is active.
    ///
    /// A collection is expected to contain at most one active element.
    var active: Element? {
        var activeElement: Element?

        for element in self where element.status == .active {
            guard activeElement == nil else {
                assertionFailure("Expected at most one active \(Element.self).")
                return activeElement
            }

            activeElement = element
        }

        return activeElement
    }
}
