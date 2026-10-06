//
//  RestTimerHint.swift
//  PowerJack
//

import SwiftUI
import TipKit

/// Points at the rest timer the first time it appears in a hint workout.
struct RestTimerHint: Hint {
    let occasion: HintOccasion?

    var title: Text { Text("Tap for your next set") }
    var message: Text? { Text("The timer is on your Lock Screen too.") }
    // Once per occasion, not on every rest.
    var options: [any TipOption] { [MaxDisplayCount(1)] }
}
