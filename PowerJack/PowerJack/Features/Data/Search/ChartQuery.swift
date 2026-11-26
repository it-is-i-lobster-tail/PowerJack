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

    var isEmpty: Bool { words.isEmpty }
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
        tokens = tokens.flatMap { SearchWords.aliases[$0] ?? [$0] }.map(SearchWords.singular)
        let logged = LoggedLift.all(in: history)
        lifts = Self.takeNamedLifts(from: &tokens, logged: logged)
        unloggedLifts = Self.takeCatalogLifts(from: &tokens)
        // An unlogged lift stays in scope with no sets, so its charts are empty and its totals are zero.
        lifts += unloggedLifts.map { Subject(name: $0) }
        lifts += Self.takeLiftFamilies(from: &tokens, logged: logged)
        muscleGroups = Self.takeMuscles(from: &tokens)
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

/// A logged exercise, named the way search compares names.
private struct LoggedLift {
    let key: String
    let name: String
    let words: [String]
    /// The name without equipment words, so "bench press" finds "Barbell Bench Press".
    let core: [String]
    let sessions: Int

    static func all(in history: StudyHistory) -> [LoggedLift] {
        var counts: [String: (name: String, count: Int)] = [:]
        for session in history.sessions where !session.done.isEmpty {
            counts[session.key, default: (session.name, 0)].count += 1
        }
        return counts.map { key, value in
            let words = SearchWords.tokens(value.name).flatMap { SearchWords.aliases[$0] ?? [$0] }.map(SearchWords.singular)
            let core = words.filter { !SearchWords.equipment.contains($0) }
            return LoggedLift(key: key, name: value.name, words: words, core: core.isEmpty ? words : core,
                              sessions: value.count)
        }
        .sorted { ($0.sessions, $1.name) > ($1.sessions, $0.name) }
    }
}

extension ChartQuery {
    /// A name typed in full, such as "back squat", even when "back" is also a muscle.
    private static func takeNamedLifts(from tokens: inout [String], logged: [LoggedLift]) -> [Subject] {
        var subjects: [Subject] = []
        for lift in logged.sorted(by: { $0.core.count > $1.core.count }) where lift.core.count > 1 {
            guard let range = tokens.range(of: lift.core) else { continue }
            let named = logged.filter { $0.core == lift.core }
            var lower = range.lowerBound
            var matches = named
            if lower > 0, SearchWords.equipment.contains(tokens[lower - 1]) {
                let equipment = tokens[lower - 1]
                let specific = named.filter { $0.words.contains(equipment) }
                if !specific.isEmpty {
                    matches = specific
                    lower -= 1
                }
            }
            subjects.append(Subject(name: matches.count == 1 ? matches[0].name : tokens[lower..<range.upperBound].joined(separator: " "),
                                    exerciseKeys: matches.map(\.key)))
            tokens.removeSubrange(lower..<range.upperBound)
        }
        return subjects
    }

    /// A family of lifts: a run of words that each appear in logged names. "Squat" is every squat,
    /// and "bench" prefers lifts named only bench plus equipment over "Incline Bench Press".
    private static func takeLiftFamilies(from tokens: inout [String], logged: [LoggedLift]) -> [Subject] {
        var subjects: [Subject] = []
        let nameWords = Set(logged.flatMap(\.words)).subtracting(SearchWords.notLiftWords)
            .subtracting(SearchWords.muscleWords).subtracting(ChartIndex.vocabulary)
        var index = 0
        while index < tokens.count {
            guard nameWords.contains(tokens[index]) else {
                index += 1
                continue
            }
            var end = index
            while end + 1 < tokens.count, nameWords.contains(tokens[end + 1]) { end += 1 }
            let run = Array(tokens[index...end])
            let candidates = logged.filter { lift in run.allSatisfy(lift.words.contains) }
            // Prefer names with the fewest words the search didn't ask for.
            let extra = { (lift: LoggedLift) in lift.core.filter { !run.contains($0) }.count }
            if let fewest = candidates.map(extra).min() {
                let matches = candidates.filter { extra($0) == fewest }
                subjects.append(Subject(name: matches.count == 1 ? matches[0].name : run.joined(separator: " "),
                                        exerciseKeys: matches.map(\.key)))
                tokens.removeSubrange(index...end)
            } else {
                index = end + 1
            }
        }
        return subjects
    }

    /// A catalog lift typed in full that has no logged sets, so the gallery can say so.
    private static func takeCatalogLifts(from tokens: inout [String]) -> [String] {
        var names: [String] = []
        for (words, name) in SearchWords.catalogNames {
            guard let range = tokens.range(of: words) else { continue }
            names.append(name)
            tokens.removeSubrange(range)
        }
        return names
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

    /// Shorthand lifters type, expanded to the words in exercise names.
    static let aliases: [String: [String]] = [
        "ohp": ["overhead", "press"], "rdl": ["romanian", "deadlift"], "rdls": ["romanian", "deadlift"],
        "pushup": ["push", "up"], "pushups": ["push", "up"], "pullup": ["pull", "up"], "pullups": ["pull", "up"],
        "chinup": ["chin", "up"], "chinups": ["chin", "up"], "ups": ["up"], "squatted": ["squat"], "benched": ["bench"],
        "deadlifted": ["deadlift"], "pressing": ["press"], "curling": ["curl"], "rowing": ["row"],
    ]

    static let equipment: Set<String> = ["barbell", "dumbbell", "cable", "machine", "kettlebell", "smith", "ez", "bar"]

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

    /// Catalog names without equipment words, longest first. Single words are lift families.
    static let catalogNames: [([String], String)] = ExerciseCatalog.entries.compactMap { entry in
        let words = tokens(entry.name).flatMap { aliases[$0] ?? [$0] }.map(singular).filter { !equipment.contains($0) }
        return words.count > 1 ? (words, entry.name) : nil
    }
    .sorted { $0.0.count > $1.0.count }
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
