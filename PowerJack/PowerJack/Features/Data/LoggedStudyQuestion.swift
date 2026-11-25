import Foundation

/// Explicit question scopes stay separate from fuzzy gallery discovery. In particular, a
/// missing named lift must never silently resolve to a different exercise in a comparison.
struct LoggedStudyQuestion {
    let original: String
    private(set) var text: String
    let interval: DateInterval?
    let periodLabel: String
    let muscles: Set<Muscle>
    let liftNames: [String]
    let textWithoutLiftNames: String

    init(_ query: String, history: StudyHistory, knownNames: [String] = []) {
        original = query.trimmingCharacters(in: .whitespacesAndNewlines)
        text = Self.normalized(original)
        interval = Self.dateRange(text, history: history)
        if let interval {
            let end = interval.end.addingTimeInterval(-1)
            periodLabel = history.calendar.isDate(interval.start, inSameDayAs: end)
                ? history.day(interval.start) : "\(history.day(interval.start)) – \(history.day(end))"
        } else {
            periodLabel = "Recorded history"
        }
        // Timing phrases such as “back-to-back days” contain no anatomical subject.
        var remainder = " " + text.replacingOccurrences(of: "back to back", with: "consecutive") + " "
        // “Pull up my chart” is a request to display something, not a second lift.
        remainder = remainder.replacingOccurrences(of: #"\bpull up (?=the |my |a |an |some )"#, with: "show ", options: .regularExpression)
        var subjects: [String] = []
        // Consume complete catalog/custom names before their shorter aliases. A front
        // squat or a sumo deadlift must retain its variant when one was specified.
        let names = Set(history.sessions.map(\.name)).union(Self.catalogNames).union(knownNames)
        // Prefer a specific lift over a shorter family alias, including plural input.
        let matched = names.compactMap { name -> (String, String)? in
            let normalized = Self.normalized(name)
            let words = normalized.split(separator: " ")
            guard words.count >= 2 || knownNames.contains(name) else { return nil }
            let plural = normalized + (normalized.hasSuffix("ss") ? "es" : "s")
            for spelling in [normalized, plural] where remainder.contains(" " + spelling + " ") {
                return (spelling, name)
            }
            return nil
        }
        let bySpelling = Dictionary(grouping: matched, by: { $0.0 })
        var aliases: [String: String] = [:]
        for (name, forms) in Self.lifts {
            for form in forms { aliases[form] = name }
        }
        let phrases = Set(bySpelling.keys).union(aliases.keys)
        for phrase in phrases.sorted(by: { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }) {
            guard remainder.contains(" " + phrase + " ") else { continue }
            let matches = bySpelling[phrase] ?? []
            guard let name = matches.count == 1 ? matches[0].1 : aliases[phrase] else { continue }
            if !subjects.contains(name) { subjects.append(name) }
            remainder = remainder.replacingOccurrences(of: " " + phrase + " ", with: " ")
        }
        // Exact names also work for user-created exercises.
        if subjects.isEmpty {
            let names = Set(history.sessions.map(\.name))
            if let named = names.filter({ remainder.contains(" " + Self.normalized($0) + " ") })
                .max(by: { $0.count < $1.count }) { subjects.append(named) }
        }
        if subjects == ["Deadlift"], text.contains("romanian"),
           text.range(of: #"\b(?:mean|specifically) (?:the )?romanian\b|\bromanian (?:kind|variant|variation|version)\b"#, options: .regularExpression) != nil {
            subjects = ["Romanian deadlift"]
        }
        liftNames = subjects
        textWithoutLiftNames = remainder.trimmingCharacters(in: .whitespaces)
        var focus = Set<Muscle>()
        for muscle in Muscle.allCases {
            if remainder.contains(" " + muscle.rawValue + " ") { focus.insert(muscle) }
        }
        for (word, group) in Self.anatomy where remainder.contains(" " + word + " ") {
            focus.formUnion(group)
        }
        muscles = focus
    }

    private static func normalized(_ value: String) -> String {
        // A period at the end of an exercise name is punctuation. Keep decimal loads intact.
        let value = value.contains(".") ? value.replacingOccurrences(
            of: #"(?<![0-9])\.|\.(?![0-9])"#, with: " ", options: .regularExpression) : value
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "'" })
            .joined(separator: " ")
    }

    private static let catalogNames = ExerciseCatalog.entries.map(\.name)

    private static let anatomy: [(String, [Muscle])] = [
        ("legs", StudyHistory.legs), ("leg", StudyHistory.legs), ("lower body", StudyHistory.legs),
        ("arms", [.biceps, .triceps]), ("upper body", StudyOptions.upperBody),
        ("pecs", [.chest]), ("quad", [.quads]), ("hamstring", [.hamstrings]),
        ("delts", [.shoulders]), ("calf", [.calves]), ("shoulder", [.shoulders])
    ]

    // Match specific variants before their shorter family names.
    private static let lifts: [(String, [String])] = [
        ("Incline bench press", ["incline bench press", "incline bench", "incline press", "incline"]),
        ("Bench press", ["flat bench press", "flat bench", "bench press", "bench"]),
        ("Dumbbell shoulder press", ["dumbbell shoulder press"]),
        ("Overhead press", ["overhead presses", "overhead press", "ohp"]),
        ("Romanian deadlift", ["romanian deadlifts", "romanian deadlift", "rdls", "rdl"]),
        ("Deadlift", ["conventional deadlift", "deadlifts", "deadlift"]),
        ("Kettlebell swing", ["kettlebell swings", "kettlebell swing"]),
        ("Front squat", ["front squats", "front squat"]),
        ("Calf raise", ["calf raises", "calf raise"]),
        ("Back squat", ["back squats", "back squat", "squatted", "squats", "squat"]),
        ("Hamstring curl", ["hamstring curls", "hamstring curl", "leg curls", "leg curl"]),
        ("Dumbbell curl", ["dumbbell curls", "dumbbell curl"]),
        ("Curl", ["curls", "curl"]), ("Cable row", ["cable rows", "cable row"]),
        ("Weighted dip", ["weighted dips", "weighted dip"]),
        ("Push-up", ["push ups", "push up", "pushups", "pushup"]),
        ("Chin-up", ["chin ups", "chin up", "chinups", "chinup"]),
        ("Pull-up", ["pull ups", "pull up", "pullups", "pullup"]),
        ("Lateral raise", ["lateral raises", "lateral raise"])
    ]

    func matchesLift(_ session: StudySession, named name: String) -> Bool {
        let label = Self.normalized(session.name)
        switch name {
        case "Bench press": return label.contains("bench") && label.contains("press") && !label.contains("incline") && !label.contains("decline") && !label.contains("close grip")
        case "Incline bench press": return label.contains("incline") && label.contains("press")
        case "Back squat": return session.key == StudyHistory.squat || label == "squat" || label.hasSuffix("back squat")
        case "Deadlift": return label == "deadlift" || label == "barbell deadlift" || label.contains("conventional deadlift")
        case "Romanian deadlift": return label.contains("romanian deadlift")
        case "Overhead press": return label.contains("overhead press") || label == "military press" || session.movementPattern == .overheadPress
        case "Weighted dip": return label.contains("dip") && (label.contains("weighted") || session.done.contains { ($0.load ?? 0) > 0 })
        case "Hamstring curl": return label.contains("leg curl") || label.contains("hamstring curl")
        case "Curl", "Dumbbell curl":
            return label.contains("curl") && (session.primary == .biceps || session.movementPattern == .elbowFlexion)
                && (name != "Dumbbell curl" || label.contains("dumbbell"))
        case "Cable row": return label.contains("cable") && label.contains("row")
        default: return label.contains(Self.normalized(name))
        }
    }

    func includes(_ date: Date) -> Bool {
        interval.map { $0.start <= date && date < $0.end } ?? true
    }

    func sessions(_ history: StudyHistory) -> [StudySession] {
        history.sessions.filter { slot in
            includes(slot.date) && (liftNames.isEmpty || liftNames.contains { matchesLift(slot, named: $0) })
                && (muscles.isEmpty || slot.primary.map(muscles.contains) == true)
        }
    }

    var includesWarmups: Bool {
        guard text.range(of: #"\b(?:working sets? only|without|excluding|ignore|ignoring|except|not including)\b"#,
                         options: .regularExpression) == nil else { return false }
        if text.range(of: #"\binclud(?:e|ing) (?:my |the )?warm ?ups?\b"#, options: .regularExpression) != nil {
            return true
        }
        guard text.range(of: #"\bworking (?:reps?|sets?|repetitions?)\b"#, options: .regularExpression) == nil else { return false }
        return text.range(of: #"\b(?:all (?:my |the )?(?:recorded|logged) sets|every (?:single )?(?:rep|repetition|set))\b"#,
                          options: .regularExpression) != nil
    }

    func missingHistoryNote(_ history: StudyHistory) -> String? {
        // A date inside a wider requested range does not establish that the whole range is empty.
        if let interval, history.calendar.isDate(interval.start, inSameDayAs: interval.end.addingTimeInterval(-1)) {
            let words = Set(text.split(separator: " "))
            if !words.isDisjoint(with: ["days", "week", "weeks", "month", "months", "year", "years", "before", "after", "between", "since", "through", "until", "past", "ending"]) { return nil }
        }
        let includeWarmups = includesWarmups
        let missing = liftNames.filter { name in
            !history.sessions.contains { slot in
                includes(slot.date) && matchesLift(slot, named: name)
                    && (!slot.done.isEmpty || (includeWarmups && slot.warmups.contains { $0.status == .complete }))
            }
        }
        if !missing.isEmpty {
            let names = missing.joined(separator: ", ")
            let period = interval == nil ? "in your workout log" : "in this period (\(periodLabel))"
            return "No completed \(includeWarmups ? "sets" : "working sets") for \(names) \(period)."
        }
        guard liftNames.isEmpty else { return nil }
        let hasWorkout = history.workouts.contains { $0.date.map(includes) == true && $0.status != .skipped }
            || history.sessions.contains { includes($0.date) }
        guard !hasWorkout else { return nil }
        return interval == nil ? "Your workout log has no recorded workouts yet." : "No workouts were logged in this period (\(periodLabel))."
    }

    func answer(_ id: TrainingStudy, _ title: String, _ summary: String, columns: [String], rows: [[String]],
                scope: String? = nil, insufficient: Bool? = nil) -> StudyResult {
        let table = StudyTable(columns: columns, rows: rows)
        var result = StudyResult(id: id, scope: [scope, periodLabel].compactMap { $0 }.joined(separator: " · "),
                                 figure: rows.isEmpty ? nil : .table(table), summary: (insufficient ?? rows.isEmpty) ? "Not enough data. " + summary : summary)
        if title == "Not enough data" { result.summary = summary }
        result.title = StudyTitle(full: title, caption: title)
        result.question = original
        if rows.isEmpty { result.emptyReason = summary }
        return result
    }

    static func months(in text: String) -> Set<Int> {
        Set(text.split(separator: " ").compactMap { DataSearchQuery.monthNumber($0) })
    }

    /// A span asks for all records between its endpoints, even when two months are named.
    private var cumulativeMonthSpan: Bool {
        text.contains("since ") && text.contains("end of ")
    }

    private static func dateRange(_ text: String, history: StudyHistory) -> DateInterval? {
        let calendar = history.calendar
        let now = history.today
        for (word, unit, offset) in [("today", Calendar.Component.day, 0), ("yesterday", .day, -1),
                                     ("this week", .weekOfYear, 0), ("last week", .weekOfYear, -1),
                                     ("this month", .month, 0), ("last month", .month, -1),
                                     ("this year", .year, 0), ("last year", .year, -1)] {
            if word == "last week" && (text.contains("last week of") || text.contains("first and last")) { continue }
            guard (" " + text + " ").contains(" " + word + " "),
                  let reference = calendar.date(byAdding: unit, value: offset, to: now) else { continue }
            return calendar.dateInterval(of: unit, for: reference)
        }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let words = text.split(separator: " ").map(String.init)
        let counts = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "eight": 8, "ten": 10, "twelve": 12]
        if let i = words.firstIndex(of: "weeks"), i > 0,
           let n = Int(words[i - 1]) ?? counts[words[i - 1]], (1...520).contains(n),
           let start = calendar.date(byAdding: .day, value: -7*n, to: tomorrow) {
            return DateInterval(start: start, end: tomorrow)
        }
        let year = calendar.component(.year, from: now)
        if text.contains("since summer"), let start = calendar.date(from: DateComponents(year: year, month: 6)),
           start <= now { return DateInterval(start: start, end: tomorrow) }
        if let i = words.firstIndex(of: "since"), words.indices.contains(i + 1),
           let month = DataSearchQuery.monthNumber(words[i + 1]) {
            let explicitYear = words.compactMap(Int.init).last(where: { (1900...2199).contains($0) })
            let startYear = explicitYear ?? (month > calendar.component(.month, from: now) ? year - 1 : year)
            let day = words.indices.contains(i + 2) ? Int(words[i + 2]) : nil
            guard day.map({ (1...31).contains($0) }) ?? true,
                  let start = calendar.date(from: DateComponents(year: startYear, month: month, day: day ?? 1)),
                  start <= now else { return nil }
            var end = tomorrow
            if let endPhrase = text.components(separatedBy: "end of ").dropFirst().first,
               let endWord = endPhrase.split(separator: " ").first,
               let endMonth = DataSearchQuery.monthNumber(endWord),
               let endDate = calendar.date(from: DateComponents(year: startYear + (endMonth < month ? 1 : 0), month: endMonth)),
               let period = calendar.dateInterval(of: .month, for: endDate) {
                end = min(period.end, tomorrow)
            }
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        if Self.months(in: text).count == 1,
           let index = words.firstIndex(where: { DataSearchQuery.monthNumber($0) != nil }),
           let month = DataSearchQuery.monthNumber(words[index]),
           words.indices.contains(index + 1), let day = Int(words[index + 1]), (1...31).contains(day) {
            let specifiedYear = words.compactMap(Int.init).first { (1900...2199).contains($0) }
            if let date = calendar.date(from: DateComponents(year: specifiedYear ?? year, month: month, day: day)),
               calendar.component(.day, from: date) == day {
                return calendar.dateInterval(of: .day, for: date)
            }
        }
        let parsed = DataSearchQuery(text)
        switch parsed.dateFilter {
        case .day(let d, let m, let y):
            return calendar.date(from: DateComponents(year: y ?? year, month: m, day: d)).flatMap { calendar.dateInterval(of: .day, for: $0) }
        case .month(let m, let y):
            return calendar.date(from: DateComponents(year: y ?? year, month: m)).flatMap { calendar.dateInterval(of: .month, for: $0) }
        case .year(let y):
            if Self.months(in: text).count == 1, let month = Self.months(in: text).first {
                return calendar.date(from: DateComponents(year: y, month: month)).flatMap { calendar.dateInterval(of: .month, for: $0) }
            }
            return calendar.date(from: DateComponents(year: y)).flatMap { calendar.dateInterval(of: .year, for: $0) }
        case nil:
            let months = Self.months(in: text)
            if months.isEmpty && !Set(words).isDisjoint(with: ["annual", "year", "yearly"]),
               let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) {
                return DateInterval(start: start, end: tomorrow)
            }
            guard months.count == 1, let month = months.first else { return nil }
            let explicitYear = words.compactMap(Int.init).first { (1900...2199).contains($0) }
            return calendar.date(from: DateComponents(year: explicitYear ?? year, month: month))
                .flatMap { calendar.dateInterval(of: .month, for: $0) }
        }
    }
}

extension LoggedStudyQuestion {
    func result(_ history: StudyHistory) -> StudyResult? {
        // A scope plus an intent browses compatible charts. An explicit measure or
        // operation selects a computed answer (for example, weekly training volume).
        let scopeWords = Set(text.split(separator: " ").map(String.init))
        let filterWords = Set(["upper", "lower", "body", "legs", "arms", "strength", "volume", "press", "pressing", "core"])
            .union(Muscle.allCases.map(\.rawValue))
        let calendarWords = Set(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec"])
            .union(history.calendar.monthSymbols.map { $0.lowercased() })
            .union(history.calendar.shortMonthSymbols.map { $0.lowercased() })
        if scopeWords.subtracting(filterWords).subtracting(calendarWords).allSatisfy({ Int($0) != nil }) { return nil }
        if let measurement = measurementAnswer(history) { return measurement }
        if history.workouts.isEmpty && history.sessions.isEmpty &&
            (original.hasSuffix("?") || text.hasPrefix("how ")) {
            return unavailable("There are no logged workouts to use for this question yet.")
        }
        if cumulativeMonthSpan {
            if interval != nil, let cumulative = loggedMetricAnswer(history) { return cumulative }
            return unavailable("This question needs a total across the specified dates.")
        }
        if let comparison = monthComparison(history) { return comparison }
        if Self.months(in: text).count > 1
            || text.contains("than last month") || text.contains("than the previous month") || text.contains("versus last month") {
            return unavailable("This search needs separate measurements for each period to make that comparison.")
        }
        if let measurement = loggedMetricAnswer(history) { return measurement }
        if let workout = workoutAnswer(history) { return workout }
        if let strength = strengthAnswer(history) { return strength }
        if let volume = volumeAnswer(history) { return volume }
        return nil
    }

    /// Use a model-nominated calculation only after the original input has established its scope.
    /// Keep the question, calendar interval and matched lifts attached to the resulting rows.
    func modelResult(_ plan: StudyQuestion, history: StudyHistory) -> StudyResult? {
        guard let measure = plan.charts.first, liftNames.count <= 1,
              plan.namedExercises.isEmpty == liftNames.isEmpty,
              plan.timeframe.isEmpty || (original.localizedCaseInsensitiveContains(plan.timeframe) && interval != nil)
        else { return nil }
        let words = Set(text.split(separator: " ").map(String.init))
        guard words.isDisjoint(with: ["than", "versus", "vs", "compare", "ratio", "minimum", "maximum", "percent", "only"]),
              words.compactMap(Int.init).allSatisfy({ (1900...2199).contains($0) }) else { return nil }
        var intent = self
        switch measure {
        case .estimatedStrengthTrend:
            guard !liftNames.isEmpty,
                  words.isDisjoint(with: ["weekly", "week", "weeks", "monthly", "months", "weekday", "weekdays"]) else { return nil }
            intent.text = "estimated strength trend"
            return intent.strengthAnswer(history)
        case .repBandDistribution, .loadByRepRange:
            guard plan.grouping == .repRange,
                  words.isDisjoint(with: ["load", "loads", "weight", "weights", "weekly", "monthly", "heavier"]) else { return nil }
            intent.text = "working sets by rep range"
            return intent.volumeAnswer(history)
        default:
            return nil
        }
    }

    private func unavailable(_ reason: String) -> StudyResult {
        answer(.sessionLedger, "Not enough data", reason, columns: [], rows: [])
    }

    private func measurementAnswer(_ history: StudyHistory) -> StudyResult? {
        let missing: (String, String)?
        let unlogged: [(phrases: [String], reason: String)] = [
            (["sleep", "slept"], "Your workout log has no dated sleep records to compare with your training."),
            (["unlogged workout", "forgot to rate"], "The records cannot tell us the values of workouts or ratings that were never logged."),
            (["heart rate", "pulse"], "Your workout log has no heart-rate measurements."),
            (["protein", "calories", "nutrition"], "Your workout log has no food intake measurements for this comparison."),
            (["range of motion", "faster out of", "bar speed", "velocity"], "Your sets record reps and loads. Answering this needs movement measurements."),
            (["pain", "soreness", "left knee", "grip strength limit"], "Exercise feedback can include a pain rating. These charts lack the symptom location or cause needed for this comparison."),
            (["gain muscle", "muscle gain", "muscle mass", "body fat"], "This needs body composition measurements over time."),
            (["what kept me", "why did i miss", "why did i take"], "Your workout dates show when you trained. They don’t record the reason for a gap.")
        ]
        if let missing = unlogged.first(where: { $0.phrases.contains(where: text.contains) }) {
            return unavailable(missing.reason)
        }
        if (text.contains("plan to do") || text.contains("skip compared with the plan")),
           history.plansFromLivePrograms.isEmpty, history.workouts.allSatisfy({ $0.status == .complete }),
           history.sessions.allSatisfy({ $0.sets.allSatisfy { $0.target == nil } }) {
            return unavailable("Only completed work is available here. This comparison needs the original training plan.")
        }
        if text.contains("how heavy was i") {
            return unavailable("This needs a bodyweight measurement from the date of the workout.")
        }
        if text.contains("bodyweight") || text.contains("body weight") {
            // Bodyweight is also an equipment category. A bodyweight exercise query
            // does not on its own request the lifter's weight.
            if text.contains("relative") || text.contains("body weight trend") || text.contains("bodyweight trend")
                || text.contains("including my body weight") || text.contains("body weight higher") || text.contains("body weight change") || text.contains("bodyweight change") || text.contains("bodyweight and") || text.contains("weigh in") {
                missing = ("Bodyweight history", "This history contains exercise loads and reps. It has no dated bodyweight measurements for a weight trend or a strength-to-bodyweight comparison.")
            } else { missing = nil }
        } else if text.contains("cardio") || text.contains("mile time") {
            missing = ("Cardio history", "The lifting log has no cardio sessions, distance or pace records to use for this question.")
        } else if text.contains("depth") && text.contains("squat") {
            missing = ("Squat depth", "Your squat sets record load and reps. They have no depth measurements to compare between sessions.")
        } else if text.contains("left") && text.contains("right") {
            missing = ("Left and right performance", "Your set log records one rep count and load per set. Separate left- and right-side measurements are needed for this comparison.")
        } else { missing = nil }
        if let missing {
            if missing.0 == "Bodyweight history", !liftNames.isEmpty {
                let selected = sessions(history)
                if text.contains("relative"), let best = selected.last(where: { $0.best != nil }),
                   let estimate = best.best {
                    return answer(.legMax, missing.0 + " and " + best.name,
                                  "Latest estimated max: " + history.loadText(estimate.tenthsPounds) + ". " + missing.1,
                                  columns: ["Lift", "Date", "Estimated max", "Bodyweight"],
                                  rows: [[best.name, history.day(best.date), history.loadText(estimate.tenthsPounds), "Unrecorded"]], insufficient: true)
                }
            }
            if missing.0 == "Cardio history", text.contains("lifting") {
                let count = history.workouts.filter { $0.status == .complete && $0.date.map(includes) == true }.count
                return answer(.frequency, "Lifting and cardio sessions", "\(count) completed lifting workouts. " + missing.1,
                              columns: ["Activity", "Recorded sessions"], rows: [["Lifting", String(count)], ["Cardio", "Unavailable"]], insufficient: true)
            }
            return answer(.sessionLedger, missing.0, missing.1, columns: [], rows: [])
        }

        if text.contains("warm up") || text.contains("warmup") {
            let rows = sessions(history).compactMap { slot -> [String]? in
                let warm = slot.warmups.filter { $0.status == .complete }.compactMap(\.load).filter { $0 > 0 }
                let work = slot.done.compactMap(\.load).filter { $0 > 0 }
                guard !warm.isEmpty, !work.isEmpty else { return nil }
                let w = Double(warm.reduce(0, +)) / Double(warm.count)
                let main = Double(work.reduce(0, +)) / Double(work.count)
                return [history.day(slot.date), slot.name, history.loadText(Int(w.rounded())),
                        history.loadText(Int(main.rounded())), (100 * w / main).studyNumber + "%"]
            }
            return answer(.sessionLedger, "Warm-up and working loads",
                          rows.isEmpty ? "No exercise session in this range has loads for both completed warm-ups and working sets." :
                            "Each row compares average external load in warm-ups and working sets for the same lift in one session.",
                          columns: ["Date", "Lift", "Mean warm-up", "Mean working", "Warm-up / working"], rows: rows)
        }
        return nil
    }
}
