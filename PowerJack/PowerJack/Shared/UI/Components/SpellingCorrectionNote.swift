//
//  SpellingCorrectionNote.swift
//  PowerJack
//
//  The quiet line above results found for a search's spelling fix.
//

import SwiftUI

struct SpellingCorrectionNote: View {
    let correction: String

    var body: some View {
        Text("Showing results for \u{201C}\(correction)\u{201D}")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .accessibilityIdentifier("search.correction")
    }
}

#Preview {
    SpellingCorrectionNote(correction: "bench press")
}
