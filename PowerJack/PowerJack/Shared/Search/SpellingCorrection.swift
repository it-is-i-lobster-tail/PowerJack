//
//  SpellingCorrection.swift
//  PowerJack
//
//  When a search finds nothing, try it again with its misspelled words fixed.
//

import UIKit

/// Fixes the spelling of a search that found nothing, so "benchh" still finds Bench Press.
///
/// It only runs when the search as typed has no results, so a correct name the dictionary
/// doesn't know, such as "Zercher" or "RDL", is never second-guessed. It never changes the
/// text in the field: the screen shows results for the fix with a "Showing results for" line.
enum SpellingCorrection {
    /// Guesses tried for each misspelled word, best first.
    private static let guessesPerWord = 4

    /// Results for `query`, or for its spelling fix when the query as typed finds nothing.
    /// `correction` is the fixed query, or nil when the results are for what was typed.
    static func results<Results>(for query: String, vocabulary: () -> [String],
                                 isEmpty: (Results) -> Bool,
                                 search: (String) -> Results) -> (results: Results, correction: String?) {
        let typed = search(query)
        guard isEmpty(typed),
              let fixed = correct(query, vocabulary: vocabulary(), finds: { !isEmpty(search($0)) })
        else { return (typed, nil) }
        return (search(fixed), fixed)
    }

    /// `query` with its misspelled words replaced, or nil when nothing is misspelled or no fix finds anything.
    /// Words in `vocabulary`, such as exercise names, count as spelled right, and guesses
    /// that are vocabulary words are tried first.
    static func correct(_ query: String, vocabulary: [String], finds: (String) -> Bool) -> String? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let known = Set(vocabulary.flatMap(words).map { $0.lowercased() })
        let checker = UITextChecker()
        let language = "en"

        // Find the misspelled words first; fix them from the end so earlier ranges stay valid.
        var misspelled: [NSRange] = []
        var start = 0
        let length = (text as NSString).length
        while start < length {
            let range = checker.rangeOfMisspelledWord(in: text, range: NSRange(location: 0, length: length),
                                                      startingAt: start, wrap: false, language: language)
            guard range.location != NSNotFound else { break }
            if !known.contains((text as NSString).substring(with: range).lowercased()) {
                misspelled.append(range)
            }
            start = range.location + range.length
        }
        guard !misspelled.isEmpty else { return nil }

        var fixed = text
        for range in misspelled.reversed() {
            let word = (fixed as NSString).substring(with: range)
            // A capitalized guess for a lowercase word is a place or a name, such as "Delft" for "dedlfit".
            let guesses = (checker.guesses(forWordRange: range, in: fixed, language: language) ?? [])
                .filter { word.first?.isUppercase == true || $0.first?.isUppercase != true }
                .prefix(guessesPerWord)
            let ranked = guesses.filter { known.contains($0.lowercased()) } + guesses.filter { !known.contains($0.lowercased()) }
            let candidates = ranked.map { (fixed as NSString).replacingCharacters(in: range, with: $0) }
            // Prefer the first guess that finds something; otherwise keep the best guess so later words can still help.
            if let chosen = candidates.first(where: finds) ?? candidates.first {
                fixed = chosen
            }
        }
        return fixed != text && finds(fixed) ? fixed : nil
    }

    private static func words(_ name: String) -> [String] {
        name.split { !$0.isLetter }.map(String.init)
    }
}
