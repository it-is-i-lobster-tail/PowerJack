//
//  LogSetHint.swift
//  PowerJack
//

import SwiftUI

/// Shown above the sets until the workout's first set is done.
struct LogSetHint: Hint {
    let occasion: HintOccasion?

    var title: Text { Text("Enter weight and reps") }
    var message: Text? { Text("The set checks itself off and starts your rest.") }
}

extension EnvironmentValues {
    /// Set by the workout screen; the exercise the lifter starts with shows it.
    @Entry var logSetHint: LogSetHint? = nil
}
