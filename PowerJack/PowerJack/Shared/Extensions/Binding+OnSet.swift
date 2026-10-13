//
//  Binding+OnSet.swift
//  PowerJack
//

import SwiftUI

extension Binding {
    /// Runs `action` right after every write through this binding.
    ///
    /// Unlike `onChange`, this also runs for writes from a screen pushed over the owner,
    /// which SwiftUI may never get to if the user leaves with the section switcher.
    func onSet(_ action: @escaping () -> Void) -> Binding {
        Binding(
            get: { wrappedValue },
            set: { newValue, transaction in
                self.transaction(transaction).wrappedValue = newValue
                action()
            }
        )
    }
}
