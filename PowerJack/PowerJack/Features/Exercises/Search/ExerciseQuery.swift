import Foundation

/// What a search asks for. Exercise names are read the same way, so "Pull-Ups",
/// "pullups" and "pull ups" compare as the same lift.
nonisolated struct ExerciseQuery: Hashable, Sendable {
    let words: [String]
    private(set) var equipment: Set<Equipment>
    private(set) var muscles: Set<Muscle>
    /// Joint movements the query names in lifter words, such as "rear delts".
    private(set) var movements: Set<String>
    /// What the on-device model read a long search as, once `adding(_:)` merged it in.
    private(set) var filters: ExerciseFilters?

    var isEmpty: Bool { words.isEmpty }

    /// The query with the model's reading merged in. Excluded equipment and setups are left out
    /// of the results; muscles and movements rank by what lifts work rather than by their names.
    func adding(_ filters: ExerciseFilters) -> ExerciseQuery {
        var query = self
        query.muscles.formUnion(filters.muscles)
        query.movements.formUnion(filters.movements)
        query.equipment.formUnion(filters.includeEquipment)
        query.equipment.subtract(filters.excludeEquipment)
        query.filters = filters
        return query
    }

    /// What the search was read as, for the line above the results.
    var summary: String? { filters?.summary }

    /// True when the model's reading leaves this lift out.
    func excludes(equipment: Equipment, names: [[String]]) -> Bool {
        guard let filters else { return false }
        return filters.excludeEquipment.contains { $0.covers(equipment) }
            || filters.excludeSetups.contains { setup in names.contains(where: setup.isUsed) }
    }

    /// The words a lift name should contain. Equipment is a preference, not part of the name,
    /// unless the query names nothing else.
    var nameWords: [String] {
        let rest = words.filter { Self.equipmentWords[$0] == nil }
        return rest.isEmpty ? words : rest
    }

    /// The typed words each of `words` came from, as positions in the text's words or in the
    /// `tokens` the query was read from. Shorthand such as "hex bar" spans two.
    let sources: [Range<Int>]

    init(_ text: String) {
        self.init(read: Self.split(text).enumerated().map { (word: $0.element, source: $0.offset..<$0.offset + 1) })
    }

    /// A query read from words another reader has already split, such as the Data tab's search,
    /// so `sources` can say which of them a lift's words came from.
    init(tokens: [String]) {
        self.init(read: tokens.enumerated().flatMap { index, token in Self.split(token).map { (word: $0, source: index..<index + 1) } })
    }

    private init(read tokens: [(word: String, source: Range<Int>)]) {
        let read = Self.read(tokens)
        words = read.map(\.word)
        sources = read.map(\.source)
        equipment = Set(words.compactMap { Self.equipmentWords[$0] })
        muscles = Set(words.compactMap { Self.muscleWords[$0] })
        movements = Self.movements(in: words)
        filters = nil
    }

    /// The typed words behind a run of `words`.
    func source(of range: Range<Int>) -> Range<Int> {
        guard !range.isEmpty else { return 0..<0 }
        return sources[range.lowerBound].lowerBound..<sources[range.upperBound - 1].upperBound
    }

    /// The one reader for names and queries: folded case and accents, camel case split,
    /// shorthand spelled out, singular words, no filler words.
    static func words(_ text: String) -> [String] {
        read(split(text).map { (word: $0, source: 0..<0) }).map(\.word)
    }

    private static func split(_ text: String) -> [String] {
        var separated = ""
        var afterLowercase = false
        for character in text {
            if afterLowercase && character.isUppercase { separated.append(" ") }
            separated.append(character)
            afterLowercase = character.isLowercase
        }
        return separated.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func read(_ tokens: [(word: String, source: Range<Int>)]) -> [(word: String, source: Range<Int>)] {
        expandShorthand(tokens).map { (word: singular($0.word), source: $0.source) }.filter { !fillerWords.contains($0.word) }
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

    static let equipmentWords: [String: Equipment] = [
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

    private static func expandShorthand(_ tokens: [(word: String, source: Range<Int>)]) -> [(word: String, source: Range<Int>)] {
        let words = tokens.map(\.word)
        var result: [(word: String, source: Range<Int>)] = []
        var index = 0
        while index < tokens.count {
            if let rule = shorthand.first(where: { rule in
                index + rule.from.count <= words.count && Array(words[index..<index + rule.from.count]) == rule.from
            }) {
                let source = tokens[index].source.lowerBound..<tokens[index + rule.from.count - 1].source.upperBound
                result += rule.to.map { (word: $0, source: source) }
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
