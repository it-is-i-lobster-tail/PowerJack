//
//  SupersetHint.swift
//  PowerJack
//

import SwiftUI

/// Shown in the template builder once a day has two exercises, until the lifter makes a superset.
struct SupersetHint: Hint {
    var title: Text { Text("Drag one exercise onto another to superset them.") }
    var message: Text? { Text("Drag on as many as you like. You'll do one set of each in turn, then rest.") }
}
