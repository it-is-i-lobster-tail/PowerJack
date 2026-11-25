import Foundation

extension ScopedChartMetric {
  var study: TrainingStudy {
    switch self {
    case .workingSets: .legWork
    case .totalReps: .armReps
    case .volumeLoad: .tonnage
    case .maximumLoad, .maximumReps: .records
    case .peakEstimate, .latestEstimate: .legMax
    case .workoutCount: .frequency
    case .workoutMinutes, .averageMinutes: .duration
    case .averageRIR: .effort
    }
  }
  func label(_ unit: String) -> String {
    switch self {
    case .workingSets: "Working sets"
    case .totalReps: "Total reps"
    case .volumeLoad: "Volume load (\(unit)·reps)"
    case .maximumLoad: "Maximum load (\(unit))"
    case .maximumReps: "Maximum reps in one set"
    case .peakEstimate: "Peak estimated max (\(unit))"
    case .latestEstimate: "Latest estimated max (\(unit))"
    case .workoutCount: "Completed workouts"
    case .workoutMinutes: "Total workout minutes"
    case .averageMinutes: "Average workout minutes"
    case .averageRIR: "Mean reported RIR"
    }
  }
}

/// A deterministic configuration for scalar measurements at the scope stated in the query.
struct StudyScopedChart {
  let metric: ScopedChartMetric
  let result: StudyResult

  /// A closed vocabulary applies only to a scalar result that already validated its metric,
  /// dates, rep filter and subjects. Unconsumed terms leave the request with search and its tools.
  static func canAnswerDirectly(_ question: StudyQuestion) -> Bool {
    let text = question.textWithoutLiftNames
    let words = text.split(separator: " ").map(String.init)
    guard words.contains(where: directRequest.contains) else { return false }
    let unsupported = #"\b(?:by|each|every|per) (?:calendar |working )?(?:week|month|year|session|workout|day|set)s?\b|\b(?:not|except|without|excluding|ignoring|only|combined|together|before|after|between)\b"#
    guard text.range(of: unsupported, options: .regularExpression) == nil else { return false }
    if words.contains("or") && question.liftNames.count < 2 && StudyQuestion.months(in: text).count < 2 {
      return false
    }
    return words.allSatisfy { word in
      directVocabulary.contains(word) || Int(word) != nil || DataSearchQuery.monthNumber(word) != nil
        || (!question.muscles.isEmpty && Muscle.allCases.contains { $0.rawValue == word })
    }
  }

  private static let directRequest: Set<String> = [
    "how", "what", "which", "count", "add", "calculate", "compare", "show", "give", "total",
    "maximum", "heaviest", "highest", "sum", "did", "separately",
  ]
  private static let directVocabulary = directRequest.union("""
    a across all an and any are as at both by can completed complete completing count counts did
    do does done during each entire every finish finished for full give had has have many much i in include
    including into is it log logged logging me my of on or over overall recorded separately show
    since so sum that the then there these this through to total totaled totals up versus vs
    was were what which with you workout workouts session sessions visit visits training history
    year annual yearly date month yearlong time spent minutes minute duration elapsed set sets
    working rep reps repetitions repetition exactly weights weight load loads pound pounds lb lbs
    poundage tonnage volume external times multiplied by lifted most heaviest maximum highest
    more fewer number between separately comparison during accumulated combined together best
    warmups warm up ups excluding ignoring without single alltime per calendar far used
    sunday sundays monday mondays tuesday tuesdays wednesday wednesdays thursday thursdays
    friday fridays saturday saturdays legs arms
    """.split(whereSeparator: { $0.isWhitespace }).map(String.init))


  private static func metric(for text: String) -> ScopedChartMetric? {
    let words = Set(text.split(separator: " ").map(String.init))
    // Ranking workouts or asking for reps at a particular load needs the matching rows.
    if text.range(of: #"\bwhich (?:[a-z]+ )?(?:workout|session|date)s?\b"#, options: .regularExpression) != nil
      || (words.contains("heaviest") && !words.isDisjoint(with: ["reps", "rep"]) && text.contains("at my heaviest")) {
      return nil
    }
    func has(_ values: String...) -> Bool { !words.isDisjoint(with: values) }
    func contains(_ values: String...) -> Bool { values.contains(where: text.contains) }
    // These need a different population, grouping, predicate, or calculation.
    guard
      !has(
        "share", "fraction", "percent", "percentage", "ratio", "median", "distribution", "trend",
        "trends", "brackets", "bracket", "bins", "bands", "spread", "rolling", "prescribed",
        "planned", "opening", "final", "first", "earliest", "before", "after", "since", "until",
        "through", "between", "past", "previous", "prior", "weeks", "week", "timers", "timer",
        "speed", "velocity", "pressure", "lactate", "mood", "sleep", "width", "both", "kg",
        "kilograms", "hours", "lightest", "fewest", "smallest", "minimum", "least", "stopped",
        "skipped", "different"),
      !contains(
        "per set", "per working set", "each rep count", "each date", "each session",
        "every session", "which weekday", "which day", "which dates", "which workout",
        "which session", "which month", "from the", "at most", "at least", "above", "below",
        "more than", "less than", "shorter than", "longer than", "cap", "working set minutes",
        "minutes on working sets", "actually lifting", "what portion", "how many exercises",
        "how many reps were in", "how many days separate", "last three", "last two")
    else { return nil }
    let estimate = has(
      "estimated", "estimate", "estimates", "calculated", "measurable", "e1rm", "1rm")
    let peak = has(
      "highest", "largest", "greatest", "heaviest", "maximum", "peak", "best", "strongest",
      "heavier")
    if estimate && (peak || has("latest", "last")) {
      return has("latest", "last") ? .latestEstimate : .peakEstimate
    }
    guard
      !has("latest", "last", "warmups", "warmup")
        || contains("warmups left out", "excluding warmups", "ignoring warmups")
    else { return nil }
    if has("rir", "reserve") && has("mean", "average") { return .averageRIR }
    if has("minutes", "duration", "elapsed") && !has("sets", "set", "timed", "longest", "shortest")
    {
      return has("average", "mean") ? .averageMinutes : .workoutMinutes
    }
    if has("tonnage", "poundage") && !peak
      || contains("times reps", "pound reps", "lb reps", "volume load")
    {
      return .volumeLoad
    }
    if peak && has("load", "loads", "weight", "weights", "pounds", "heavy", "heavier", "heaviest") {
      return .maximumLoad
    }
    if peak && has("reps", "rep") && !has("total", "workouts", "sessions", "session") {
      return .maximumReps
    }
    guard
      !estimate && !peak
        && !has(
          "effort", "rir", "rated", "rating", "exactly", "average", "mean", "per", "rep-count",
          "distinct", "load", "loads")
    else { return nil }
    if has("visits", "visit", "workouts", "sessions", "days", "times")
      && !has("minutes", "reps", "sets", "date", "dates")
    {
      // Logged attendance can include a started workout that ended early.
      if has("logged", "attended") && !has("completed", "finished", "finish", "complete") { return nil }
      return .workoutCount
    }
    if has("sets", "set")
      && !has("rep", "reps", "records", "visits", "sessions", "date", "dates", "workouts")
    {
      return .workingSets
    }
    if has("reps", "rep", "repetitions", "repetition") && !has("set", "single", "weights", "weight") { return .totalReps }
    return nil
  }

  init?(_ q: StudyQuestion, history h: StudyHistory) {
    let includeWarmups = q.includesWarmups
    var request = includeWarmups ? q.text.replacingOccurrences(
      of: #"\binclud(?:e|ing) (?:my |the )?warm ?ups?\b"#, with: "", options: .regularExpression) : q.text
    // Remove the explicit rep predicate before choosing the measure (e.g. a count of sets).
    var remaining = q.text
    var exactReps: Int?
    let exactPattern = #"\bexactly (\d+) (?:reps?|repetitions?)\b"#
    if let range = request.range(of: exactPattern, options: .regularExpression) {
      exactReps = Int(request[range].split(separator: " ")[1])
      request.removeSubrange(range)
      remaining = remaining.replacingOccurrences(of: exactPattern, with: "", options: .regularExpression)
    }
    guard let metric = Self.metric(for: request) else { return nil }
    if exactReps != nil && metric != .workingSets && metric != .maximumLoad { return nil }
    self.metric = metric
    if includeWarmups && ![ScopedChartMetric.workingSets, .totalReps, .volumeLoad].contains(metric) { return nil }
    let words = q.text.split(separator: " ").map(String.init)
    let tokens = Set(words)
    let numberWords = [
      "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
      "nine": 9, "ten": 10,
    ]
    if exactReps == nil && metric == .maximumLoad {
      let number = #"(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten)"#
      let pattern = #"\b(?:set of "# + number + #"|"# + number + #" reps?)\b"#
      if let r = remaining.range(of: pattern, options: .regularExpression) {
        exactReps =
          remaining[r].split(separator: " ").compactMap { Int($0) ?? numberWords[String($0)] }.first
        remaining.removeSubrange(r)
      }
    }
    let months = words.compactMap { DataSearchQuery.monthNumber($0) }
    let numbers = remaining.split(separator: " ").compactMap { Int($0) }.filter {
      !(1900...2199).contains($0)
    }
    if !numbers.isEmpty {
      guard numbers.count == 1, months.count == 1, let span = q.interval,
        h.calendar.isDate(span.start, inSameDayAs: span.end.addingTimeInterval(-1)),
        h.calendar.component(.day, from: span.start) == numbers[0]
      else { return nil }
    }
    if remaining.split(separator: " ").contains(where: {
      numberWords[String($0)] != nil && $0 != "one"
    }) {
      return nil
    }
    let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    let days = weekdays.indices.filter {
      tokens.contains(weekdays[$0]) || tokens.contains(weekdays[$0] + "s")
    }
    guard days.count <= 1 else { return nil }
    let weekday = days.first.map { $0 + 1 }
    let calendar = h.calendar
    var periods: [(String, DateInterval?)] = [(q.periodLabel, q.interval)]
    if months.count > 1 {
      guard Set(months).count == months.count, !tokens.contains("from"),
        !tokens.isDisjoint(with: [
          "compare", "comparison", "separately", "versus", "vs", "than", "or", "and", "differ",
          "difference",
        ])
      else { return nil }
      periods = []
      for (i, word) in words.enumerated() {
        guard let month = DataSearchQuery.monthNumber(word) else { continue }
        let explicit = words.dropFirst(i + 1).first.flatMap(Int.init)
        let y =
          explicit.flatMap { (1900...2199).contains($0) ? $0 : nil }
          ?? calendar.component(.year, from: h.today)
        guard let start = calendar.date(from: .init(year: y, month: month)),
          let span = calendar.dateInterval(of: .month, for: start)
        else { return nil }
        periods.append((start.formatted(.dateTime.month(.wide).year()), span))
      }
    } else if !months.isEmpty && q.interval == nil {
      return nil
    }
    if months.isEmpty,
      let year = words.compactMap(Int.init).first(where: { (1900...2199).contains($0) })
    {
      guard let start = calendar.date(from: .init(year: year, month: 1)),
        let span = calendar.dateInterval(of: .year, for: start)
      else { return nil }
      periods = [(String(year), span)]
    }
    let lifts = q.liftNames
    let muscles = q.muscles.sorted { $0.rawValue < $1.rawValue }
    guard lifts.isEmpty || muscles.isEmpty else { return nil }
    if lifts.isEmpty && muscles.isEmpty {
      guard
        tokens.isDisjoint(with: [
          "bench", "squat", "deadlift", "curl", "row", "press", "raise", "thrust", "pull", "push",
          "swing", "lunge",
        ])
      else { return nil }
    }
    if metric == .averageMinutes || metric == .workoutMinutes {
      guard lifts.isEmpty && muscles.isEmpty else { return nil }
    }
    let all = lifts.isEmpty && muscles.isEmpty
    let subjects = all ? ["All training"] : lifts + muscles.map { $0.rawValue.capitalized }
    var rows = [[String]]()
    for (period, span) in periods {
      func includes(_ date: Date) -> Bool {
        let inPeriod = span.map { $0.start <= date && date < $0.end } ?? true
        return inPeriod && (weekday == nil || calendar.component(.weekday, from: date) == weekday)
      }
      let scoped = h.sessions.filter { includes($0.date) }
      let visits = h.workouts.filter { $0.status == .complete && $0.date.map(includes) == true }
      for subject in subjects {
        let selected = scoped.filter {
          all
            || (lifts.isEmpty
              ? $0.primary?.rawValue.capitalized == subject : q.matchesLift($0, named: subject))
        }
        let ids = Set(selected.filter { !$0.done.isEmpty }.map(\.workout))
        let measured = Self.measure(
          metric, slots: selected, visits: all ? visits : visits.filter { ids.contains($0.key) },
          reps: exactReps, includeWarmups: includeWarmups, history: h)
        rows.append([subject, period, measured.value?.studyNumber ?? "—", String(measured.count)])
      }
    }
    let heading = includeWarmups && metric == .workingSets ? "Completed sets" : metric.label(h.unit.symbol)
    let qualifiers = [
      includeWarmups ? "Including warmups" : nil,
      weekday.map { weekdays[$0 - 1].capitalized }, exactReps.map { "exactly \($0) reps" },
    ].compactMap { $0 }
    let suffix = qualifiers.isEmpty ? "" : " · " + qualifiers.joined(separator: " · ")
    let summary =
      rows.map { "\($0[0]) · \($0[1]): \($0[2])" }.joined(separator: "; ")
      + (rows.contains { $0[2] == "—" } ? ". A dash means no qualifying observation." : ".")
    var scoped = q.answer(
      metric.study, heading + suffix, summary,
      columns: ["Subject", "Period", heading, "Observations"], rows: rows,
      insufficient: rows.contains { $0[2] == "—" })
    scoped.scope = (qualifiers + [periods.map { $0.0 }.joined(separator: " and ")]).joined(separator: " · ")
    result = scoped
  }

  private static func measure(
    _ metric: ScopedChartMetric, slots: [StudySession], visits: [StudyWorkout], reps: Int?,
    includeWarmups: Bool, history h: StudyHistory
  ) -> (value: Double?, count: Int) {
    func completedSets(_ slot: StudySession) -> [StudySet] {
      includeWarmups ? slot.done + slot.warmups.filter { $0.status == .complete } : slot.done
    }
    let sets = slots.flatMap(completedSets).filter { reps == nil || $0.reps == reps }
    let counts = sets.compactMap(\.reps)
    switch metric {
    case .workingSets: return (Double(sets.count), sets.count)
    case .totalReps:
      return (counts.isEmpty && !sets.isEmpty ? nil : Double(counts.reduce(0, +)), counts.count)
    case .maximumReps: return (counts.max().map(Double.init), counts.count)
    case .maximumLoad:
      let loads = sets.filter { ($0.reps ?? 0) > 0 }.compactMap(\.load).filter { $0 > 0 }
      return (loads.max().map(h.weight), loads.count)
    case .volumeLoad:
      let values = slots.filter { !$0.repsOnly }.flatMap(completedSets).compactMap { set -> Double? in
        guard let l = set.load, let r = set.reps else { return nil }
        return h.weight(l) * Double(r)
      }
      return (values.isEmpty && !sets.isEmpty ? nil : values.reduce(0, +), values.count)
    case .peakEstimate, .latestEstimate:
      let values = slots.compactMap { s in s.best.map { (s.date, $0.tenthsPounds) } }
      let latest = values.map(\.0).max()
      let comparable = metric == .latestEstimate ? values.filter { $0.0 == latest } : values
      return (comparable.map(\.1).max().map(h.weight), comparable.count)
    case .averageRIR:
      let ratings = sets.compactMap(\.rating)
      guard !ratings.isEmpty, !ratings.contains(.fiveOrMore) else { return (nil, ratings.count) }
      return (Double(ratings.map(\.rawValue).reduce(0, +)) / Double(ratings.count), ratings.count)
    case .workoutCount: return (Double(visits.count), visits.count)
    case .workoutMinutes, .averageMinutes:
      let minutes = visits.compactMap(\.seconds).map { $0 / 60 }
      guard !minutes.isEmpty else {
        return (metric == .workoutMinutes && visits.isEmpty ? 0 : nil, 0)
      }
      return (
        minutes.reduce(0, +) / (metric == .averageMinutes ? Double(minutes.count) : 1),
        minutes.count
      )
    }
  }
}
