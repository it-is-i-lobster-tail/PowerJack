//
//  Array+OrderedModel.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import Foundation
import SwiftData
import SwiftUI

protocol OrderedModel: AnyObject {
    var order: Int { get set }
}

extension Array where Element: OrderedModel {
    mutating func moveAndReorder(from source: IndexSet, to destination: Int) {
        guard destination >= 0, destination <= count else { return }
        guard source.allSatisfy({ indices.contains($0) }) else { return }

        move(fromOffsets: source, toOffset: destination)

        for (index, item) in enumerated() {
            item.order = index
        }
    }
}

extension Sequence where Element: PersistentModel {
    /// Sorts by `order`. Ties fall back to the model's identity so the list stays stable
    /// when two devices reorder the same children at once.
    func sorted(byOrder order: (Element) -> Int) -> [Element] {
        sorted { lhs, rhs in
            let lhsOrder = order(lhs)
            let rhsOrder = order(rhs)
            return lhsOrder != rhsOrder
                ? lhsOrder < rhsOrder
                : lhs.persistentModelID < rhs.persistentModelID
        }
    }
}
