//
//  CompleteSetIntent+Widget.swift
//  PowerJackWidgets
//

import AppIntents

extension CompleteSetIntent {
    /// Never called: iOS runs Live Activity intents in the app (see CompleteSetIntent+App.swift).
    func perform() async throws -> some IntentResult {
        .result()
    }
}
