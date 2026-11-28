import Foundation
import FoundationModels

/// A single number a search can ask for, such as "How many bench sets did I do in October?"
@Generable
enum AnswerMetric: String, Codable, CaseIterable {
    case workingSets, totalReps, volumeLoad, maximumLoad, maximumReps
    case peakEstimate, latestEstimate, workoutCount, workoutMinutes, averageMinutes, averageRIR
    case lastTrained, sessionsPerWeek

    /// The chart a reader opens to see where the number comes from.
    var study: TrainingStudy {
        switch self {
        case .workingSets: .legWork
        case .totalReps: .armReps
        case .volumeLoad: .tonnage
        case .maximumLoad, .maximumReps: .records
        case .peakEstimate, .latestEstimate: .legMax
        case .workoutCount, .sessionsPerWeek: .frequency
        case .workoutMinutes, .averageMinutes: .duration
        case .averageRIR: .effort
        case .lastTrained: .recency
        }
    }

    func label(_ unit: String) -> String {
        switch self {
        case .workingSets: "Working sets"
        case .totalReps: "Total reps"
        case .volumeLoad: "Volume load (\(unit)·reps)"
        case .maximumLoad: "Heaviest load (\(unit))"
        case .maximumReps: "Most reps in one set"
        case .peakEstimate: "Best estimated max (\(unit))"
        case .latestEstimate: "Latest estimated max (\(unit))"
        case .workoutCount: "Completed workouts"
        case .workoutMinutes: "Total workout minutes"
        case .averageMinutes: "Average workout minutes"
        case .averageRIR: "Average reported RIR"
        case .lastTrained: "Last trained"
        case .sessionsPerWeek: "Sessions per week"
        }
    }

    /// Whether the words ask for one number. A trend or a breakdown, such as "sets per week",
    /// is a chart rather than one number, and so is a yes-or-no question such as "is my bench going up".
    static func isAsked(by query: ChartQuery) -> Bool {
        let has = query.mentions
        return !has(["per", "each", "every", "by", "trend", "over time", "progress", "chart", "graph", "why"])
            && has(["how many", "how much", "how long", "how often", "total", "count", "number of", "sum", "average",
                    "mean", "heaviest", "most", "max", "maximum", "highest", "best", "pr", "pb", "record"] + lastPhrases)
    }

    private static let lastPhrases = ["when did i last", "when was my last", "when was the last", "last time i", "last trained"]

    /// The number the words name. Nil when they ask for a number without saying which, as in
    /// "how many push-ups", where the model may choose.
    static func named(by query: ChartQuery) -> AnswerMetric? {
        let has = query.mentions
        guard isAsked(by: query) else { return nil }
        if has(lastPhrases) { return .lastTrained }
        if has(["how often"]) { return .sessionsPerWeek }
        if has(["estimated", "e1rm", "1rm", "one rep max"]) {
            return has(["latest", "current", "now"]) ? .latestEstimate : .peakEstimate
        }
        if has(["rir", "reps in reserve"]) { return has(["average", "mean"]) ? .averageRIR : nil }
        if has(["minute", "hour", "how long", "how much time", "time spent", "duration"]) {
            return has(["total", "how much time", "time spent"]) ? .workoutMinutes : .averageMinutes
        }
        if has(["tonnage", "volume load", "weight moved", "total weight", "pounds lifted", "weight lifted"]) { return .volumeLoad }
        if has(["most reps", "max reps", "maximum reps", "most rep"]) { return .maximumReps }
        if has(["heaviest", "max", "maximum", "most weight", "best", "pr", "pb", "record", "highest"]) { return .maximumLoad }
        if has(["workout", "session", "time", "day"]) { return .workoutCount }
        if has(["set"]) { return .workingSets }
        if has(["rep", "repetition"]) { return .totalReps }
        return nil
    }

    /// The number a search asks for: the one it names, else reps for a counted lift.
    init?(asking query: ChartQuery) {
        guard Self.isAsked(by: query) else { return nil }
        if let named = Self.named(by: query) {
            self = named
        } else if query.hasScope && query.mentions(["how many"]) {
            // "How many push-ups did I do?" counts reps.
            self = .totalReps
        } else {
            return nil
        }
    }
}

/// A direct answer: one value for each subject and period the search names, from the logged sets.
enum ChartAnswer {
    static func result(_ metric: AnswerMetric, for query: ChartQuery, history h: StudyHistory) -> StudyResult {
        let includeWarmups = query.mentions(["warmup", "warm up", "warm ups"])
            && !query.mentions(["without", "excluding", "except", "no"])
        let exactReps = [.workingSets, .maximumLoad].contains(metric) ? query.parameters[.reps] : nil
        // Workout length belongs to whole workouts, not to the lifts inside them.
        let wholeLog = !query.hasScope || metric == .workoutMinutes || metric == .averageMinutes
        // A word that covers several lifts, such as "squat", gets a value for each lift.
        let lifts = query.lifts.flatMap { lift in
            lift.exerciseKeys.count < 2 ? [lift]
                : lift.exerciseKeys.map { ChartQuery.Subject(name: h.exerciseName(for: $0), exerciseKeys: [$0]) }
        }
        let subjects = wholeLog ? [ChartQuery.Subject(name: "All training")] : lifts.isEmpty ? query.muscleGroups : lifts
        func includes(_ session: StudySession, in subject: ChartQuery.Subject) -> Bool {
            if wholeLog { return true }
            if query.lifts.isEmpty { return session.primary.map(subject.muscles.contains) == true }
            return subject.exerciseKeys.contains(session.key)
        }
        let periods: [(label: String, range: DateInterval?)] = query.periods.isEmpty
            ? [("All history", nil)]
            : query.periods.map { ($0.label, $0.interval(in: h.calendar)) }

        var rows: [(subject: String, period: String, value: Double?, count: Int, text: String?)] = []
        for period in periods {
            let inPeriod = { (date: Date) in period.range.map { $0.contains(date) && date < $0.end } ?? true }
            for subject in subjects {
                let sessions = h.sessions.filter { inPeriod($0.date) && includes($0, in: subject) }
                let trained = Set(sessions.filter { !$0.done.isEmpty }.map(\.workout))
                let workouts = h.workouts.filter { workout in
                    workout.status == .complete && workout.date.map(inPeriod) == true
                        && (wholeLog || trained.contains(workout.key))
                }
                let value = measure(metric, sessions: sessions, workouts: workouts, exactReps: exactReps,
                                    includeWarmups: includeWarmups, range: period.range, history: h)
                rows.append((subject.name, period.label, value.value, value.count, value.text))
            }
        }

        let heading = metric.label(h.unit.symbol)
        let qualifiers = [includeWarmups ? "Including warmups" : nil, exactReps.map { "exactly \($0) reps" }]
            .compactMap { $0 }
        let text = { (row: (subject: String, period: String, value: Double?, count: Int, text: String?)) in
            row.text ?? row.value?.studyNumber ?? "—"
        }
        let name = { (row: (subject: String, period: String, value: Double?, count: Int, text: String?)) in
            [subjects.count > 1 ? row.subject : nil, periods.count > 1 ? row.period : nil]
                .compactMap { $0 }.joined(separator: " · ")
        }
        let table = StudyTable(columns: ["Subject", "Period", heading, "Observations"],
                               rows: rows.map { [$0.subject, $0.period, text($0), String($0.count)] })
        var result = StudyResult(id: metric.study, scope: (qualifiers + [periods.map(\.label).joined(separator: " and ")])
            .joined(separator: " · "))
        if rows.count == 1, let row = rows.first {
            result.summary = "\(row.subject): \(text(row))."
            result.figure = .table(table)
        } else {
            result.summary = rows.map { "\(name($0)): \(text($0))" }.joined(separator: "; ") + "."
            result.figure = .bars(rows.map { StudyBar(label: name($0), value: $0.value ?? 0) })
            result.detail = table
        }
        if rows.contains(where: { $0.value == nil }) {
            result.summary += " A dash means nothing qualifying was logged."
        }
        result.title = StudyTitle(full: ([heading] + qualifiers).joined(separator: " · "), caption: heading)
        result.question = query.text
        return result
    }

    /// A question about something the workout log doesn't record, answered honestly.
    static func unrecorded(_ query: ChartQuery) -> StudyResult? {
        guard let reason = UnrecordedMeasure.reason(for: query) else { return nil }
        var result = StudyResult(id: .sessionLedger, scope: "Recorded history")
        result.summary = "Not enough data. " + reason
        result.emptyReason = reason
        result.title = StudyTitle(full: "Not enough data", caption: "Not enough data")
        result.question = query.text
        return result
    }

    private static func measure(_ metric: AnswerMetric, sessions: [StudySession], workouts: [StudyWorkout],
                                exactReps: Int?, includeWarmups: Bool, range: DateInterval?,
                                history h: StudyHistory) -> (value: Double?, count: Int, text: String?) {
        let trained = sessions.filter { !$0.done.isEmpty }
        switch metric {
        case .lastTrained:
            // The days since, with the date: "Nov 20, 2026 · 5 days ago".
            guard let last = trained.map(\.date).max() else { return (nil, 0, nil) }
            let days = h.days(last, h.today)
            let ago = days == 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
            return (Double(days), trained.count, "\(last.formatted(.dateTime.month(.abbreviated).day().year())) · \(ago)")
        case .sessionsPerWeek:
            // Training days over the weeks the period covers, up to today.
            let start = max(range?.start ?? h.firstDate, h.calendar.startOfDay(for: h.firstDate))
            let end = min(range?.end ?? h.today, h.today)
            let weeks = max(1, Double(h.days(start, end) + 1) / 7)
            let days = Set(trained.map { h.calendar.startOfDay(for: $0.date) }).count
            return ((Double(days) / weeks * 10).rounded() / 10, days, nil)
        default:
            let value = measure(metric, sessions: sessions, workouts: workouts, exactReps: exactReps,
                                includeWarmups: includeWarmups, history: h)
            return (value.value, value.count, nil)
        }
    }

    private static func measure(_ metric: AnswerMetric, sessions: [StudySession], workouts: [StudyWorkout],
                                exactReps: Int?, includeWarmups: Bool, history h: StudyHistory) -> (value: Double?, count: Int) {
        func completed(_ session: StudySession) -> [StudySet] {
            includeWarmups ? session.done + session.warmups.filter { $0.status == .complete } : session.done
        }
        let sets = sessions.flatMap(completed).filter { exactReps == nil || $0.reps == exactReps }
        let reps = sets.compactMap(\.reps)
        switch metric {
        case .workingSets:
            return (Double(sets.count), sets.count)
        case .totalReps:
            return (Double(reps.reduce(0, +)), reps.count)
        case .maximumReps:
            return (reps.max().map(Double.init), reps.count)
        case .maximumLoad:
            let loads = sets.filter { ($0.reps ?? 0) > 0 }.compactMap(\.load).filter { $0 > 0 }
            return (loads.max().map(h.weight), loads.count)
        case .volumeLoad:
            let volumes = sessions.filter { !$0.repsOnly }.flatMap(completed).compactMap { set -> Double? in
                guard let load = set.load, let reps = set.reps else { return nil }
                return h.weight(load) * Double(reps)
            }
            return (volumes.reduce(0, +), volumes.count)
        case .peakEstimate, .latestEstimate:
            let estimates = sessions.compactMap { session in session.best.map { (session.date, $0.tenthsPounds) } }
            let latest = estimates.map(\.0).max()
            let chosen = metric == .latestEstimate ? estimates.filter { $0.0 == latest } : estimates
            return (chosen.map(\.1).max().map(h.weight), chosen.count)
        case .averageRIR:
            // "5 or more" has no exact value, so it can't be averaged.
            let ratings = sets.compactMap(\.rating)
            guard !ratings.isEmpty, !ratings.contains(.fiveOrMore) else { return (nil, ratings.count) }
            return (Double(ratings.map(\.rawValue).reduce(0, +)) / Double(ratings.count), ratings.count)
        case .workoutCount:
            return (Double(workouts.count), workouts.count)
        case .workoutMinutes, .averageMinutes:
            let minutes = workouts.compactMap(\.seconds).map { $0 / 60 }
            guard !minutes.isEmpty else { return (metric == .workoutMinutes ? 0 : nil, 0) }
            let total = minutes.reduce(0, +)
            return (metric == .averageMinutes ? total / Double(minutes.count) : total, minutes.count)
        case .lastTrained, .sessionsPerWeek:
            return (nil, 0)
        }
    }
}

/// Things lifters ask about that a set log doesn't record.
enum UnrecordedMeasure {
    static func reason(for query: ChartQuery) -> String? {
        reasons.first { query.mentions($0.phrases) }?.reason
    }

    private static let reasons: [(phrases: [String], reason: String)] = [
        (["sleep", "slept"], "Your workout log has no sleep records."),
        (["heart rate", "pulse", "hrv"], "Your workout log has no heart-rate measurements."),
        (["protein", "calories", "calorie", "nutrition", "diet", "eat", "ate"], "Your workout log has no food records."),
        (["bar speed", "velocity", "range of motion", "depth"], "Your sets record reps and load, not how the bar moved."),
        (["body fat", "muscle mass", "body composition"], "Answering this needs body composition measurements."),
        (["my bodyweight", "my body weight", "relative to bodyweight", "relative to body weight", "how much do i weigh",
          "weigh in"], "Your workout log has no dated bodyweight measurements."),
        (["cardio", "running", "mile", "cycling", "steps"], "Your workout log has no cardio records."),
        (["rest between sets", "rest time", "rest periods"], "Your workout log doesn't record rest between sets."),
    ]
}

extension StudyPeriod {
    /// The calendar span this period covers, or nil for a chart's default or all history.
    func interval(in calendar: Calendar, today: Date = .now) -> DateInterval? {
        switch self {
        case .original, .all: nil
        case .year(let year):
            calendar.date(from: DateComponents(year: year, month: 1, day: 1)).flatMap { calendar.dateInterval(of: .year, for: $0) }
        case .month(let year, let month):
            calendar.date(from: DateComponents(year: year, month: month, day: 1)).flatMap { calendar.dateInterval(of: .month, for: $0) }
        case let .day(year, month, day):
            calendar.date(from: DateComponents(year: year, month: month, day: day)).flatMap { calendar.dateInterval(of: .day, for: $0) }
        case let .range(start, end):
            DateInterval(start: start, end: max(start, end))
        case .recent(let span):
            span.interval(today: today, calendar: calendar)
        }
    }
}
