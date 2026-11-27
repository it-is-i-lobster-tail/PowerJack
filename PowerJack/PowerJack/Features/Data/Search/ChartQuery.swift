import Foundation

/// What a chart search asks for, read once from the typed text.
///
/// The scope (lifts, muscles, dates and numbers) always comes from the user's own words, so no
/// later step, including the language model, can invent a lift or a date. The words left over
/// are the intent, which ranks the charts.
struct ChartQuery: Equatable {
    /// A lift or muscle group the search names, with the logged exercises or muscles it covers.
    struct Subject: Equatable {
        let name: String
        var exerciseKeys: [String] = []
        var muscles: [Muscle] = []
    }

    let text: String
    /// Every word of the search, for cues such as "how many".
    let words: [String]
    private(set) var periods: [StudyPeriod] = []
    private(set) var parameters: [StudyParameter: Int] = [:]
    private(set) var lifts: [Subject] = []
    private(set) var muscleGroups: [Subject] = []
    /// Catalog lifts the search names that have no logged sets.
    private(set) var unloggedLifts: [String] = []
    private(set) var intent = ""

    /// A lone letter is the start of a word, not a search yet.
    var isEmpty: Bool { words.allSatisfy { $0.count < 2 } }
    var period: StudyPeriod? { periods.count == 1 ? periods[0] : nil }
    var exerciseKeys: [String] { lifts.flatMap(\.exerciseKeys).uniqued() }
    var muscles: [Muscle] { Muscle.allCases.filter { muscle in muscleGroups.contains { $0.muscles.contains(muscle) } } }
    var hasScope: Bool { !lifts.isEmpty || !muscleGroups.isEmpty }

    /// Questions benefit from the language model. Short filters such as "arms October" do not.
    var isQuestion: Bool {
        text.contains("?") || words.count >= 5 || Self.questionWords.contains(words.first ?? "")
    }

    /// Whether the search contains any of these words or phrases, ignoring plurals.
    func mentions(_ phrases: [String]) -> Bool {
        let text = " " + words.map(SearchWords.singular).joined(separator: " ") + " "
        return phrases.contains { phrase in
            text.contains(" " + SearchWords.tokens(phrase).map(SearchWords.singular).joined(separator: " ") + " ")
        }
    }

    init(_ text: String, history: StudyHistory) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var tokens = SearchWords.tokens(self.text)
        words = tokens
        periods = Self.takePeriods(from: &tokens, history: history)
        parameters = Self.takeParameters(from: &tokens)
        tokens = tokens.map { Self.liftVerbs[$0] ?? SearchWords.singular($0) }
        let known = ChartLifts.of(history)
        takeLifts(from: &tokens, known)
        let joints = Self.takeMovements(from: &tokens, known)
        lifts += joints.lifts
        muscleGroups = joints.muscles + Self.takeMuscles(from: &tokens)
        // A bare number, such as "at 185", has no unit to say what it measures.
        intent = tokens.filter { Double($0) == nil }.joined(separator: " ")
    }

    private static let questionWords: Set<String> = [
        "what", "when", "where", "which", "who", "why", "how", "do", "does", "did", "am", "is", "are",
        "was", "were", "have", "has", "can", "could", "should", "show", "compare",
    ]
}

// MARK: - Dates

extension ChartQuery {
    /// Reads "today", "last month", "October", "Oct 10", "March 2025" or "2025". A month without a
    /// year means its most recent occurrence, so "December" asked in November is last December.
    private static func takePeriods(from tokens: inout [String], history: StudyHistory) -> [StudyPeriod] {
        let calendar = history.calendar
        let today = history.today
        func parts(_ date: Date) -> (year: Int, month: Int, day: Int) {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return (c.year ?? 0, c.month ?? 1, c.day ?? 1)
        }
        var periods: [StudyPeriod] = []
        var index = 0
        while index < tokens.count {
            let word = tokens[index]
            let next = tokens.indices.contains(index + 1) ? tokens[index + 1] : ""
            var consumed = 0
            switch (word, next) {
            case ("today", _), ("yesterday", _):
                let date = calendar.date(byAdding: .day, value: word == "today" ? 0 : -1, to: today) ?? today
                let day = parts(date)
                periods.append(.day(year: day.year, month: day.month, day: day.day))
                consumed = 1
            case ("this", "month"), ("last", "month"), ("previous", "month"):
                let date = calendar.date(byAdding: .month, value: word == "this" ? 0 : -1, to: today) ?? today
                periods.append(.month(year: parts(date).year, month: parts(date).month))
                consumed = 2
            case ("this", "year"), ("last", "year"), ("previous", "year"):
                periods.append(.year(parts(today).year - (word == "this" ? 0 : 1)))
                consumed = 2
            default:
                if let year = Self.year(word) {
                    periods.append(.year(year))
                    consumed = 1
                } else if let month = Self.month(at: index, in: tokens) {
                    let day = Int(next).flatMap { (1...31).contains($0) ? $0 : nil }
                    let yearIndex = index + (day == nil ? 1 : 2)
                    let stated = tokens.indices.contains(yearIndex) ? Self.year(tokens[yearIndex]) : nil
                    let now = parts(today)
                    let year = stated ?? (month > now.month || (month == now.month && (day ?? 0) > now.day) ? now.year - 1 : now.year)
                    if let day {
                        periods.append(.day(year: year, month: month, day: day))
                    } else {
                        periods.append(.month(year: year, month: month))
                    }
                    consumed = 1 + (day == nil ? 0 : 1) + (stated == nil ? 0 : 1)
                }
            }
            if consumed > 0 {
                tokens.removeSubrange(index..<index + consumed)
            } else {
                index += 1
            }
        }
        return periods
    }

    private static func year(_ word: String) -> Int? {
        guard word.count == 4, let year = Int(word), (1900...2199).contains(year) else { return nil }
        return year
    }

    /// "May" is also an ordinary word, so it needs a date-like neighbor.
    private static func month(at index: Int, in tokens: [String]) -> Int? {
        let word = tokens[index]
        guard word.count >= 3, let month = DataSearchQuery.monthNumber(word) else { return nil }
        guard word == "may" else { return month }
        let previous = index > 0 ? tokens[index - 1] : ""
        let next = tokens.indices.contains(index + 1) ? tokens[index + 1] : ""
        let datePrepositions: Set<String> = ["in", "on", "during", "since", "of", "from", "and", "or", "vs", "versus", "than"]
        return datePrepositions.contains(previous) || Int(next) != nil ? month : nil
    }
}

// MARK: - Numbers

extension ChartQuery {
    /// Reads "185 lb", "80 kg", "5 reps", "3 sets", "3x5", "50 minutes", "6 weeks" and "21 days".
    private static func takeParameters(from tokens: inout [String]) -> [StudyParameter: Int] {
        var parameters: [StudyParameter: Int] = [:]
        var index = 0
        while index < tokens.count {
            let word = tokens[index]
            if let scheme = word.wholeMatch(of: #/(\d{1,2})[x×](\d{1,3})/#),
               let sets = Int(scheme.1), let reps = Int(scheme.2) {
                parameters[.sets] = sets
                parameters[.reps] = reps
                tokens.remove(at: index)
                continue
            }
            guard let number = Double(word), number.isFinite, number >= 0, number <= 100_000,
                  tokens.indices.contains(index + 1),
                  let unit = Self.units[tokens[index + 1]] else {
                index += 1
                continue
            }
            switch unit {
            case .load: parameters[.load] = WeightUnit.pounds.tenthsPounds(from: number)
            case .loadKilograms: parameters[.load] = WeightUnit.kilograms.tenthsPounds(from: number)
            case .other(let parameter): parameters[parameter] = Int(number)
            }
            tokens.removeSubrange(index...index + 1)
        }
        return parameters
    }

    private enum Unit { case load, loadKilograms, other(StudyParameter) }

    private static let units: [String: Unit] = {
        var units: [String: Unit] = [:]
        for word in ["lb", "lbs", "pound", "pounds"] { units[word] = .load }
        for word in ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"] { units[word] = .loadKilograms }
        let others: [(StudyParameter, [String])] = [
            (.reps, ["rep", "reps", "repetition", "repetitions"]), (.sets, ["set", "sets"]),
            (.weeks, ["week", "weeks"]), (.sessions, ["session", "sessions", "workout", "workouts"]),
            (.minutes, ["minute", "minutes", "min", "mins"]), (.comparisonDays, ["day", "days"]),
        ]
        for (parameter, words) in others {
            for word in words { units[word] = .other(parameter) }
        }
        return units
    }()
}

// MARK: - Lifts and muscles

/// The lifts a Data search can name: every logged lift by each name it was logged under, and
/// every built-in lift, so a typed lift with no history can say so.
private final class ChartLifts {
    let index: ExerciseSearch.Index
    let logged: Set<String>
    let familiarity: ExerciseFamiliarity

    private init(_ lifts: [(key: String, names: [String], session: StudySession)], movesLike: [String: String],
                 familiarity: ExerciseFamiliarity) {
        let catalog = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ("catalog:\($0.id)", $0) })
        let logged = Set(lifts.map(\.key))
        self.logged = logged
        var documents = lifts.map { lift in
            if let entry = catalog[lift.key] { return ExerciseSearch.Document(entry, otherNames: lift.names) }
            // An own lift that moves like a built-in does its joint actions, so "rear delts" finds it.
            let profile = movesLike[lift.key].flatMap { catalog[$0] }?.profile
            let pattern = profile?.family?.rawValue
            return ExerciseSearch.Document(key: lift.key, names: lift.names, primary: lift.session.primary ?? .chest,
                                           secondary: lift.session.assisting ?? [], equipment: .bodyweight, pattern: pattern,
                                           structure: profile.map { ExerciseStructure(actions: $0.actions, pattern: pattern) })
        }
        documents += ExerciseCatalog.entries.filter { !logged.contains("catalog:\($0.id)") }.map { ExerciseSearch.Document($0) }
        // Spans read names, not meaning, so the index skips the embedding model.
        index = ExerciseSearch.Index(documents, encoder: nil)
        self.familiarity = familiarity
    }

    private static var cache: [Int: ChartLifts] = [:]

    /// Search runs on every pause while typing, so each set of logged names is indexed once.
    static func of(_ history: StudyHistory) -> ChartLifts {
        var names: [String: (names: [String], session: StudySession)] = [:]
        var sessions: [String: Set<String>] = [:]
        for session in history.sessions.reversed() where !session.done.isEmpty {
            // Newest name first, so a renamed lift shows its current name.
            if names[session.key]?.names.contains(session.name) != true {
                names[session.key, default: ([], session)].names.append(session.name)
            }
            sessions[session.workout, default: []].insert(session.key)
        }
        let lifts = names.map { (key: $0.key, names: $0.value.names, session: $0.value.session) }.sorted { $0.key < $1.key }
        var hasher = Hasher()
        hasher.combine(history.revision)
        for (own, builtIn) in history.movesLike.sorted(by: { $0.key < $1.key }) {
            hasher.combine(own)
            hasher.combine(builtIn)
        }
        for lift in lifts {
            hasher.combine(lift.key)
            hasher.combine(lift.names)
        }
        let id = hasher.finalize()
        if let cached = cache[id] { return cached }
        let order = history.sessions.map(\.workout).uniqued()
        let lifted = ChartLifts(lifts, movesLike: history.movesLike, familiarity: ExerciseFamiliarity(sessions: order.compactMap { sessions[$0] }))
        if cache.count >= 4 { cache.removeAll() }
        cache[id] = lifted
        return lifted
    }
}

extension ChartQuery {
    /// Words that never name a lift by themselves: chart words such as "volume", muscle groups,
    /// and function words.
    private static let plainWords = SearchWords.notLiftWords.union(SearchWords.muscleWords).union(ChartIndex.vocabulary)

    /// Questions say what was done: "how much have I benched".
    private static let liftVerbs = [
        "benched": "bench", "squatted": "squat", "deadlifted": "deadlift", "pressed": "press", "pressing": "press",
        "curled": "curl", "curling": "curl", "rowed": "row", "rowing": "row",
    ]

    /// Lift names, as the exercise picker reads them. See `ExerciseSearch.Index.liftSpans`.
    private mutating func takeLifts(from tokens: inout [String], _ known: ChartLifts) {
        let query = ExerciseQuery(tokens: tokens)
        var taken = IndexSet()
        for span in known.index.liftSpans(in: query, context: .charting(logged: known.logged),
                                          familiarity: known.familiarity, plainWords: Self.plainWords) {
            let source = query.source(of: span.range)
            if span.keys.isEmpty {
                // A built-in lift with no logged sets stays in scope, so its charts are empty and its totals are zero.
                unloggedLifts.append(span.name)
                lifts.append(Subject(name: span.name))
            } else {
                let name = span.keys.count == 1 ? span.name : tokens[source].joined(separator: " ")
                lifts.append(Subject(name: name, exerciseKeys: span.keys))
            }
            taken.insert(integersIn: source)
        }
        tokens = tokens.indices.filter { !taken.contains($0) }.map { tokens[$0] }
    }

    /// Joint words such as "rear delts" scope the logged lifts that do that movement, or with
    /// none logged, the muscles that do it. A lone muscle word such as "lat" stays a muscle group.
    private static func takeMovements(from tokens: inout [String], _ known: ChartLifts) -> (lifts: [Subject], muscles: [Subject]) {
        let query = ExerciseQuery(tokens: tokens)
        let words = query.words
        var used = Array(repeating: false, count: words.count)
        var taken = IndexSet()
        var lifts: [Subject] = []
        var muscles: [Subject] = []
        for length in stride(from: min(3, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let range = start..<start + length
                let term = words[range].joined(separator: " ")
                let movements = JointAnatomy.bundled.movements(forTerm: term)
                guard !movements.isEmpty, range.allSatisfy({ !used[$0] }),
                      length > 1 || ExerciseQuery.muscleWords[term] == nil,
                      // "trap bar" is a bar, not the traps.
                      !(term == "trap" && words.indices.contains(start + 1) && words[start + 1] == "bar")
                else { continue }
                let source = query.source(of: range)
                let name = tokens[source].joined(separator: " ")
                let keys = known.index.keys(doing: movements, among: known.logged)
                    .sorted { known.familiarity.score($0) > known.familiarity.score($1) }
                if !keys.isEmpty {
                    lifts.append(Subject(name: name, exerciseKeys: keys))
                } else {
                    let movers = movements.flatMap { JointAnatomy.bundled.muscles(for: $0) }.filter(\.isPrime).map(\.group)
                    guard !movers.isEmpty else { continue }
                    muscles.append(Subject(name: name, muscles: Muscle.allCases.filter(movers.contains)))
                }
                for index in range { used[index] = true }
                taken.insert(integersIn: source)
            }
        }
        tokens = tokens.indices.filter { !taken.contains($0) }.map { tokens[$0] }
        return (lifts, muscles)
    }

    private static func takeMuscles(from tokens: inout [String]) -> [Subject] {
        var groups: [Subject] = []
        for (phrase, name, muscles) in SearchWords.muscleAliases {
            let words = phrase.split(separator: " ").map(String.init)
            while let range = tokens.range(of: words) {
                if !groups.contains(where: { $0.muscles == muscles }) {
                    groups.append(Subject(name: name, muscles: muscles))
                }
                tokens.removeSubrange(range)
            }
        }
        // "Which muscles have I neglected?" asks about all of them.
        if groups.isEmpty, let index = tokens.firstIndex(of: "muscle") {
            groups.append(Subject(name: "all muscles", muscles: Muscle.allCases))
            tokens.remove(at: index)
        }
        return groups
    }
}

// MARK: - Words

/// Search compares lowercase, accent-free, singular words.
enum SearchWords {
    static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "'", with: "")
        return folded.split { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "×" }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
    }

    static func singular(_ word: String) -> String {
        guard word.count > 3, Double(word) == nil, !stopWords.contains(word) else { return word }
        if word == "calves" { return "calf" }
        if word.hasSuffix("sses") || word.hasSuffix("ches") || word.hasSuffix("shes") { return String(word.dropLast(2)) }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("s") && !word.hasSuffix("ss") && !word.hasSuffix("us") && !word.hasSuffix("ceps") {
            return String(word.dropLast())
        }
        return word
    }

    /// Function words that carry no meaning for ranking. Direction words such as "up" stay, since
    /// "going up" means progress.
    static let stopWords: Set<String> = Set("""
        a about after all am an and any are as at be been before between both but by can could did didnt do
        does doesnt doing done dont during each ever every for from get getting got had has have how hows i if
        im in into is it its ive just me my myself not now of off on or our out over per really since so some
        than that the their them then there these they this those through to too very vs versus was were what
        whats when where which while who why will with would you your
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    /// Words that never start a lift name by themselves, even though "Push Up" contains "up".
    static let notLiftWords = stopWords.union(["up", "down", "going", "go", "more", "most", "last", "next", "same"])

    /// The words people use for a muscle group, its display name, and its muscles.
    /// Multi-word phrases come first, so "upper body" is read before "body".
    static let muscleAliases: [(phrase: String, name: String, muscles: [Muscle])] = [
        ("upper body", "upper body", [.chest, .shoulders, .back, .biceps, .triceps, .forearms]),
        ("lower body", "lower body", StudyHistory.legs), ("leg", "legs", StudyHistory.legs),
        ("arm", "arms", [.biceps, .triceps]), ("core", "core", [.abs, .obliques]), ("pec", "chest", [.chest]),
        ("delt", "shoulders", [.shoulders]), ("lat", "back", [.back]), ("ab", "abs", [.abs]),
        ("bicep", "biceps", [.biceps]), ("tricep", "triceps", [.triceps]),
    ] + Muscle.allCases.map { (phrase: singular($0.rawValue), name: $0.rawValue, muscles: [$0]) }

    static let muscleWords = Set(muscleAliases.flatMap { $0.phrase.split(separator: " ").map(String.init) })
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Array where Element: Equatable {
    /// The first place `phrase` appears as consecutive elements.
    func range(of phrase: [Element]) -> Range<Int>? {
        guard !phrase.isEmpty, phrase.count <= count else { return nil }
        for start in 0...(count - phrase.count) where Array(self[start..<start + phrase.count]) == phrase {
            return start..<start + phrase.count
        }
        return nil
    }
}
