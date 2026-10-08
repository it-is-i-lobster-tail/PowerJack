//
//  TemplatesHint.swift
//  PowerJack
//

import SwiftUI

/// Shown at the top of Templates until the lifter opens one.
struct TemplatesHint: Hint {
    var title: Text { Text("Templates define a plan for what exercises to perform on what day.") }
    var message: Text? { Text("You can edit these or make your own. Use templates to build a program.") }
}
