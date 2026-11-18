//
//  SupersetHint.swift
//  PowerJack
//

import SwiftUI

/// Shown in the template builder once a day has two exercises, until the lifter makes a superset.
struct SupersetHint: Hint {
    var title: Text { Text("Swipe an exercise either way to superset it.") }
    var message: Text? { Text("You'll do one set of each in turn, then rest.") }
}
