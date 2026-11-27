import Foundation

/// What a search asks for. Exercise names are read the same way, so "Pull-Ups",
/// "pullups" and "pull ups" compare as the same lift.
nonisolated struct ExerciseQuery: Hashable, Sendable {
    let words: [String]
    let equipment: Set<Equipment>
    let muscles: Set<Muscle>
    /// Joint movements the query names in lifter words, such as "rear delts".
    let movements: Set<String>

    var isEmpty: Bool { words.isEmpty }

    /// The words a lift name should contain. Equipment is a preference, not part of the name,
    /// unless the query names nothing else.
    var nameWords: [String] {
        let rest = words.filter { Self.equipmentWords[$0] == nil }
        return rest.isEmpty ? words : rest
    }

    init(_ text: String) {
        words = Self.words(text)
        equipment = Set(words.compactMap { Self.equipmentWords[$0] })
        muscles = Set(words.compactMap { Self.muscleWords[$0] })
        movements = Self.movements(in: words)
    }

    /// The one reader for names and queries: folded case and accents, camel case split,
    /// shorthand spelled out, singular words, no filler words.
    static func words(_ text: String) -> [String] {
        var separated = ""
        var afterLowercase = false
        for character in text {
            if afterLowercase && character.isUppercase { separated.append(" ") }
            separated.append(character)
            afterLowercase = character.isLowercase
        }
        let tokens = separated.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return expandShorthand(tokens).map(singular).filter { !fillerWords.contains($0) }
    }

    // MARK: - Vocabulary

    /// Shorthand lifters type, longest phrase first so "ez bar" isn't read as "ez".
    private static let shorthand: [(from: [String], to: [String])] = [
        (["hex", "bar"], ["trap", "bar"]), (["pec", "deck"], ["chest", "fly"]), (["ez", "bar"], ["ez", "bar"]),
        (["db"], ["dumbbell"]), (["bb"], ["barbell"]), (["kb"], ["kettlebell"]), (["ez"], ["ez", "bar"]),
        (["rdl"], ["romanian", "deadlift"]), (["rdls"], ["romanian", "deadlift"]),
        (["sldl"], ["stiff", "leg", "deadlift"]), (["ohp"], ["overhead", "press"]), (["military"], ["overhead"]),
        (["skullcrusher"], ["skull", "crusher"]), (["skullcrushers"], ["skull", "crusher"]), (["chins"], ["chin", "up"]),
    ]

    private static let fillerWords: Set<String> = [
        "a", "an", "and", "the", "for", "with", "on", "in", "of", "to", "my", "i", "do", "did", "what", "some",
        "exercise", "workout",
    ]

    private static let equipmentWords: [String: Equipment] = [
        "barbell": .barbell, "dumbbell": .dumbbell, "kettlebell": .kettlebell,
        "cable": .cable, "machine": .machine, "bodyweight": .bodyweight,
    ]

    static let muscleWords: [String: Muscle] = [
        "chest": .chest, "pec": .chest, "shoulder": .shoulders, "delt": .shoulders, "back": .back, "lat": .back,
        "biceps": .biceps, "bicep": .biceps, "triceps": .triceps, "tricep": .triceps, "ab": .abs,
        "oblique": .obliques, "forearm": .forearms, "quad": .quads, "glute": .glutes, "calf": .calves,
        "hamstring": .hamstrings, "ham": .hamstrings,
    ]

    /// Lifter phrases of up to 3 words that name joint movements (`JointAnatomy.movements(forTerm:)`).
    private static func movements(in words: [String]) -> Set<String> {
        var found = Set<String>()
        for length in 1...3 where length <= words.count {
            for start in 0...(words.count - length) {
                found.formUnion(JointAnatomy.bundled.movements(forTerm: words[start..<start + length].joined(separator: " ")))
            }
        }
        return found
    }

    private static func expandShorthand(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < tokens.count {
            if let rule = shorthand.first(where: { rule in
                index + rule.from.count <= tokens.count && Array(tokens[index..<index + rule.from.count]) == rule.from
            }) {
                result += rule.to
                index += rule.from.count
            } else {
                result.append(tokens[index])
                index += 1
            }
        }
        return result
    }

    private static func singular(_ word: String) -> String {
        switch word {
        case "ups": return "up"
        case "abs": return "ab"
        case "calves": return "calf"
        default: break
        }
        guard word.count > 3, Double(word) == nil else { return word }
        if word.hasSuffix("sses") || word.hasSuffix("ches") || word.hasSuffix("shes") { return String(word.dropLast(2)) }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("s") && !word.hasSuffix("ss") && !word.hasSuffix("us") && !word.hasSuffix("ceps") {
            return String(word.dropLast())
        }
        return word
    }
}
