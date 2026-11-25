import Foundation
import SwiftData

/// Each chart describes the questions it answers independently of its example lift.
extension TrainingStudy {
    var searchVocabulary: Set<String> {
        let labels = [searchTerms, genericName, searchMetadata.question, searchMetadata.measure]
            .joined(separator: " ").lowercased()
        return Set(labels.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { StudySearch.term(String($0)) })
            .union(searchMetadata.keywords.map(StudySearch.term))
    }

    var searchTerms: String {
        switch self {
        case .legWork: "volume workload weekly set credits muscle exposure direct assisting secondary"
        case .armReps: "volume workload repetitions reps monthly daily totals direct assisting"
        case .gluteSources: "volume workload sources exercise contributions direct assisting set credits"
        case .frequency: "volume frequency working sets weekday calendar schedule distribution"
        case .repRanges: "volume repetitions reps bands ranges distribution working sets"
        case .repChanges: "volume reps repetitions changes deltas increase decrease comparison periods"
        case .legMax: "strength progress estimated max estimates e1rm 1rm trends progression history"
        case .records: "strength records personal best pr load reps repetition maximum"
        case .fixedSquat: "strength reps fixed weight load capacity performance"
        case .milestones: "strength milestones first achieved reps load progression"
        case .repeatBench: "strength repeatability repeatable sets prescribed reps target consistency"
        case .yearlyRecords: "strength annual yearly lifetime personal records pr best"
        case .skipped: "adherence compliance skipped missed planned completed sets"
        case .effort: "intensity effort difficulty rir reserve reported prescribed target"
        case .lastCurl: "performance recent sessions comparison working sets load reps"
        case .benchSets: "performance fatigue dropoff across sets reps load sequence"
        case .substitutions: "programming substitutions swaps replacements planned actual exercise"
        case .exerciseOrder: "strength programming order position early late workout performance"
        case .returnToSquat: "strength recovery return breaks layoffs detraining baseline"
        case .blocks: "strength gains training blocks cycles progression"
        case .duration: "duration time budget completion minutes routine workout length"
        case .goal: "volume goal cumulative progress repetitions reps target"
        case .recency: "recovery recency frequency days since last direct training"
        case .repMix: "volume intensity load weight mix distribution rep ranges"
        case .relationship: "strength relationship correlation paired lifts scatter comparison"
        case .typicalBench: "strength baseline typical recent range median variability"
        case .forecast: "strength forecast errors estimates accuracy prediction prior median"
        case .squatSuccess: "performance success attempts opening prescribed target reps load"
        case .missingEstimates: "strength estimates eligibility missing gaps high reps coverage"
        case .pushups: "volume performance bodyweight best set total reps repetitions trend"
        case .tonnage: "volume workload tonnage total external load change sessions contributions"
        case .sessionLedger: "workout history ledger first day log sets details recorded"
        }
    }
}

extension StudyOptions {
    static let upperBody: [Muscle] = [.chest, .shoulders, .back, .biceps, .triceps, .forearms]

    var searchMuscleName: String? {
        let group = Set(muscles)
        if group == Set(Muscle.allCases) { return "all muscles" }
        if group == [.biceps, .triceps] { return "arms" }
        if group == Set(StudyHistory.legs) { return "legs" }
        if group == Set(Self.upperBody) { return "upper body" }
        if group == [.abs, .obliques] { return "core" }
        return nil
    }
}

struct StudySearchFocus: Equatable, Codable {
    let name: String
    let muscles: [Muscle]
    let exercises: [String]

    func describes(_ options: StudyOptions) -> Bool {
        Set(muscles) == Set(options.muscles) && Set(exercises) == Set(options.exerciseKeys)
    }
}

struct StudySearch {
    let queryText: String
    let knownExerciseNames: [String]
    private let empty: Bool
    private var period: StudyPeriod?
    private let terms: Set<String>
    private var muscles: [Muscle]
    private var keys: [String]
    private let loadedKeys: Set<String>
    private let bodyweightKeys: Set<String>
    private var subject: String
    private var requested: [StudyParameter: Int]
    private let termWeights: [String: Int]

    nonisolated static func term(_ word: String) -> String {
        switch word {
        case "stronger", "strongest": "strength"
        case "volume", "workload": "volume"
        case "1rm", "e1rm", "maxes", "maximum": "max"
        case "estimated", "estimates": "estimate"
        case "sets": "set"
        case "repetition", "repetitions", "reps": "rep"
        case "records", "prs": "record"
        case "muscles": "muscle"
        case "exercises": "exercise"
        case "workouts": "workout"
        case "sessions": "session"
        case "totals": "total"
        case "weekly", "weeks": "week"
        case "months", "monthly": "month"
        case "days": "day"
        case "weekdays": "weekday"
        case "gained": "increase"
        case "lost": "decrease"
        case "changes", "changed": "change"
        case "trends", "trending": "trend"
        case "improved", "improvement", "progression", "progressed": "progress"
        case "contributed", "contribution": "contributions"
        case "scheduled": "planned"
        case "swap", "swapped", "replaced": "substitutions"
        case "skipping", "miss": "skipped"
        case "accuracy", "accurate", "predicted": "forecast"
        case "hard", "hardest", "easy": "effort"
        case "lift", "lifts": "exercise"
        case "skips", "skip": "skipped"
        case "block": "blocks"
        case "plateaued", "stalled": "progress"
        case "weight", "weights", "loads": "load"
        case "recover", "recovered", "regain": "recovery"
        case "compared", "compare", "comparing": "comparison"
        case "dropping", "drop", "falloff": "dropoff"
        case "substitute", "substitution", "swapping": "substitutions"
        case "bests": "best"
        case "heavier": "heaviest"
        case "hit", "targets": "target"
        case "credited", "credit": "credits"
        case "contribute", "contributing": "contributions"
        case "peaked", "peak": "best"
        case "typical", "usually": "usual"
        case "both": "together"
        default: word
        }
    }

    private static let filler = Set("""
        a about after all am an and are as at be been before between by can did do does during each
        ever every for from get getting had has have how i in into is it last me much many more most
        my of often on or our out over per recently show so than that the their them then there these
        this those through to two vs was were what when where which who why will with would you
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    private static let catalogPatterns = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ($0.id, $0.profile.pattern) })

    private static let documentFrequency: [String: Int] = {
        var counts: [String: Int] = [:]
        for study in TrainingStudy.allCases {
            for term in study.searchVocabulary { counts[term, default: 0] += 1 }
        }
        return counts
    }()

    init(query: String, history: StudyHistory, exercises: [Exercise], index: ExerciseChartSearch.Index?) {
        knownExerciseNames = exercises.map(\.exerciseName)
        queryText = query
        empty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var text = query.lowercased().trimmingCharacters(in: .punctuationCharacters)
        // Dates work inside questions as well as at the end of a short filter.
        let calendarDate = #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)(?:\s+\d{1,2}\b,?)?(?:\s+\d{4}\b)?\b|\b(?:19|20)\d{2}\b"#
        if let range = text.range(of: calendarDate, options: .regularExpression) {
            let dateText = String(text[range])
            text.replaceSubrange(range, with: " ")
            text += " " + dateText
        }
        let year = history.calendar.component(.year, from: history.today)
        // Relative calendar phrases use the same editable month/year controls as explicit dates.
        let relativePeriods: [(String, Calendar.Component, Int)] = [
            ("this month", .month, 0), ("last month", .month, -1), ("previous month", .month, -1),
            ("this year", .year, 0), ("last year", .year, -1), ("previous year", .year, -1),
        ]
        for (phrase, component, offset) in relativePeriods {
            guard let range = text.range(of: phrase),
                let date = history.calendar.date(byAdding: component, value: offset, to: history.today) else { continue }
            let y = history.calendar.component(.year, from: date)
            let m = history.calendar.component(.month, from: date)
            text.replaceSubrange(range, with: " ")
            text += component == .year ? " \(y)" : " \(history.calendar.monthSymbols[m - 1]) \(y)"
            break
        }
        let parsed = DataSearchQuery(text)
        switch parsed.dateFilter {
        case .year(let value): period = .year(value)
        case .month(let month, let value): period = .month(year: value ?? year, month: month)
        case .day(let day, let month, let value): period = .day(year: value ?? year, month: month, day: day)
        case nil: period = nil
        }

        var phrase = parsed.exerciseText.lowercased()
        phrase = phrase.replacingOccurrences(of: #"(\d+)\s*[×x]\s*(\d+)\b"#, with: "$1 sets $2 reps", options: .regularExpression)
        let pattern = #"\b(\d+(?:\.\d+)?)\s*(pounds?|lbs?|kilograms?|kgs?|reps?|repetitions?|sets?|weeks?|sessions?|minutes?|days?)\b"#
        var parameters: [StudyParameter: Int] = [:]
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)).reversed() {
                guard let range = Range(match.range, in: phrase),
                    let number = Range(match.range(at: 1), in: phrase).flatMap({ Double(phrase[$0]) }),
                    let unit = Range(match.range(at: 2), in: phrase).map({ String(phrase[$0]) }),
                    number.isFinite, number <= 100000 else { continue }
                let key: StudyParameter
                let value: Int
                if unit.hasPrefix("lb") || unit.hasPrefix("pound") || unit.hasPrefix("k") {
                    key = .load
                    value = (unit.hasPrefix("k") ? WeightUnit.kilograms : .pounds).tenthsPounds(from: number)
                } else {
                    switch unit {
                    case "set", "sets": key = .sets
                    case "week", "weeks": key = .weeks
                    case "session", "sessions": key = .sessions
                    case "minute", "minutes": key = .minutes
                    case "day", "days": key = .comparisonDays
                    default: key = .reps
                    }
                    value = Int(number)
                }
                parameters[key] = value
                phrase.replaceSubrange(range, with: " ")
            }
        }
        requested = parameters
        let liftInflections = ["squats": "squat", "deadlifts": "deadlift", "curls": "curl", "lunges": "lunge",
                               "rows": "row", "presses": "press", "raises": "raise", "pushups": "push-up", "pushup": "push-up"]
        var words = phrase.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).flatMap { token -> [String] in
            let normalized = liftInflections[String(token)] ?? String(token)
            return normalized.split(separator: "-").map(String.init)
        }
        // Preserve anatomy words that identify a named lift, such as “back squat”.
        let liftNames = Set(history.sessions.map(\.name) + exercises.map(\.exerciseName))
        let liftPhrases = liftNames.map { name in
            name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        var focus = Set<Muscle>()
        let aliases: [(String, [Muscle])] = [
            ("upper body", StudyOptions.upperBody), ("lower body", StudyHistory.legs),
            ("legs", StudyHistory.legs), ("arms", [.biceps, .triceps]), ("core", [.abs, .obliques]),
        ] + Muscle.allCases.map { ($0.rawValue, [$0]) }
        for (name, group) in aliases {
            let tokens = name.split(separator: " ").map(String.init)
            if let start = words.indices.first(where: { Array(words.dropFirst($0).prefix(tokens.count)) == tokens }) {
                let end = start + tokens.count
                if end < words.count && liftPhrases.contains(where: { name in
                    name.indices.dropLast().contains { name[$0] == words[end - 1] && name[$0 + 1] == words[end] }
                }) { continue }
                focus.formUnion(group)
                words.removeSubrange(start..<start + tokens.count)
            }
        }
        if focus.isEmpty && words.contains("muscles") {
            focus = Set(Muscle.allCases)
        }
        muscles = Muscle.allCases.filter(focus.contains)
        let movementWords = Set(["press", "pressing", "squat", "bench", "curl", "lunge", "push", "up", "row", "deadlift"])
        var vocabulary = Set(Self.documentFrequency.keys).subtracting(movementWords)
        if !words.contains("push") { vocabulary.insert("up") }
        let meaningful = words.filter { !Self.filler.contains($0) }
        let recognized = Set(meaningful.map(Self.term)).intersection(vocabulary)
        terms = recognized
        termWeights = Dictionary(uniqueKeysWithValues: recognized.map { word in
            (word, max(1, 15 - (Self.documentFrequency[word] ?? 0)))
        })
        let residual = meaningful.filter { !vocabulary.contains(Self.term($0)) }
        let names = Set(liftPhrases.joined())
        let exerciseWords = residual.filter { names.contains($0) || movementWords.contains($0) }
        let exerciseText = (!exerciseWords.isEmpty ? exerciseWords :
            (recognized.isEmpty && focus.isEmpty && parameters.isEmpty ? residual : [])).joined(separator: " ")
        subject = exerciseText
        loadedKeys = Set(history.sessions.filter(\.loaded).map(\.key))
        bodyweightKeys = Set(history.sessions.filter(\.repsOnly).map(\.key))
        var matched = Set<String>()
        if !exerciseText.isEmpty {
            let results = index?.results(for: exerciseText)
            let press = exerciseText == "press" || exerciseText == "pressing"
            let exactWords = exerciseText.split(separator: " ").map(String.init)
            // Named lifts match actual names. The exercise index can also return related
            // movements, which are helpful only when the name itself has no literal match.
            let hasNamedLift = liftPhrases.contains { name in
                exactWords.allSatisfy(name.contains)
            }
            for exercise in exercises {
                let rank = results?.ranks[exercise.persistentModelID]
                let pattern = exercise.movementPattern ?? exercise.catalogID.flatMap { Self.catalogPatterns[$0] }
                let pressing = press && [.horizontalPress, .overheadPress, .legPress, .dip].contains(pattern)
                let words = exercise.exerciseName.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                let literal = exactWords.allSatisfy(words.contains)
                if pressing || literal || (!hasNamedLift && !press && rank != nil) {
                    matched.insert(exercise.syncKey ?? exercise.exerciseName)
                }
            }
            for session in history.sessions where session.name.localizedCaseInsensitiveContains(exerciseText) {
                matched.insert(session.key)
            }
        }
        let selected = history.sessions.filter {
            (focus.isEmpty || $0.primary.map(focus.contains) == true)
                && (exerciseText.isEmpty || matched.contains($0.key))
        }
        let keyNames = Dictionary(selected.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
        keys = keyNames.keys.sorted { lhs, rhs in
            let left = keyNames[lhs] ?? ""
            let right = keyNames[rhs] ?? ""
            let leftLiteral = !exerciseText.isEmpty && left.localizedCaseInsensitiveContains(exerciseText)
            let rightLiteral = !exerciseText.isEmpty && right.localizedCaseInsensitiveContains(exerciseText)
            return leftLiteral == rightLiteral ? (left, lhs) < (right, rhs) : leftLiteral
        }
    }

    func score(for study: TrainingStudy, options: StudyOptions) -> Int {
        let vocabulary = study.searchVocabulary
        let matched = terms.intersection(vocabulary)
        var score = matched.reduce(0) { $0 + (termWeights[$1] ?? 1) * 10 }
        score -= (terms.count - matched.count) * 8
        if !muscles.isEmpty && study.hasMuscleFocus { score += 20 }
        if subject.isEmpty && !muscles.isEmpty && terms.isEmpty {
            switch study {
            case .legWork: score += 14
            case .frequency: score += 12
            case .armReps: score += 10
            case .legMax: score += 8
            default: break
            }
        }
        if study == .legMax && (terms == ["strength"] || (!subject.isEmpty && terms == ["progress"])) { score += 50 }
        if terms.contains("neglected") && study == .recency { score += 50 }
        if terms == ["volume"] && [.legWork, .armReps, .gluteSources, .frequency].contains(study) { score += 25 }
        if !subject.isEmpty && study.multipleExercises { score += 10 }
        if let first = options.exerciseKeys.first, first == keys.first { score += 2 }
        return score
    }

    func matches(for study: TrainingStudy, saved: StudyOptions, modelSelected: Bool = false) -> [StudyOptions] {
        if empty { return [saved] }
        let vocabulary = study.searchVocabulary
        let broadIntents = terms.intersection(["volume", "strength", "adherence", "frequency", "recovery", "duration"])
        if !modelSelected && (!broadIntents.isSubset(of: vocabulary) || (!terms.isEmpty && terms.isDisjoint(with: vocabulary))) { return [] }
        var options = saved
        options.showsFullSearchTitle = true
        if let period { options.period = period }
        for (key, value) in requested {
            let supported = study.parameters.map(\.0)
            let target: StudyParameter = key == .reps && supported.contains(.goalReps) ? .goalReps :
                (key == .comparisonDays && supported.contains(.gapDays) ? .gapDays : key)
            guard supported.contains(target), target.range.contains(value) else { return [] }
            options.parameters[target] = value
        }
        guard !subject.isEmpty || !muscles.isEmpty else {
            return !modelSelected && terms.isEmpty && period == nil && requested.isEmpty ? [] : [options]
        }
        if !subject.isEmpty && keys.isEmpty { return [] }
        options.searchFocus = nil
        options.muscles = []
        options.exerciseKeys = []
        options.secondExercise = nil
        if study.hasMuscleFocus && subject.isEmpty {
            options.muscles = muscles
            let name = subject.isEmpty ? options.searchMuscleName : subject
            if let name {
                options.searchFocus = .init(name: name, muscles: muscles, exercises: options.exerciseKeys)
            }
            return [options]
        }
        let eligible = keys.filter { key in
            if study == .pushups { return bodyweightKeys.contains(key) }
            if vocabulary.contains("strength") || [.tonnage, .repMix, .squatSuccess].contains(study) {
                return loadedKeys.contains(key)
            }
            return true
        }
        guard !eligible.isEmpty else { return [] }
        if study == .legWork { return [] } // Aggregate log credits cannot identify the contributing exercise.
        if study == .relationship {
            guard eligible.count >= 2 else { return [] }
            options.exerciseKeys = [eligible[0]]
            options.secondExercise = eligible[1]
            return [options]
        }
        if study.multipleExercises {
            options.exerciseKeys = eligible
            options.muscles = muscles
            let name = subject.isEmpty ? options.searchMuscleName : subject
            if let name {
                options.searchFocus = .init(name: name, muscles: muscles, exercises: options.exerciseKeys)
            }
            return [options]
        }
        return eligible.map { key in
            var variant = options
            variant.exerciseKeys = [key]
            return variant
        }
    }
}

extension StudySearch {
    /// Preserve the user's explicit filters. A model can nominate measures but cannot create a lift in history.
    func interpreted(_ plan: StudyQuestion, query: String, history: StudyHistory,
                     exercises: [Exercise]) -> StudySearch? {
        var scoped = self
        let filter = StudySearch(query: plan.filters, history: history, exercises: exercises, index: nil)
        // Only the input can supply anatomy, dates, and numeric thresholds.
        let timeframe = plan.timeframe
        if !timeframe.isEmpty {
            guard query.localizedCaseInsensitiveContains(timeframe) else { return nil }
            let time = StudySearch(query: timeframe, history: history, exercises: exercises, index: nil)
            if scoped.period == nil { scoped.period = time.period }
        }
        guard filter.period == nil || filter.period == scoped.period else { return nil }
        let numberWords = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let tokens = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        if tokens.contains("yesterday") || tokens.contains("today") {
            let day = history.calendar.date(byAdding: .day, value: tokens.contains("yesterday") ? -1 : 0, to: history.today) ?? history.today
            let parts = history.calendar.dateComponents([.year, .month, .day], from: day)
            if let y = parts.year, let m = parts.month, let d = parts.day { scoped.period = .day(year: y, month: m, day: d) }
        }
        if let range = query.lowercased().range(of: #"\bset of (?:[0-9]+|one|two|three|four|five|six|seven|eight|nine|ten)\b"#, options: .regularExpression),
           let token = query.lowercased()[range].split(separator: " ").last {
            let count = Int(token) ?? numberWords.firstIndex(of: String(token)).map { $0 + 1 }
            if let count, StudyParameter.reps.range.contains(count) { scoped.requested[.reps] = count }
        }
        for (key, value) in filter.requested where scoped.requested[key] == nil {
            let number = key == .load ? value / 10 : value
            if tokens.contains(String(number)) || ((1...10).contains(number) && tokens.contains(numberWords[number - 1])) {
                scoped.requested[key] = value
            }
        }

        let subjects = plan.namedExercises
        if !subjects.isEmpty {
            let names = Dictionary(history.sessions.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
            var resolved: [String] = []
            for subject in subjects {
                let words = exerciseWords(subject)
                let original = LoggedStudyQuestion(query, history: history)
                let allowed = exerciseWords(query).union(original.liftNames.flatMap { exerciseWords($0) })
                guard !words.isEmpty, words.isSubset(of: allowed) else { return nil }
                let matches = names.keys.filter { words.isSubset(of: exerciseWords(names[$0] ?? "")) }.sorted()
                guard !matches.isEmpty else { return nil }
                // A comparison needs one identifiable lift on each side.
                if subjects.count > 1 {
                    let exact = matches.filter { exerciseWords(names[$0] ?? "") == words }
                    guard let key = exact.first ?? (matches.count == 1 ? matches.first : nil),
                          !resolved.contains(key) else { return nil }
                    resolved.append(key)
                } else {
                    let exact = matches.filter { exerciseWords(names[$0] ?? "") == words }
                    guard let key = exact.count == 1 ? exact.first : (matches.count == 1 ? matches.first : nil) else { return nil }
                    resolved = [key]
                }
            }
            scoped.subject = resolved.compactMap { names[$0] }.joined(separator: " and ")
            scoped.keys = resolved
        } else if plan.wholeTraining && scoped.muscles.isEmpty && scoped.subject.isEmpty {
            scoped.muscles = Muscle.allCases
        }
        return scoped
    }

    private func exerciseWords(_ text: String) -> Set<String> {
        let aliases = ["chinups": "chin up", "chinup": "chin up", "pushups": "push up", "pushup": "push up",
                       "pullups": "pull up", "pullup": "pull up", "rdl": "romanian deadlift", "ohp": "overhead press"]
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return Set(words.flatMap { word in
            (aliases[String(word)] ?? String(word)).split(separator: " ").map {
                $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : String($0)
            }
        })
    }
}
