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
        /// Where in `words` the subject was read.
        var positions: [Int] = []
        /// Other logged lifts the words could mean, closest first.
        var alternatives: [String] = []
    }

    /// A search to try instead, when the words match nothing logged.
    struct Suggestion: Equatable {
        let name: String
        let text: String
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
    /// How the search was read when that isn't plain from the results.
    private(set) var notes: [String] = []
    private(set) var suggestion: Suggestion?
    private(set) var intent = ""
    /// Where in `words` each period and number was read.
    private(set) var periodPositions: [[Int]] = []
    private(set) var parameterPositions: [StudyParameter: [Int]] = [:]

    /// A lone letter is the start of a word, not a search yet.
    var isEmpty: Bool { words.allSatisfy { $0.count < 2 } }
    /// One period, or the span covering several, such as "2023 vs 2025".
    private(set) var period: StudyPeriod?
    var exerciseKeys: [String] { lifts.flatMap(\.exerciseKeys).uniqued() }
    var muscles: [Muscle] { Muscle.allCases.filter { muscle in muscleGroups.contains { $0.muscles.contains(muscle) } } }
    var hasScope: Bool { !lifts.isEmpty || !muscleGroups.isEmpty }

    /// Questions benefit from the language model. Short filters such as "arms October" do not.
    var isQuestion: Bool {
        text.contains("?") || words.count >= 5 || Self.questionWords.contains(words.first ?? "")
    }

    /// Two lifts set side by side: "squat vs deadlift", "compare bench and squat".
    var comparesLifts: Bool { lifts.count >= 2 || (exerciseKeys.count >= 2 && mentions(["vs", "versus", "compare"])) }

    /// Whether the search contains any of these words or phrases, ignoring plurals.
    func mentions(_ phrases: [String]) -> Bool {
        let text = " " + words.map(SearchWords.singular).joined(separator: " ") + " "
        return phrases.contains { phrase in
            text.contains(" " + SearchWords.tokens(phrase).map(SearchWords.singular).joined(separator: " ") + " ")
        }
    }

    /// The search with the words at `positions` replaced, or removed when `replacement` is nil.
    func text(replacing positions: [Int], with replacement: String?) -> String {
        let first = positions.min()
        return words.indices.compactMap { index -> String? in
            if index == first { return replacement?.lowercased() }
            return positions.contains(index) ? nil : words[index]
        }
        .joined(separator: " ")
    }

    init(_ text: String, history: StudyHistory) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        words = SearchWords.tokens(self.text)
        var tokens = Tokens(words)
        (periods, periodPositions) = Self.takePeriods(from: &tokens, history: history)
        let spans = periods.compactMap { $0.interval(in: history.calendar) }
        if periods.count == 1 {
            period = periods[0]
        } else if let start = spans.map(\.start).min(), let end = spans.map(\.end).max() {
            period = .range(start: start, end: end)
        }
        (parameters, parameterPositions) = Self.takeParameters(from: &tokens)
        tokens.words = tokens.words.map { Self.liftVerbs[$0] ?? SearchWords.singular($0) }
        let known = ChartLifts.of(history)
        takeLifts(from: &tokens, known, unit: history.unit)
        takeMovements(from: &tokens, known)
        muscleGroups += Self.takeMuscles(from: &tokens)
        readIntent(tokens, known)
    }

    private static let questionWords: Set<String> = [
        "what", "when", "where", "which", "who", "why", "how", "do", "does", "did", "am", "is", "are",
        "was", "were", "have", "has", "can", "could", "should", "show", "compare",
    ]
}

/// The words still to read, each with its place in the search.
private struct Tokens {
    var words: [String]
    private(set) var positions: [Int]

    init(_ words: [String]) {
        self.words = words
        positions = Array(words.indices)
    }

    var count: Int { words.count }
    var indices: Range<Int> { words.indices }
    subscript(index: Int) -> String { words[index] }
    func word(at index: Int) -> String { words.indices.contains(index) ? words[index] : "" }

    /// Removes these words and gives back where they were in the search.
    @discardableResult
    mutating func take(_ range: Range<Int>) -> [Int] {
        let taken = Array(positions[range])
        words.removeSubrange(range)
        positions.removeSubrange(range)
        return taken
    }

    mutating func take(_ indices: IndexSet) {
        let kept = words.indices.filter { !indices.contains($0) }
        words = kept.map { words[$0] }
        positions = kept.map { positions[$0] }
    }
}

// MARK: - Dates

extension ChartQuery {
    /// Reads dates as people say them, anywhere in the text: "today", "this week", "last month",
    /// "past 3 months", "October", "Oct 10", "March 2025", "2025", "since September" and
    /// "between May and July". A month without a year means its most recent occurrence, so
    /// "December" asked in November is last December.
    private static func takePeriods(from tokens: inout Tokens, history: StudyHistory) -> ([StudyPeriod], [[Int]]) {
        let reader = PeriodReader(calendar: history.calendar, today: history.today)
        var periods: [StudyPeriod] = []
        var positions: [[Int]] = []
        var index = 0
        while index < tokens.count {
            let word = tokens[index]
            var found: (period: StudyPeriod, length: Int)?
            if word == "since", let start = reader.period(at: index + 1, in: tokens.words),
               let interval = start.period.interval(in: history.calendar) {
                found = (.range(start: interval.start, end: reader.tomorrow), 1 + start.length)
            } else if word == "between" || word == "from", let first = reader.period(at: index + 1, in: tokens.words),
                      ["and", "to", "through", "until"].contains(tokens.word(at: index + 1 + first.length)),
                      let second = reader.period(at: index + 2 + first.length, in: tokens.words),
                      let start = first.period.interval(in: history.calendar)?.start,
                      let end = second.period.interval(in: history.calendar)?.end {
                found = (.range(start: start, end: max(start, end)), 2 + first.length + second.length)
            } else {
                found = reader.period(at: index, in: tokens.words)
            }
            if let found {
                periods.append(found.period)
                positions.append(tokens.take(index..<index + found.length))
            } else {
                index += 1
            }
        }
        return (periods, positions)
    }
}

/// Reads one date phrase relative to today.
private struct PeriodReader {
    let calendar: Calendar
    let today: Date
    var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today }

    private static let units: [String: Calendar.Component] = [
        "day": .day, "days": .day, "week": .weekOfYear, "weeks": .weekOfYear,
        "month": .month, "months": .month, "year": .year, "years": .year,
    ]

    func period(at index: Int, in tokens: [String]) -> (period: StudyPeriod, length: Int)? {
        guard tokens.indices.contains(index) else { return nil }
        let word = tokens[index]
        let next = tokens.indices.contains(index + 1) ? tokens[index + 1] : ""
        let now = parts(today)
        switch (word, next) {
        case ("today", _), ("yesterday", _):
            let day = parts(calendar.date(byAdding: .day, value: word == "today" ? 0 : -1, to: today) ?? today)
            return (.day(year: day.year, month: day.month, day: day.day), 1)
        case ("this", "week"), ("last", "week"), ("previous", "week"), ("past", "week"):
            let date = calendar.date(byAdding: .day, value: word == "this" ? 0 : -7, to: today) ?? today
            guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
            return (.range(start: week.start, end: week.end), 2)
        case ("this", "month"), ("last", "month"), ("previous", "month"):
            let date = parts(calendar.date(byAdding: .month, value: word == "this" ? 0 : -1, to: today) ?? today)
            return (.month(year: date.year, month: date.month), 2)
        case ("this", "year"), ("last", "year"), ("previous", "year"):
            return (.year(now.year - (word == "this" ? 0 : 1)), 2)
        default:
            break
        }
        // "last 3 months", "past 10 days": the span ending today.
        if ["last", "past", "previous"].contains(word), let count = Int(next), (1...999).contains(count),
           tokens.indices.contains(index + 2), let unit = Self.units[tokens[index + 2]],
           let start = calendar.date(byAdding: unit, value: -count, to: tomorrow) {
            return (.range(start: start, end: tomorrow), 3)
        }
        if let year = Self.year(word) { return (.year(year), 1) }
        guard let month = month(at: index, in: tokens) else { return nil }
        let day = Int(next).flatMap { (1...31).contains($0) ? $0 : nil }
        let yearIndex = index + (day == nil ? 1 : 2)
        let stated = tokens.indices.contains(yearIndex) ? Self.year(tokens[yearIndex]) : nil
        let year = stated ?? (month > now.month || (month == now.month && (day ?? 0) > now.day) ? now.year - 1 : now.year)
        let length = 1 + (day == nil ? 0 : 1) + (stated == nil ? 0 : 1)
        if let day { return (.day(year: year, month: month, day: day), length) }
        return (.month(year: year, month: month), length)
    }

    private func parts(_ date: Date) -> (year: Int, month: Int, day: Int) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0, c.month ?? 1, c.day ?? 1)
    }

    private static func year(_ word: String) -> Int? {
        guard word.count == 4, let year = Int(word), (1900...2199).contains(year) else { return nil }
        return year
    }

    /// "May" is also an ordinary word, so it needs a date-like neighbor.
    private func month(at index: Int, in tokens: [String]) -> Int? {
        let word = tokens[index]
        guard word.count >= 3, let month = DataSearchQuery.monthNumber(word) else { return nil }
        guard word == "may" else { return month }
        let previous = index > 0 ? tokens[index - 1] : ""
        let next = tokens.indices.contains(index + 1) ? tokens[index + 1] : ""
        let datePrepositions: Set<String> = [
            "in", "on", "during", "since", "of", "from", "and", "or", "vs", "versus", "than", "between", "to",
        ]
        return datePrepositions.contains(previous) || Int(next) != nil ? month : nil
    }
}

// MARK: - Numbers

extension ChartQuery {
    /// Reads "185 lb", "80 kg", "5 reps", "3 sets", "3x5", "50 minutes", "6 weeks" and "21 days".
    private static func takeParameters(from tokens: inout Tokens) -> ([StudyParameter: Int], [StudyParameter: [Int]]) {
        var parameters: [StudyParameter: Int] = [:]
        var positions: [StudyParameter: [Int]] = [:]
        var index = 0
        while index < tokens.count {
            let word = tokens[index]
            if let scheme = word.wholeMatch(of: #/(\d{1,2})[x×](\d{1,3})/#),
               let sets = Int(scheme.1), let reps = Int(scheme.2) {
                parameters[.sets] = sets
                parameters[.reps] = reps
                positions[.sets] = tokens.take(index..<index + 1)
                positions[.reps] = positions[.sets]
                continue
            }
            guard let number = Double(word), number.isFinite, number >= 0, number <= 100_000,
                  let unit = Self.units[tokens.word(at: index + 1)] else {
                index += 1
                continue
            }
            let parameter: StudyParameter
            switch unit {
            case .load:
                parameter = .load
                parameters[.load] = WeightUnit.pounds.tenthsPounds(from: number)
            case .loadKilograms:
                parameter = .load
                parameters[.load] = WeightUnit.kilograms.tenthsPounds(from: number)
            case .other(let other):
                parameter = other
                parameters[other] = Int(number)
            }
            positions[parameter] = tokens.take(index..<index + 2)
        }
        return (parameters, positions)
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

    /// A bare number beside a lift is a weight in the lifter's unit: "bench 225", "225 bench".
    /// Smaller numbers are more likely reps, so they stay unread.
    private static let bareLoads = 20.0...2000.0
}

// MARK: - Lifts and muscles

/// The lifts a Data search can name: every logged lift by each name it was logged under, and
/// every built-in lift, so a typed lift with no history can say so.
private final class ChartLifts {
    let index: ExerciseSearch.Index
    let logged: Set<String>
    let familiarity: ExerciseFamiliarity
    /// Logged lifts as search reads them, and the name each was last logged under.
    let documents: [String: ExerciseSearch.Document]
    let names: [String: String]

    private init(_ lifts: [(key: String, names: [String], session: StudySession)], own: [String: ExerciseSearch.Document],
                 familiarity: ExerciseFamiliarity) {
        let catalog = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ("catalog:\($0.id)", $0) })
        let logged = Set(lifts.map(\.key))
        self.logged = logged
        let loggedDocuments = lifts.map { lift in
            if let entry = catalog[lift.key] { return ExerciseSearch.Document(entry, otherNames: lift.names) }
            // An own lift brings the joint actions, equipment and muscles set on it, so "rear delts" finds it.
            if var document = own[lift.key] {
                document.names = (lift.names + document.names).uniqued()
                return document
            }
            return ExerciseSearch.Document(key: lift.key, names: lift.names, primary: lift.session.primary ?? .chest,
                                           secondary: lift.session.assisting ?? [], equipment: .bodyweight)
        }
        documents = Dictionary(loggedDocuments.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        names = Dictionary(lifts.map { ($0.key, $0.session.name) }, uniquingKeysWith: { first, _ in first })
        let unlogged = ExerciseCatalog.entries.filter { !logged.contains("catalog:\($0.id)") }.map { ExerciseSearch.Document($0) }
        // Spans read names, not meaning, so the index skips the embedding model.
        index = ExerciseSearch.Index(loggedDocuments + unlogged, encoder: nil)
        self.familiarity = familiarity
    }

    private static var cache: [Int: ChartLifts] = [:]

    /// Search runs on every pause while typing, so each set of logged names is indexed once.
    static func of(_ history: StudyHistory) -> ChartLifts {
        var names: [String: (names: [String], session: StudySession)] = [:]
        var sessions: [String: Set<String>] = [:]
        for session in history.sessions.reversed() where !session.done.isEmpty {
            // Newest name first, so a renamed lift shows its current name.
            for name in [session.name] + session.importedNames where names[session.key]?.names.contains(name) != true {
                names[session.key, default: ([], session)].names.append(name)
            }
            sessions[session.workout, default: []].insert(session.key)
        }
        let lifts = names.map { (key: $0.key, names: $0.value.names, session: $0.value.session) }.sorted { $0.key < $1.key }
        var hasher = Hasher()
        hasher.combine(history.revision)
        for (key, document) in history.ownLifts.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hasher.combine(document)
        }
        for lift in lifts {
            hasher.combine(lift.key)
            hasher.combine(lift.names)
        }
        let id = hasher.finalize()
        if let cached = cache[id] { return cached }
        let order = history.sessions.map(\.workout).uniqued()
        let lifted = ChartLifts(lifts, own: history.ownLifts,
                                familiarity: ExerciseFamiliarity(sessions: order.compactMap { sessions[$0] }))
        if cache.count >= 4 { cache.removeAll() }
        cache[id] = lifted
        return lifted
    }

    /// Logged lifts sorted by how much they are trained.
    func byFamiliarity(_ keys: some Sequence<String>) -> [String] {
        keys.sorted { (familiarity.score($0), names[$1] ?? $1) > (familiarity.score($1), names[$0] ?? $0) }
    }

    /// The muscles a lift works: its listed muscles and those its joint actions move.
    func muscles(of key: String) -> Set<Muscle> {
        guard let document = documents[key] else { return [] }
        return Set([document.primary] + document.secondary + document.structure.muscles.keys)
    }

    /// Logged lifts whose names share a lift word with `words`, most trained first.
    func sharingWords(_ words: [String], except keys: [String] = []) -> [String] {
        let liftWords = Set(words).subtracting(SearchWords.notLiftWords).subtracting(ExerciseSearch.variantWords)
            .filter { ExerciseQuery.equipmentWords[$0] == nil && $0.count >= 3 }
        guard !liftWords.isEmpty else { return [] }
        let matches = documents.values.filter { document in
            !keys.contains(document.key)
                && document.names.contains { !liftWords.isDisjoint(with: ExerciseQuery.words($0)) }
        }
        return byFamiliarity(matches.map(\.key))
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
    private mutating func takeLifts(from tokens: inout Tokens, _ known: ChartLifts, unit: WeightUnit) {
        let query = ExerciseQuery(tokens: tokens.words)
        var taken = IndexSet()
        for span in known.index.liftSpans(in: query, context: .charting(logged: known.logged),
                                          familiarity: known.familiarity, plainWords: Self.plainWords) {
            var source = query.source(of: span.range)
            // "push" and "pull" on their own are training days, read with the muscle groups.
            if source.count == 1, SearchWords.splitDays.contains(where: { $0.phrase == tokens[source.lowerBound] }) { continue }
            var subject = Subject(name: span.name, exerciseKeys: span.keys)
            if span.keys.isEmpty {
                // A built-in lift with no logged sets stays in scope, so its charts are empty and its totals are zero.
                unloggedLifts.append(span.name)
                subject.alternatives = known.sharingWords(Array(query.words[span.range])).prefix(5).compactMap { known.names[$0] }
            } else if span.keys.count > 1 {
                // A muscle word beside a family keeps the lifts that work it: "back fly" is the reverse fly.
                for neighbour in [source.lowerBound - 1, source.upperBound] where !taken.contains(neighbour) {
                    guard let muscles = SearchWords.muscleAliases.first(where: { $0.phrase == tokens.word(at: neighbour) })?.muscles
                    else { continue }
                    let working = span.keys.filter { !known.muscles(of: $0).isDisjoint(with: muscles) }
                    guard !working.isEmpty, working.count < span.keys.count else { continue }
                    subject.exerciseKeys = working
                    source = min(source.lowerBound, neighbour)..<max(source.upperBound, neighbour + 1)
                    break
                }
                let keys = subject.exerciseKeys
                let name = keys.count == 1 ? known.names[keys[0]] ?? span.name : (source.map { tokens[$0] }).joined(separator: " ")
                subject = Subject(name: name, exerciseKeys: keys,
                                  alternatives: (keys + known.sharingWords(Array(query.words[span.range]), except: keys))
                                      .prefix(6).compactMap { known.names[$0] })
            } else {
                subject.alternatives = known.sharingWords(Array(query.words[span.range]), except: span.keys).prefix(5)
                    .compactMap { known.names[$0] }
            }
            // A bare number beside a lift is its weight: "bench 225".
            if parameters[.load] == nil {
                for neighbour in [source.upperBound, source.lowerBound - 1] where !taken.contains(neighbour) {
                    guard let number = Double(tokens.word(at: neighbour)), Self.bareLoads.contains(number) else { continue }
                    parameters[.load] = unit.tenthsPounds(from: number)
                    parameterPositions[.load] = [tokens.positions[neighbour]]
                    taken.insert(neighbour)
                    break
                }
            }
            subject.positions = source.map { tokens.positions[$0] }
            lifts.append(subject)
            taken.insert(integersIn: source)
        }
        tokens.take(taken)
    }

    /// Joint words such as "rear delts" scope the logged lifts that do that movement. With none
    /// logged, they scope the muscles that do it, and say so. A lone muscle word such as "lat"
    /// stays a muscle group.
    private mutating func takeMovements(from tokens: inout Tokens, _ known: ChartLifts) {
        let query = ExerciseQuery(tokens: tokens.words)
        let words = query.words
        var used = Array(repeating: false, count: words.count)
        var taken = IndexSet()
        for length in stride(from: min(3, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let range = start..<start + length
                let term = words[range].joined(separator: " ")
                let movements = JointAnatomy.bundled.movements(forTerm: term)
                guard !movements.isEmpty, range.allSatisfy({ !used[$0] }),
                      length > 1 || (ExerciseQuery.muscleWords[term] == nil && !SearchWords.splitDays.contains { $0.phrase == term }),
                      // "trap bar" is a bar, not the traps.
                      !(term == "trap" && words.indices.contains(start + 1) && words[start + 1] == "bar")
                else { continue }
                let source = query.source(of: range)
                let name = source.map { tokens[$0] }.joined(separator: " ")
                let positions = source.map { tokens.positions[$0] }
                let keys = known.byFamiliarity(known.index.keys(doing: movements, among: known.logged))
                if !keys.isEmpty {
                    lifts.append(Subject(name: name, exerciseKeys: keys, positions: positions,
                                         alternatives: keys.prefix(6).compactMap { known.names[$0] }))
                } else {
                    let movers = movements.flatMap { JointAnatomy.bundled.muscles(for: $0) }.filter(\.isPrime).map(\.group)
                    let groups = Muscle.allCases.filter(movers.contains)
                    guard !groups.isEmpty else { continue }
                    let groupName = groups.map(\.rawValue).formatted(.list(type: .and))
                    muscleGroups.append(Subject(name: groupName, muscles: groups, positions: positions))
                    let work = groups.map { SearchWords.singular($0.rawValue) }.formatted(.list(type: .and))
                    notes.append("No logged lifts work the \(name), so these charts show all \(work) work.")
                }
                for index in range { used[index] = true }
                taken.insert(integersIn: source)
            }
        }
        tokens.take(taken)
    }

    private static func takeMuscles(from tokens: inout Tokens) -> [Subject] {
        var groups: [Subject] = []
        for (phrase, name, muscles) in SearchWords.muscleAliases + SearchWords.splitDays {
            let words = phrase.split(separator: " ").map(String.init)
            while let found = tokens.words.range(of: words) {
                // "back day" and "push day" mean that training.
                let range = tokens.word(at: found.upperBound) == "day" ? found.lowerBound..<found.upperBound + 1 : found
                let positions = tokens.take(range)
                if let index = groups.firstIndex(where: { $0.muscles == muscles }) {
                    groups[index].positions += positions
                } else {
                    groups.append(Subject(name: name, muscles: muscles, positions: positions))
                }
            }
        }
        // "Which muscles have I neglected?" asks about all of them.
        if groups.isEmpty, let index = tokens.words.firstIndex(of: "muscle") {
            groups.append(Subject(name: "all muscles", muscles: Muscle.allCases, positions: tokens.take(index..<index + 1)))
        }
        return groups
    }
}

// MARK: - Intent

extension ChartQuery {
    /// The words left over rank the charts. A chart word with one typo is read as the word, and a
    /// half-typed last word as the chart word it starts: "stregth" is strength, "bench prog" progress.
    /// A word that matches nothing may be a typo of a lift, so it can suggest another search.
    private mutating func readIntent(_ tokens: Tokens, _ known: ChartLifts) {
        let vocabulary = ChartIndex.vocabulary
        var read: [String] = []
        var unknown: [(word: String, position: Int)] = []
        for (index, word) in tokens.words.enumerated() {
            // A bare number, such as "at 185", has no unit to say what it measures.
            guard Double(word) == nil else { continue }
            if vocabulary.contains(word) || SearchWords.notLiftWords.contains(word) || word.count < 3 {
                read.append(word)
            } else if index == tokens.count - 1, let completion = vocabulary.filter({ $0.hasPrefix(word) }).min(by: Self.shorter) {
                read.append(completion)
            } else if let correction = vocabulary.filter({ ExerciseSearch.isTypo(word, of: $0) }).min(by: Self.shorter) {
                read.append(correction)
            } else {
                read.append(word)
                unknown.append((word, tokens.positions[index]))
            }
        }
        intent = read.joined(separator: " ")
        suggestion = Self.suggestion(for: unknown, unlogged: lifts.filter(\.exerciseKeys.isEmpty), in: self, known)
    }

    private static func shorter(_ a: String, _ b: String) -> Bool { (a.count, a) < (b.count, b) }

    /// The closest logged lift, then built-in lift, then chart word to a word that matched nothing;
    /// else, for a lift with no logged sets, the logged lift that shares its name most.
    private static func suggestion(for unknown: [(word: String, position: Int)], unlogged: [Subject],
                                   in query: ChartQuery, _ known: ChartLifts) -> Suggestion? {
        for (word, position) in unknown where word.count >= 4 {
            func distance(_ name: String) -> Int {
                ExerciseQuery.words(name).map { ExerciseSearch.editDistance(word, $0, limit: 2) }.min() ?? 3
            }
            let logged = known.byFamiliarity(known.logged).compactMap { known.names[$0] }
            let candidates = [logged, ExerciseCatalog.entries.map(\.name), Array(ChartIndex.vocabulary).sorted()]
            for names in candidates {
                guard let best = names.map({ ($0, distance($0)) }).filter({ $0.1 <= 2 }).min(by: { $0.1 < $1.1 }) else { continue }
                return Suggestion(name: best.0, text: query.text(replacing: [position], with: best.0))
            }
        }
        for subject in unlogged {
            guard let name = subject.alternatives.first else { continue }
            return Suggestion(name: name, text: query.text(replacing: subject.positions, with: name))
        }
        return nil
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
    static let notLiftWords = stopWords.union(["up", "down", "going", "go", "more", "most", "last", "next", "same", "full", "body"])

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

    /// Training days named by how they move. They never stand for Push Up or a curl.
    static let splitDays: [(phrase: String, name: String, muscles: [Muscle])] = [
        ("push", "push", [.chest, .shoulders, .triceps]), ("pull", "pull", [.back, .biceps]),
    ]
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
