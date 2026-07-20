//
//  Array+OrderedModel.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import Foundation
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
