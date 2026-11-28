import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import PowerJack

@MainActor
struct SpellingCorrectionTests {
    private let names = ["Barbell Back Squat", "Barbell Bench Press", "Zercher Squat", "Romanian Deadlift"]

    private func search(_ text: String) -> [String] {
        let words = text.lowercased().split(separator: " ")
        guard !words.isEmpty else { return names }
        return names.filter { name in words.allSatisfy { name.lowercased().contains($0) } }
    }

    private func catalogSearch(_ text: String) -> [ExerciseCatalog.Entry] {
        MovesLike.index.rank(ExerciseQuery(text)).compactMap { MovesLike.entry($0.key) }
    }

    @Test("A misspelled word is replaced by a guess that finds something")
    func misspelledWordIsCorrected() {
        #expect(SpellingCorrection.correct("squatt", vocabulary: names) { !search($0).isEmpty } == "squat")
        #expect(SpellingCorrection.correct("benchh press", vocabulary: names) { !search($0).isEmpty } == "bench press")
    }

    @Test("Correctly spelled words and vocabulary words are left alone")
    func correctWordsAreUntouched() {
        #expect(SpellingCorrection.correct("squat", vocabulary: names) { _ in true } == nil)
        // A lifter's own exercise names count as spelled right, such as "Zercher" or "JM Press".
        #expect(SpellingCorrection.correct("Zercher", vocabulary: names) { _ in true } == nil)
        #expect(SpellingCorrection.correct("jm press", vocabulary: names + ["JM Press"]) { _ in true } == nil)
        #expect(SpellingCorrection.correct("   ", vocabulary: names) { _ in true } == nil)
    }

    @Test("No correction is offered when no fix finds anything")
    func fixThatFindsNothingIsDropped() {
        #expect(SpellingCorrection.correct("squatt", vocabulary: names) { _ in false } == nil)
    }

    @Test("A search with no results shows the results for its spelling fix")
    func zeroResultFallback() {
        let found = SpellingCorrection.results(for: "benchh", vocabulary: { names }, isEmpty: \.isEmpty, search: search)
        #expect(found.correction == "bench")
        #expect(found.results == ["Barbell Bench Press"])
    }

    @Test("A search with results is never corrected")
    func existingResultsAreKept() {
        var askedForVocabulary = false
        let found = SpellingCorrection.results(for: "zerch", vocabulary: { askedForVocabulary = true; return names },
                                               isEmpty: \.isEmpty, search: search)
        #expect(found.correction == nil)
        #expect(found.results == ["Zercher Squat"])
        #expect(!askedForVocabulary)
    }

    @Test("Lift names the dictionary doesn't know still find their exercise", arguments: ["RDL", "hack squat", "skull crusher"])
    func jargonFindsItsExercise(_ text: String) {
        let found = SpellingCorrection.results(for: text, vocabulary: { ExerciseCatalog.entries.map(\.name) },
                                               isEmpty: \.isEmpty, search: catalogSearch)
        #expect(found.correction == nil)
        #expect(!found.results.isEmpty)
    }

    @Test("The chart search field leaves autocorrect and spell checking on")
    func chartSearchFieldAutocorrects() async throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let screen = try await HostedView(ProgramDataView().modelContainer(container))
        defer { screen.close() }
        func fields(in view: UIView) -> [UITextField] {
            ((view as? UITextField).map { [$0] } ?? []) + view.subviews.flatMap(fields)
        }
        let field = try #require(fields(in: screen.window).first { $0.placeholder == "Search charts" })
        #expect(field.autocorrectionType != .no)
        #expect(field.spellCheckingType != .no)
    }
}
