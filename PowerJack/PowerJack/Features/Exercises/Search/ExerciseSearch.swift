import Foundation
import SwiftData

/// Ranks exercises for a query. Every lift gets one score: the sum of its evidence,
/// each 0 to 1, weighted for where the search runs.
/// - Name: the share of query words found in the lift's name. An exact name sorts first.
/// - Meaning: on-device word embeddings, or the muscles the query names.
/// - Structure: shared joint actions and muscles (`ExerciseStructure`) with the lift being replaced,
///   or with the joint movements the query names.
/// - History: how much the lifter trains it (`ExerciseFamiliarity`).
nonisolated enum ExerciseSearch {
    /// A value snapshot taken on the store's actor. Indexing never retains SwiftData objects.
    struct Document: Hashable, Codable, Sendable {
        let key: String
        /// The Data tab adds the names a lift was logged under.
        var names: [String]
        let primary: Muscle
        let secondary: [Muscle]
        let equipment: Equipment
        let pattern: String?
        let style: String
        let actions: [String]
        let structure: ExerciseStructure

        @MainActor private static let catalog = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ($0.id, $0) })

        @MainActor init(_ exercise: Exercise) {
            let entry = exercise.catalogID.flatMap { Self.catalog[$0] }
            key = exercise.searchKey
            names = [exercise.exerciseName, entry?.name].compactMap { $0 }
            primary = exercise.primaryMuscleFocus
            secondary = exercise.secondaryMuscles
            equipment = exercise.equipment
            style = exercise.executionStyle?.rawValue ?? entry?.profile.style.rawValue ?? ""
            // Actions the lifter set in Advanced Data carry their weight. Other stored rows weigh 1.
            let stored = CustomJointActions.read(exercise) ?? (exercise.jointActions ?? []).compactMap { action in
                action.movement.map { JointAction(movement: $0.key, weight: 1, role: action.role) }
            }
            actions = stored.map { $0.role.rawValue + " " + $0.movement }.sorted()
            // Built-in lifts read the catalog, which knows each action's weight, and so do own
            // lifts that copied a built-in's movement ("Moves like").
            if let profile = entry?.profile ?? MovesLike.entry(MovesLike.key(of: exercise))?.profile {
                pattern = profile.family?.rawValue
                structure = ExerciseStructure(actions: profile.actions, pattern: pattern)
            } else {
                pattern = exercise.movementPattern?.rawValue
                structure = stored.isEmpty
                    ? ExerciseStructure(primary: primary, secondary: secondary, pattern: pattern)
                    : ExerciseStructure(actions: stored, pattern: pattern)
            }
        }

        /// A built-in lift, also known by any other names it was logged under.
        @MainActor init(_ entry: ExerciseCatalog.Entry, otherNames: [String] = []) {
            key = "catalog:\(entry.id)"
            names = (otherNames + [entry.name]).uniqued()
            primary = entry.primaryMuscle
            secondary = entry.secondaryMuscles
            equipment = entry.equipment
            style = entry.profile.style.rawValue
            actions = entry.profile.storedMovements.map { entry.profile.role.rawValue + " " + $0 }.sorted()
            pattern = entry.profile.family?.rawValue
            structure = ExerciseStructure(actions: entry.profile.actions, pattern: pattern)
        }

        /// A lift known by the names and muscles its history recorded, and the structure of the
        /// built-in it moves like, when it has one.
        init(key: String, names: [String], primary: Muscle, secondary: [Muscle], equipment: Equipment,
             pattern: String? = nil, structure: ExerciseStructure? = nil) {
            self.key = key
            self.names = names
            self.primary = primary
            self.secondary = secondary
            self.equipment = equipment
            style = ""
            actions = []
            self.pattern = pattern
            self.structure = structure ?? ExerciseStructure(primary: primary, secondary: secondary, pattern: pattern)
        }
    }

    enum Context: Hashable, Sendable {
        case browse
        /// Change and Substitute. Without `sameEquipment`, other equipment ranks first.
        case replacing(source: String, sameEquipment: Bool)
        case importing(category: Muscle?)
        case charting(logged: Set<String>)

        var weights: (name: Double, meaning: Double, structure: Double, history: Double) {
            switch self {
            case .browse: (1.0, 0.6, 0.3, 0.15)
            case .replacing: (0.6, 0.3, 1.0, 0.15)
            case .importing: (1.0, 0.5, 0.2, 0.1)
            case .charting: (1.0, 0.4, 0.2, 0.3)
            }
        }
    }

    struct Match: Hashable, Sendable {
        let key: String
        let score: Double
        let name: Double
        let meaning: Double
        let structure: Double
        let history: Double
    }

    struct Index: Sendable {
        private struct Entry: Sendable {
            let document: Document
            let sortName: String
            let names: [[String]]
            let fields: [[String]]
            let vector: [Float]
            let mechanics: [Float]
        }

        private typealias Scored = (match: Match, entry: Entry, exact: Bool)

        private let entries: [Entry]
        private let encoder: ExerciseTextEncoder?
        private let topics: [AnatomyTopic]
        /// Every word of every name, so reading lift words never rebuilds it per search.
        fileprivate let allNameWords: Set<String>

        init(_ documents: [Document], encoder: ExerciseTextEncoder? = .bundled) {
            self.encoder = encoder
            topics = AnatomyTopic.index(using: encoder)
            entries = documents.map { document in
                let names = document.names.map(ExerciseQuery.words)
                let pattern = ExerciseQuery.words(document.pattern ?? "")
                let style = ExerciseQuery.words(document.style)
                let equipment = ExerciseQuery.words(document.equipment.displayName)
                let actions = document.actions.map(ExerciseQuery.words)
                let girdleActions = document.actions.filter { $0.contains("scapula.") }
                    .map { ExerciseQuery.words($0.replacingOccurrences(of: "scapula.", with: "shoulder girdle ")) }
                // Repeating "press" across the name, equipment and pattern would give
                // that word extra weight solely because of how the catalog is stored.
                var seen = Set<String>()
                let description = (names.flatMap { $0 } + ExerciseQuery.words(document.primary.rawValue) + pattern + equipment)
                    .filter { seen.insert($0).inserted }.joined(separator: " ")
                let mechanics = (pattern + style + actions.flatMap { $0 }).joined(separator: " ")
                return Entry(document: document, sortName: document.names.first ?? "", names: names,
                             fields: [pattern, style, equipment] + actions + girdleActions,
                             vector: encoder?.vector(for: description) ?? [], mechanics: encoder?.vector(for: mechanics) ?? [])
            }
            allNameWords = Set(entries.flatMap { $0.names.flatMap { $0 } })
        }

        /// Best first. An empty query lists the lifts the lifter trains or, when replacing,
        /// the source's closest neighbours.
        func rank(_ query: ExerciseQuery, context: Context = .browse, familiarity: ExerciseFamiliarity = .none) -> [Match] {
            let weights = context.weights
            var candidates = entries
            candidates.removeAll { query.excludes(equipment: $0.document.equipment, names: $0.names) }
            // What structure compares with: the lift being replaced, or the query's joint words.
            let named = query.movements.isEmpty ? nil : ExerciseStructure(actions: query.movements.map { JointAction.main($0) }, pattern: nil)
            var reference = named
            var avoided: Equipment?
            switch context {
            case .replacing(let source, let sameEquipment):
                candidates.removeAll { $0.document.key == source }
                let original = entries.first { $0.document.key == source }?.document
                reference = original?.structure
                // Naming equipment in the query overrides the preference for something else.
                if !sameEquipment && query.equipment.isEmpty { avoided = original?.equipment }
            case .charting(let logged):
                candidates.removeAll { !logged.contains($0.document.key) }
            case .browse, .importing:
                break
            }
            var related: [String: Double] = [:]
            if let reference {
                for entry in candidates { related[entry.document.key] = reference.similarity(to: entry.document.structure) }
            }

            // Equipment the query names is a preference: other equipment still shows, after it.
            // Closeness to the replaced lift only reorders lifts that fully match what was typed.
            func match(_ entry: Entry, name: Double = 0, meaning: Double = 0, neighbour: Bool = true) -> Match {
                let doc = entry.document
                let preference = query.equipment.isEmpty || query.equipment.contains(doc.equipment) ? 1 : ExerciseSearch.otherEquipment
                let avoid = doc.equipment == avoided ? ExerciseSearch.avoidedEquipment : 1
                let closeness = neighbour ? related[doc.key] ?? 0 : 0
                let (name, meaning, structure) = (preference * name, preference * meaning, preference * avoid * closeness)
                let history = familiarity.score(doc.key)
                let score = weights.name * name + weights.meaning * meaning + weights.structure * structure + weights.history * history
                return Match(key: doc.key, score: score, name: name, meaning: meaning, structure: structure, history: history)
            }

            guard !query.isEmpty else {
                let shown = candidates.filter { entry in
                    if case .replacing = context { return related[entry.document.key] ?? 0 >= ExerciseSearch.minimumStructure }
                    return familiarity.score(entry.document.key) > 0
                }
                return Self.sorted(shown.map { (match($0), $0, false) })
            }

            let evidence = candidates.map { ($0, nameEvidence($0, query)) }
            let fullNames = evidence.filter { $0.1.share == 1 }
            // When every full name match is one movement, its other lifts are relevant too.
            let patterns = Set(fullNames.compactMap { $0.0.document.pattern })
            let family = patterns.count == 1 ? patterns.first : nil

            // Opposite joint-action roles read alike to the model but describe different work.
            let roles = [JointActionRole.produces, .resists].flatMap { ExerciseQuery.words($0.rawValue) }
            let phrase = encoder.flatMap { encoder in
                query.words.contains(where: roles.contains) ? nil : SearchPhrase(terms: query.nameWords, encoder: encoder)
            }
            var similarity: [String: Double] = [:]
            if let phrase {
                for entry in candidates {
                    let identity = phrase.similarity(to: entry.vector)
                    let mechanics = 0.9 * phrase.similarity(to: entry.mechanics)
                    similarity[entry.document.key] = Double(max(identity, mechanics))
                }
            }

            // A query that names a body part, or names no lift but reads like a body part,
            // ranks by muscles rather than by the words in names.
            let labelled = topics.first { $0.labels.contains(query.nameWords.joined(separator: " ")) }?.focus
            var focus = labelled ?? (query.muscles.isEmpty ? nil : AnatomyTopic.Focus(muscles: query.muscles, emphasis: query.muscles))
            if focus == nil, fullNames.isEmpty, let phrase {
                focus = AnatomyTopic.focus(for: phrase, topics: topics, bestLift: Float(similarity.values.max() ?? 0))
            }
            // Joint words that read like nothing else, such as "posterior chain", name the prime movers' groups.
            // A model reading (`ExerciseQuery.adding`) ranks by what lifts work, never by the words typed.
            let filtered = query.filters != nil
            if focus == nil, fullNames.isEmpty || filtered, let named {
                let movers = Set(named.muscles.filter { $0.value == 1 }.keys)
                if !movers.isEmpty { focus = AnatomyTopic.Focus(muscles: movers, emphasis: movers) }
            }
            var byMuscle = focus != nil && (labelled != nil || fullNames.isEmpty || filtered)
            // An imported name is a lift's name: its category, or a muscle it names, adds evidence
            // but never replaces the words.
            if case .importing(let category) = context, labelled == nil {
                byMuscle = false
                if let category { focus = AnatomyTopic.Focus(muscles: [category], emphasis: [category]) }
            }

            let scored: [Scored] = evidence.map { entry, words in
                let doc = entry.document
                let meaningful = min(1, (similarity[doc.key] ?? 0) / ExerciseSearch.similarityCap)
                let muscle = focus.map { ExerciseSearch.muscleEvidence(doc, $0) } ?? 0
                var name = byMuscle ? 0 : words.share
                if !byMuscle, let family, doc.pattern == family { name = max(name, ExerciseSearch.familyEvidence) }
                let meaning = byMuscle ? (muscle > 0 ? muscle : ExerciseSearch.outsideFocus * meaningful) : max(muscle, meaningful)
                let full = byMuscle ? muscle > 0 : words.share == 1
                return (match(entry, name: name, meaning: meaning, neighbour: full), entry, words.exact)
            }

            // The cutoff reads only what the query says, never structure or history.
            func relevance(_ match: Match) -> Double { weights.name * match.name + weights.meaning * match.meaning }
            let best = scored.map { relevance($0.match) }.max() ?? 0
            let cutoff = max(ExerciseSearch.minimumRelevance, best - ExerciseSearch.relevanceMargin)
            return Self.sorted(scored.filter { $0.exact || relevance($0.match) >= cutoff })
        }

        /// Exact names first, then score, then how much the lifter trains it, then name.
        private static func sorted(_ scored: [Scored]) -> [Match] {
            scored.sorted { left, right in
                if left.exact != right.exact { return left.exact }
                if left.match.score != right.match.score { return left.match.score > right.match.score }
                if left.match.history != right.match.history { return left.match.history > right.match.history }
                return left.entry.sortName.localizedStandardCompare(right.entry.sortName) == .orderedAscending
            }
            .map(\.match)
        }

        /// The best share of query words in one of the lift's names. A description field,
        /// such as its movement or style, that holds every word counts nearly as much.
        private func nameEvidence(_ entry: Entry, _ query: ExerciseQuery) -> (share: Double, exact: Bool) {
            let words = query.nameWords
            let whole = query.words.joined()
            if entry.names.contains(where: { $0.joined() == whole }) { return (1, true) }
            let share = entry.names.map { ExerciseSearch.share(of: words, in: $0) }.max() ?? 0
            let field = entry.fields.contains { ExerciseSearch.share(of: words, in: $0) == 1 } ? ExerciseSearch.fieldEvidence : 0
            return (max(share, field), false)
        }
    }

    // MARK: - Tuning

    /// Show every match at least this relevant to the query...
    static let minimumRelevance = 0.35
    /// ...and within this much of the best one, so focused queries stay short.
    static let relevanceMargin = 0.4
    /// Cosine similarity at or above this counts as full meaning evidence.
    static let similarityCap = 0.8
    /// A field such as "isometric" or "produces knee extension" holds every query word.
    static let fieldEvidence = 0.8
    /// Lifts of the one movement every full name match shares, such as Push Up for "bench press".
    static let familyEvidence = 0.8
    /// Evidence kept when the lift uses other equipment than the query names.
    static let otherEquipment = 0.85
    /// With no query, Change and Substitute list lifts at least this close to the one replaced.
    static let minimumStructure = 0.2
    /// Closeness kept by a substitute on the same equipment as the lift it replaces.
    static let avoidedEquipment = 0.85
    /// Meaning kept by a lift outside the muscles a body-part query names.
    static let outsideFocus = 0.5

    private static func muscleEvidence(_ document: Document, _ focus: AnatomyTopic.Focus) -> Double {
        if focus.emphasis.contains(document.primary) { return 1 }
        if focus.muscles.contains(document.primary) { return 0.85 }
        if !focus.muscles.isDisjoint(with: document.secondary) { return 0.65 }
        return 0
    }

    /// The share of query words found in a name. A word matches when it is equal, a prefix of
    /// at least 3 letters (2 for the last word, still being typed), one typo away for words of
    /// 5 or more letters, or the joined form of neighbouring words ("pullup", "pull down").
    static func share(of query: [String], in name: [String]) -> Double {
        guard !query.isEmpty, !name.isEmpty else { return 0 }
        let joined = name.indices.dropLast().map { name[$0] + name[$0 + 1] }
        var matched = Array(repeating: false, count: query.count)
        for (index, word) in query.enumerated() {
            let shortest = index == query.count - 1 ? 2 : 3
            if name.contains(where: { $0 == word || (word.count >= shortest && $0.hasPrefix(word)) || oneTypo(word, $0) })
                || joined.contains(where: { $0 == word || (word.count > 4 && $0.hasPrefix(word)) }) {
                matched[index] = true
            }
            if index > 0, name.contains(query[index - 1] + word) {
                matched[index - 1] = true
                matched[index] = true
            }
        }
        return Double(matched.filter { $0 }.count) / Double(query.count)
    }

    /// One letter added, dropped or changed, for words of 5 or more letters.
    fileprivate static func oneTypo(_ word: String, _ target: String) -> Bool {
        guard word.count >= 5, abs(word.count - target.count) <= 1, word != target else { return false }
        let a = Array(word), b = Array(target)
        var i = 0, j = 0, edits = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                i += 1
                j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if a.count > b.count {
                i += 1
            } else if a.count < b.count {
                j += 1
            } else {
                i += 1
                j += 1
            }
        }
        return edits + (a.count - i) + (b.count - j) <= 1
    }
}

// MARK: - Lift words

nonisolated extension ExerciseSearch {
    /// Words in a search that name lifts, such as "rdl" in "rdl e1rm".
    struct LiftSpan: Hashable, Sendable {
        /// Positions in the query's `words`.
        let range: Range<Int>
        /// The lifts named, most trained first. Empty for a built-in lift with no history.
        let keys: [String]
        /// The lift's name when the words name one lift, otherwise the words themselves.
        let name: String
    }

    /// Equipment says which version of a lift, never which lift.
    fileprivate static let equipmentWords = Set(ExerciseQuery.equipmentWords.keys).union(["smith", "ez", "bar"])

    /// Words that say which version of a lift, like equipment: "pull ups forward grip" is a pull-up,
    /// and "grip" alone never names Close Grip Bench Press.
    static let variantWords: Set<String> = [
        "grip", "forward", "wide", "narrow", "close", "neutral", "flat", "standing", "seated", "bar", "single",
    ]

    /// One letter added, dropped, changed or swapped with its neighbour, for words of 4 or more
    /// letters, also comparing plurals so "burpies" is "burpees".
    static func isTypo(_ word: String, of target: String) -> Bool {
        guard word.count >= 4, target.count >= 4, word != target else { return false }
        func plural(_ word: String) -> String { word.hasSuffix("y") ? word.dropLast() + "ies" : word + "s" }
        return editDistance(word, target, limit: 1) == 1 || editDistance(plural(word), plural(target), limit: 1) == 1
    }

    /// Letters added, dropped, changed or swapped with a neighbour (Damerau–Levenshtein), or
    /// `limit + 1` once it is clearly more than `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= limit else { return limit + 1 }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var previous2: [Int] = []
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    row[j] = min(row[j], previous2[j - 2] + 1)
                }
            }
            if row.min()! > limit { return limit + 1 }
            previous2 = previous
            previous = row
        }
        return min(previous[b.count], limit + 1)
    }
}

nonisolated extension ExerciseSearch.Index {
    /// The lifts a search names, read the way the picker reads names: shorthand, plurals,
    /// one typo, joined words and a half-typed last word. Charting names logged lifts, and
    /// comes back with no keys when every word counts only for built-in lifts with no history.
    /// - A full name wins: "incline bench" is Incline Barbell Bench Press.
    /// - A family word is every logged lift it fits best: "squat" is every squat, and "bench"
    ///   prefers Barbell Bench Press over Incline Barbell Bench Press.
    /// - Every word counts: with no incline bench logged, "incline bench" is the unlogged incline
    ///   presses, never the flat bench.
    /// - Muscle words, `plainWords` and variant words such as "grip" never name a lift alone, so
    ///   "back squat" is a lift and "back volume" is not. A variant word beside a lift is part of it.
    func liftSpans(in query: ExerciseQuery, context: ExerciseSearch.Context,
                   familiarity: ExerciseFamiliarity = .none, plainWords: Set<String> = []) -> [ExerciseSearch.LiftSpan] {
        var logged = entries
        var unlogged: [Entry] = []
        if case .charting(let keys) = context {
            logged = entries.filter { keys.contains($0.document.key) }
            unlogged = entries.filter { !keys.contains($0.document.key) }
        }
        logged.sort { (familiarity.score($0.document.key), $1.sortName) > (familiarity.score($1.document.key), $0.sortName) }
        var words = query.words
        guard !words.isEmpty else { return [] }

        let nameWords = Set(logged.flatMap { $0.names.flatMap { $0 } })
        func isPlain(_ word: String) -> Bool {
            plainWords.contains(word) || ExerciseQuery.muscleWords[word] != nil || Double(word) != nil
        }
        // Search runs while typing, so "ben" is "bench" on its way: the word it starts in the
        // most trained lift.
        if let last = words.last, last.count >= 3, !isPlain(last), !nameWords.contains(last),
           !ExerciseSearch.equipmentWords.contains(last),
           let completion = logged.lazy.flatMap({ $0.names.flatMap { $0 } }).first(where: { $0.hasPrefix(last) && !isPlain($0) }) {
            words[words.count - 1] = completion
        }

        // A typo is a word no lift name uses, so "full" never becomes "pull". Each typed word is
        // compared with the name words once: every window and lift then reads the answer.
        var typos: [String: Set<String>] = [:]
        for word in Set(words) where !isPlain(word) && !allNameWords.contains(word) {
            typos[word] = allNameWords.filter { ExerciseSearch.isTypo(word, of: $0) }
        }
        func isTypo(_ word: String, of target: String) -> Bool {
            typos[word]?.contains(target) ?? false
        }
        /// How many words of the lift's name, beside equipment, the window leaves out, or nil
        /// when a window word isn't in the name.
        func missing(_ window: ArraySlice<String>, _ entry: Entry) -> Int? {
            entry.names.compactMap { name in Self.missing(Array(window), from: name, isTypo: isTypo) }.min()
        }
        // A window names a lift only through a word that isn't equipment, a variant, a muscle or plain.
        func canName(_ window: ArraySlice<String>) -> Bool {
            window.contains {
                !isPlain($0) && !ExerciseSearch.equipmentWords.contains($0) && !ExerciseSearch.variantWords.contains($0)
            }
        }

        var taken = Array(repeating: false, count: words.count)
        var spans: [ExerciseSearch.LiftSpan] = []
        func take(_ range: Range<Int>, _ matches: [Entry], isLogged: Bool) {
            // Lifts with no history are only named, so name the closest: every typed word in the
            // name, then the fewest words beside them. "front squat" is Barbell Front Squat, not
            // Smith Machine Front Squat, and "smith front squat" is the Smith one.
            let matches = isLogged || matches.count < 2 ? matches : Self.closest(matches, to: Set(words[range]))
            let name = matches.count == 1 ? matches[0].sortName
                : isLogged ? words[range].joined(separator: " ") : Self.sharedName(of: matches)
            spans.append(.init(range: range, keys: isLogged ? matches.map(\.document.key) : [], name: name))
            for index in range { taken[index] = true }
        }
        func isFree(_ range: Range<Int>) -> Bool { range.allSatisfy { !taken[$0] } }

        // Full names, longest first: logged lifts, then built-in lifts with no history.
        for (pool, isLogged) in [(logged, true), (unlogged, false)] {
            for length in stride(from: words.count, through: 2, by: -1) {
                for start in 0...(words.count - length) {
                    let range = start..<start + length
                    guard isFree(range), canName(words[range]) else { continue }
                    let matches = pool.filter { missing(words[range], $0) == 0 }
                    if !matches.isEmpty { take(range, matches, isLogged: isLogged) }
                }
            }
        }

        // Families: the longest run of lift words some lifts share. Logged lifts that fit it win.
        // A run only built-in lifts with no history fit names them when it has two words or is a
        // whole name, as in "incline bench" or "burpees", so a lone "row" stays the logged row.
        var start = 0
        while start < words.count {
            var best: (end: Int, fits: [(entry: Entry, missing: Int, isLogged: Bool)])?
            var end = start
            // A plain word can sit inside a name, as "over" in "bent over row", but never starts or ends one.
            while end < words.count, !taken[end], end > start || !isPlain(words[start]) {
                let window = words[start...end]
                let fits = logged.compactMap { entry in missing(window, entry).map { (entry, $0, true) } }
                    + unlogged.compactMap { entry in missing(window, entry).map { (entry, $0, false) } }
                guard !fits.isEmpty else { break }
                if canName(window), !isPlain(words[end]) { best = (end, fits) }
                end += 1
            }
            guard let best else {
                start += 1
                continue
            }
            let range = start..<best.end + 1
            let logged = best.fits.filter(\.isLogged)
            let pool = logged.isEmpty ? best.fits : logged
            let fewest = pool.map(\.missing).min() ?? 0
            if !logged.isEmpty || range.count > 1 || fewest == 0 {
                take(range, pool.filter { $0.missing == fewest }.map(\.entry), isLogged: !logged.isEmpty)
            }
            start = best.end + 1
        }

        // A variant word beside a lift says which version, so it belongs to the lift.
        return spans.sorted { $0.range.lowerBound < $1.range.lowerBound }.map { span in
            var lower = span.range.lowerBound, upper = span.range.upperBound
            while lower > 0, !taken[lower - 1], ExerciseSearch.variantWords.contains(words[lower - 1]) {
                lower -= 1
                taken[lower] = true
            }
            while upper < words.count, !taken[upper], ExerciseSearch.variantWords.contains(words[upper]) {
                taken[upper] = true
                upper += 1
            }
            return .init(range: lower..<upper, keys: span.keys, name: span.name)
        }
    }

    /// The lifts whose names hold the most of `words`, then the fewest words beside them.
    private static func closest(_ entries: [Entry], to words: Set<String>) -> [Entry] {
        func distance(_ entry: Entry) -> (Int, Int) {
            entry.names.map { name in
                let name = Set(name)
                return (words.subtracting(name).count, name.subtracting(words).count)
            }.min { $0 < $1 } ?? (0, 0)
        }
        let best = entries.map(distance).min { $0 < $1 }
        return entries.filter { distance($0) == best! }
    }

    /// The words every one of these lifts' names shares, as in "Incline Bench Press" for the
    /// incline barbell and dumbbell presses.
    private static func sharedName(of entries: [Entry]) -> String {
        let words = entries.dropFirst().reduce(Set(entries[0].names[0])) { $0.intersection($1.names.flatMap { $0 }) }
        let shared = entries[0].sortName.split(separator: " ").filter { words.contains(ExerciseQuery.words(String($0)).first ?? "") }
        return shared.isEmpty ? entries[0].sortName : shared.joined(separator: " ")
    }

    /// Logged lifts that do every one of these joint movements, at least one as a main action.
    func keys(doing movements: Set<String>, among logged: Set<String>) -> [String] {
        guard !movements.isEmpty else { return [] }
        return entries.filter { entry in
            let actions = entry.document.structure.actions
            return logged.contains(entry.document.key) && movements.allSatisfy { actions[$0] != nil }
                && movements.contains { actions[$0] == 1 }
        }
        .map(\.document.key)
    }

    /// Words of `name` beside equipment that no window word matched, or nil when a window word
    /// matches nothing. A word matches when equal, one typo away, or the joined form of two
    /// neighbours ("pullup", "pull down").
    private static func missing(_ window: [String], from name: [String], isTypo: (String, String) -> Bool) -> Int? {
        var used = Array(repeating: false, count: name.count)
        var index = 0
        while index < window.count {
            let word = window[index]
            if let at = name.firstIndex(of: word) ?? name.indices.first(where: { isTypo(word, name[$0]) }) {
                used[at] = true
            } else if let at = name.indices.dropLast().first(where: { name[$0] + name[$0 + 1] == word }) {
                used[at] = true
                used[at + 1] = true
            } else if index + 1 < window.count, let at = name.firstIndex(of: word + window[index + 1]) {
                used[at] = true
                index += 1
            } else {
                return nil
            }
            index += 1
        }
        return name.indices.filter { !used[$0] && !ExerciseSearch.equipmentWords.contains(name[$0]) }.count
    }
}

extension Exercise {
    /// Names the exercise in search and familiarity. An own exercise without a sync ID yet
    /// falls back to its store identifier, which is stable while the index is in memory.
    var searchKey: String { syncKey ?? "\(persistentModelID)" }
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

    /// Lifters say "leg day" for the lower body.
    private static let aliases = ["lowerBody": ["leg"]]

    static func index(using encoder: ExerciseTextEncoder?) -> [Self] {
        guard let url = Bundle.main.url(forResource: "MuscleAnatomy", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Anatomy.self, from: data) else { return [] }
        func label(_ text: String) -> String { ExerciseQuery.words(text).joined(separator: " ") }
        let regions = catalog.regions.map { region in
            let members = Set(catalog.muscles.filter { $0.regions.contains(region.id) }.map(\.muscle))
            let focus = Focus(muscles: members, emphasis: region.emphasis ?? members)
            return Self(labels: Set([label(region.name), label(region.id)] + (aliases[region.id] ?? [])), focus: focus,
                        vectors: encoder.map { [region.name, region.description].map($0.vector) } ?? [])
        }
        return regions + catalog.muscles.map { entry -> Self in
            let words = ExerciseQuery.muscleWords.filter { $0.value == entry.muscle }.map(\.key)
            return Self(labels: Set(words + [label(entry.muscle.rawValue)]), focus: Focus(muscles: [entry.muscle], emphasis: [entry.muscle]),
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
