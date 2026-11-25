//
//  TitleCaseTests.swift
//  PowerJackTests
//

import Testing
@testable import PowerJack

/// Names typed in title case: small words go lowercase once the next space is typed, other words don't change.
struct TitleCaseTests {
    /// Types `text` one character at a time, as the keyboard would, and returns what the field shows.
    private func type(_ text: String) -> String {
        var field = ""
        for character in text { field = TitleCase.typed(field + String(character), after: field) }
        return field
    }

    @Test func smallWordsGoLowercase() {
        #expect(type("Push Day Of The Week") == "Push Day of the Week")
        #expect(type("Squat To A Box") == "Squat to a Box")
    }

    @Test func firstWordKeepsItsCapital() {
        #expect(type("The Big Three") == "The Big Three")
        #expect(type("  A Lift") == "  A Lift")
    }

    @Test func lastWordKeepsItsCapital() {
        #expect(type("Rows On") == "Rows On")
    }

    @Test func wordsTypedOnPurposeStay() {
        #expect(type("Press OF Doom") == "Press OF Doom")
        #expect(type("easy pull") == "easy pull")
        #expect(type("Pull Ups Then Dips") == "Pull Ups Then Dips")
    }

    @Test func pastingOrDeletingChangesNothing() {
        #expect(TitleCase.typed("Curl On The Bench ", after: "") == "Curl On The Bench ")
        #expect(TitleCase.typed("Curl On", after: "Curl On ") == "Curl On")
    }
}
