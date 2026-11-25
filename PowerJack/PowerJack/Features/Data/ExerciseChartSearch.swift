import Foundation
import SwiftData

nonisolated struct ExerciseChartSearch: Sendable {
    let ranks: [PersistentIdentifier: Int]
    let muscles: Set<Muscle>
    // Literal matches have one rank per tier. Semantic matches also encode
    // distance within the tier so pickers can weigh close matches against the source.
    var ranksPerTier = 1

    /// Take value snapshots on the store's actor. Indexing never retains SwiftData objects.
    struct Document: Hashable, Sendable {
        let id: PersistentIdentifier
        let names: [String]
        let primary: Muscle
        let secondary: [Muscle]
        let equipment: Equipment
        let pattern: String?
        let style: String
        let actions: [String]

        @MainActor private static let catalog = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ($0.id, $0) })

        @MainActor init(_ exercise: Exercise) {
            let entry = exercise.catalogID.flatMap { Self.catalog[$0] }
            id = exercise.persistentModelID
            names = [exercise.exerciseName, entry?.name].compactMap { $0 }
            primary = exercise.primaryMuscleFocus
            secondary = exercise.secondaryMuscles
            equipment = exercise.equipment
            pattern = exercise.movementPattern?.rawValue ?? entry?.profile.pattern.rawValue
            style = exercise.executionStyle?.rawValue ?? entry?.profile.style.rawValue ?? ""
            actions = (exercise.jointActions ?? []).compactMap { action in
                guard let key = action.movement?.key else { return nil }
                return action.role.rawValue + " " + key
            }.sorted()
        }
    }

    struct Index: Sendable {
        private struct Entry: Sendable {
            let document: Document
            let names: [[String]]
            let fields: [[String]]
            let vector: [Float]
            let mechanics: [Float]
        }

        private struct ScoredEntry {
            let entry: Entry
            let identity: Float
            let mechanics: Float
            var score: Float { max(identity, mechanics) }
        }

        private let entries: [Entry]
        private let encoder: ExerciseTextEncoder?
        private let topics: [AnatomyTopic]

        init(_ documents: [Document], encoder: ExerciseTextEncoder? = .bundled) {
            self.encoder = encoder
            topics = AnatomyTopic.index(using: encoder)
            entries = documents.map { document in
                let names = document.names.map(words)
                let pattern = words(document.pattern ?? "")
                let muscles = ([document.primary] + document.secondary).map { words($0.rawValue) }
                let actions = document.actions.map(words)
                let girdleActions = document.actions.filter { $0.contains("scapula.") }
                    .map { words($0.replacingOccurrences(of: "scapula.", with: "shoulder girdle ")) }
                let fields = [pattern + words(document.primary.rawValue), words(document.style), words(document.equipment.displayName)]
                    + muscles + actions + girdleActions
                // Repeating "press" across the name, equipment and pattern would give
                // that word extra weight solely because of how the catalog is stored.
                var seen = Set<String>()
                let description = (names.flatMap { $0 } + words(document.primary.rawValue) + pattern + words(document.equipment.displayName))
                    .filter { seen.insert($0).inserted }.joined(separator: " ")
                let mechanics = (pattern + words(document.style) + actions.flatMap { $0 }).joined(separator: " ")
                return Entry(document: document, names: names, fields: fields, vector: encoder?.vector(for: description) ?? [],
                             mechanics: encoder?.vector(for: mechanics) ?? [])
            }
        }

        func results(for query: String) -> ExerciseChartSearch? {
            let terms = words(query)
            guard !terms.isEmpty else { return nil }
            // Recognized equipment constrains both literal matches and related lifts.
            let equipment = Equipment.allCases.filter { item in
                let label = item.displayName.lowercased()
                return terms.count > 1 && terms.contains { $0 == label || $0 == label + "s" }
            }
            let candidates = equipment.isEmpty ? entries : entries.filter { equipment.contains($0.document.equipment) }
            let meaning = terms.filter { term in
                !equipment.contains { term == $0.displayName.lowercased() || term == $0.displayName.lowercased() + "s" }
            }
            let subject = meaning.isEmpty ? terms : meaning
            let name = subject.joined(separator: " ")
            let namedFocus = topics.first { $0.labels.contains(name) }?.focus

            var ranks: [PersistentIdentifier: Int] = [:]
            var focus: Set<Muscle> = []
            var patterns: Set<String> = []
            var exactName = false
            for entry in candidates {
                let doc = entry.document
                if entry.names.contains(where: { matches($0, terms) }) {
                    let exact = entry.names.contains(terms)
                    exactName = exactName || exact
                    ranks[doc.id] = exact ? 0 : 1
                    if let pattern = doc.pattern { patterns.insert(pattern) }
                } else if entry.fields.contains(where: { matches($0, terms) }) {
                    ranks[doc.id] = 2
                } else {
                    continue
                }
                focus.insert(doc.primary)
                focus.formUnion(doc.secondary)
            }

            // An unambiguous lift name can expand to variants of the same movement.
            if patterns.count == 1, let family = patterns.first {
                for entry in candidates where entry.document.pattern == family && ranks[entry.document.id] == nil {
                    ranks[entry.document.id] = 3
                }
            }
            let lexical = ExerciseChartSearch(ranks: ranks, muscles: focus)
            if namedFocus == nil && (exactName || (!ranks.isEmpty && (patterns.count == 1 || terms.count > 1))) { return lexical }
            // Opposite joint-action roles are semantically close but describe different work.
            if terms.contains(JointActionRole.produces.rawValue) || terms.contains(JointActionRole.resists.rawValue) { return lexical }
            if namedFocus == nil && (encoder == nil || query.count < 3) { return lexical }

            let phrase = encoder.map { SearchPhrase(terms: subject, encoder: $0) }
            let scored = candidates.map { entry in
                ScoredEntry(entry: entry, identity: phrase?.similarity(to: entry.vector) ?? 0,
                            mechanics: 0.9 * (phrase?.similarity(to: entry.mechanics) ?? 0))
            }
            let bestLift = scored.map(\.score).max() ?? 0
            let cutoff = max(0.42, bestLift - 0.10)
            if let anatomy = namedFocus ?? phrase.flatMap({ AnatomyTopic.focus(for: $0, topics: topics, bestLift: bestLift) }) {
                return muscleResults(anatomy, scored: scored, cutoff: cutoff)
            }
            if !ranks.isEmpty { return lexical }
            // An unrelated phrase should still have an empty state. Keep the best
            // semantic neighbors within a margin so a focused query stays focused.
            for match in scored where match.score >= cutoff {
                ranks[match.entry.document.id] = Int((1 - match.score) * 1000)
                focus.insert(match.entry.document.primary)
            }
            return ExerciseChartSearch(ranks: ranks, muscles: focus, ranksPerTier: 1000)
        }

        /// How well each lift can stand in for the source. A shared muscle or movement
        /// anchors the comparison even when a custom exercise has no mechanics profile.
        func relatedness(to id: PersistentIdentifier) -> [PersistentIdentifier: Float] {
            guard let source = entries.first(where: { $0.document.id == id }) else { return [:] }
            let original = source.document
            var scores: [PersistentIdentifier: Float] = [:]
            for entry in entries where entry.document.id != id {
                let candidate = entry.document
                let sameMuscle = original.primary == candidate.primary
                let samePattern = original.pattern != nil && original.pattern == candidate.pattern
                let assists = candidate.secondary.contains(original.primary) || original.secondary.contains(candidate.primary)
                guard sameMuscle || samePattern || assists else { continue }

                var score: Float = sameMuscle ? 4 : 0
                if samePattern { score += 3 }
                score += ExerciseTextEncoder.similarity(source.mechanics, entry.mechanics)
                score += ExerciseTextEncoder.similarity(source.vector, entry.vector)
                scores[candidate.id] = score
            }
            return scores
        }

        private func muscleResults(_ focus: AnatomyTopic.Focus, scored: [ScoredEntry], cutoff: Float) -> ExerciseChartSearch {
            let surroundingMuscles = Set(topics.filter { $0.focus.muscles.isSuperset(of: focus.muscles) }
                .flatMap { $0.focus.muscles })
            var ranks: [PersistentIdentifier: Int] = [:]
            for match in scored {
                let doc = match.entry.document
                let tier: Int
                if focus.emphasis.contains(doc.primary) {
                    tier = 0
                } else if focus.muscles.contains(doc.primary) {
                    tier = 1
                } else if !focus.muscles.isDisjoint(with: doc.secondary) {
                    tier = 2
                } else {
                    // Outside the surrounding body region, require both the exercise
                    // description and its mechanics to support a related result.
                    let evidence = surroundingMuscles.contains(doc.primary) ? match.score : min(match.identity, match.mechanics)
                    guard evidence >= cutoff else { continue }
                    tier = 3
                }
                let similarity = min(1, max(0, match.score))
                ranks[doc.id] = tier * 1000 + Int((1 - similarity) * 999)
            }
            return ExerciseChartSearch(ranks: ranks, muscles: ranks.isEmpty ? [] : focus.muscles, ranksPerTier: 1000)
        }
    }

    private static func matches(_ tokens: [String], _ terms: [String]) -> Bool {
        if terms.count == 1, let term = terms.first, term.count >= 4 {
            if tokens.indices.contains(where: { tokens[$0...].joined().hasPrefix(term) }) { return true }
        }
        return terms.allSatisfy { term in
            tokens.contains { token in
                token.hasPrefix(term) || (term.hasSuffix("s") && (term == token + "s" || term == token + "es"))
            }
        }
    }

    private static func words(_ text: String) -> [String] {
        var separated = ""
        var afterLowercase = false
        for character in text {
            if afterLowercase && character.isUppercase { separated.append(" ") }
            separated.append(character)
            afterLowercase = character.isLowercase
        }
        return separated.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

/// A short phrase inside a longer question can carry more meaning than the
/// question as a whole. The full query wins ties with its component phrases.
private nonisolated struct SearchPhrase {
    let full: [Float]
    let parts: [[Float]]

    init(terms: [String], encoder: ExerciseTextEncoder) {
        full = encoder.vector(for: terms.joined(separator: " "))
        if (5...16).contains(terms.count) {
            parts = terms.indices.dropFirst().map { encoder.vector(for: terms[($0 - 1)...$0].joined(separator: " ")) }
        } else {
            parts = []
        }
    }

    func similarity(to vector: [Float]) -> Float {
        parts.reduce(ExerciseTextEncoder.similarity(full, vector)) { best, part in
            max(best, 0.97 * ExerciseTextEncoder.similarity(part, vector))
        }
    }
}

/// Catalog anatomy, indexed alongside exercises. Queries are embedded against
/// these descriptions so the same region can be found using unfamiliar wording.
private nonisolated struct AnatomyTopic: Sendable {
    struct Focus: Sendable {
        let muscles: Set<Muscle>
        let emphasis: Set<Muscle>
    }

    let labels: Set<String>
    let focus: Focus
    let vectors: [[Float]]

    static func index(using encoder: ExerciseTextEncoder?) -> [Self] {
        guard let url = Bundle.main.url(forResource: "MuscleAnatomy", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Anatomy.self, from: data) else { return [] }
        let regions = catalog.regions.map { region in
            let members = Set(catalog.muscles.filter { $0.regions.contains(region.id) }.map(\.muscle))
            let focus = Focus(muscles: members, emphasis: region.emphasis ?? members)
            return Self(labels: [region.name.lowercased(), region.id.lowercased()], focus: focus,
                        vectors: encoder.map { [region.name, region.description].map($0.vector) } ?? [])
        }
        return regions + catalog.muscles.map { entry in
            Self(labels: [entry.muscle.rawValue], focus: Focus(muscles: [entry.muscle], emphasis: [entry.muscle]),
                 vectors: encoder.map { [entry.muscle.rawValue, entry.description].map($0.vector) } ?? [])
        }
    }

    private struct Anatomy: Decodable {
        struct Region: Decodable {
            let id, name, description: String
            let emphasis: Set<Muscle>?
        }
        struct Group: Decodable {
            let muscle: Muscle
            let regions: [String]
            let description: String
        }

        let regions: [Region]
        let muscles: [Group]
    }

    static func focus(for query: SearchPhrase, topics: [Self], bestLift: Float) -> Focus? {
        let scores = topics.map { topic in
            (topic, topic.vectors.map(query.similarity).max() ?? 0)
        }
        let best = scores.map(\.1).max() ?? 0
        if let (region, score) = scores.filter({ $0.0.focus.muscles.count > 1 }).max(by: { $0.1 < $1.1 }),
           score >= 0.49, score >= best - 0.12, score >= bestLift - 0.16 {
            return region.focus
        }
        guard best >= 0.49, best >= bestLift - 0.08 else { return nil }
        let matches = scores.filter { $0.0.focus.muscles.count == 1 && $0.1 >= best - 0.07 }
        let muscles = Set(matches.flatMap { $0.0.focus.muscles })
        return muscles.isEmpty ? nil : Focus(muscles: muscles, emphasis: muscles)
    }
}
