import Foundation

/// What the gallery shows for a search: what the search read, an optional direct answer, then the
/// charts that answer it best, those with data first.
struct ChartSearchResults {
    var answer: GalleryCard?
    var cards: [GalleryCard] = []
    var note: String?
    var scope: [ScopeChip] = []
    /// Another search to try when no chart has data.
    var suggestion: ChartQuery.Suggestion?

    var isEmpty: Bool { answer == nil && cards.isEmpty }
}

/// One thing a search read, such as a lift, a muscle group, a period or a weight. Each offers the
/// searches without it, and a lift also the searches for the other lifts its words could mean.
struct ScopeChip: Identifiable, Equatable {
    struct Choice: Equatable, Hashable {
        let name: String
        let text: String
    }

    let label: String
    let isLift: Bool
    var alternatives: [Choice] = []
    let removed: String
    var id: String { label }
}

extension ChartQuery {
    func scopeChips(unit: WeightUnit) -> [ScopeChip] {
        func capitalized(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() }
        var chips = lifts.map { lift in
            ScopeChip(label: capitalized(lift.name), isLift: true,
                      alternatives: lift.alternatives.filter { $0 != lift.name }.map {
                          .init(name: $0, text: text(replacing: lift.positions, with: $0))
                      },
                      removed: text(replacing: lift.positions, with: nil))
        }
        chips += muscleGroups.map { ScopeChip(label: capitalized($0.name), isLift: false, removed: text(replacing: $0.positions, with: nil)) }
        chips += zip(periods, periodPositions).map { period, positions in
            ScopeChip(label: period.label, isLift: false, removed: text(replacing: positions, with: nil))
        }
        var seen: [[Int]] = []
        for parameter in [StudyParameter.load, .sets, .reps, .sessions, .weeks, .minutes, .comparisonDays] {
            guard let value = parameters[parameter], let positions = parameterPositions[parameter],
                  !seen.contains(positions) else { continue }
            seen.append(positions)
            let label: String
            switch parameter {
            case .load: label = "\(unit.format(tenthsPounds: value)) \(unit.symbol)"
            case .sets: label = parameters[.reps].map { "\(value)×\($0)" } ?? "\(value) sets"
            case .reps: label = "\(value) reps"
            case .sessions: label = "\(value) workouts"
            case .weeks: label = "\(value) weeks"
            case .minutes: label = "\(value) min"
            default: label = "\(value) days"
            }
            chips.append(ScopeChip(label: label, isLift: false, removed: text(replacing: positions, with: nil)))
        }
        return chips
    }
}

/// Combines local search with the language model's reading of a question.
///
/// Local search answers at once: `ChartQuery` reads the scope, `ChartIndex` ranks charts by
/// meaning, and `ChartAnswer` computes any number asked for. For a question, the model's
/// plan can then move its charts to the front and name a number to compute. It never changes
/// the scope, and when it is unavailable or fails, the local results stay as they are.
enum ChartSearch {
    /// Every chart with its saved controls, for an empty search.
    static func gallery(history: StudyHistory, saved: SavedStudyViews,
                        cache: ChartResultCache = ChartResultCache()) -> ChartSearchResults {
        ChartSearchResults(cards: TrainingStudy.allCases.map { study in
            let options = saved[study]
            return GalleryCard(id: GalleryCardID(study: study, exerciseKeys: []), options: options,
                               result: cache.result(for: study, options: options, in: history))
        })
    }

    static func results(for query: ChartQuery, plan: ChartSearchPlan? = nil, history: StudyHistory,
                        saved: SavedStudyViews, index: ChartIndex = .shared,
                        cache: ChartResultCache = ChartResultCache()) -> ChartSearchResults {
        guard !query.isEmpty else { return gallery(history: history, saved: saved, cache: cache) }
        let answer = answer(for: query, plan: plan, history: history)
        let note = note(for: query, history: history)
        // "Did I sleep enough?" has no chart. "Did sleep help my bench?" still shows the bench's charts.
        let unrecorded = UnrecordedMeasure.reason(for: query) != nil
        if unrecorded && !query.hasScope {
            return ChartSearchResults(answer: answer, note: note, scope: query.scopeChips(unit: history.unit))
        }
        // Each chart configured for the search's scope. A chart that can't show the scope has none.
        let configurations = Dictionary(uniqueKeysWithValues: TrainingStudy.allCases.map { study in
            (study, query.options(for: study, saved: saved[study], history: history))
        })
        func rank(_ intent: String) -> [TrainingStudy] {
            // A search made only of scope, such as "arms October", narrows every chart. A single day
            // with nothing else to rank by, as in "what did I do yesterday", leads with its workout log.
            guard let relevant = index.relevant(for: intent, where: { configurations[$0]?.isEmpty == false }) else {
                guard case .day = query.period else { return TrainingStudy.allCases }
                return ([.sessionLedger] + TrainingStudy.allCases).uniqued()
            }
            return relevant
        }
        var ranked = unrecorded ? TrainingStudy.allCases : rank(query.intent)
        // Search runs while typing, so a last word that matches nothing may be unfinished: "how lo", "bench prog".
        // Without it, a scoped search shows every chart for its scope. A long word on its own is a real miss.
        if ranked.isEmpty, let last = query.intent.split(separator: " ").last {
            let rest = query.intent.dropLast(last.count).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty || query.hasScope || last.count < 4 { ranked = rank(rest) }
        }
        // "squat vs deadlift" asks how two lifts relate.
        let compared: [TrainingStudy] = query.comparesLifts ? [.relationship] : []
        let studies = (compared + (plan?.studies ?? []) + ranked).uniqued()
        let cards = studies.flatMap { study in
            (configurations[study] ?? []).map { options in
                GalleryCard(id: GalleryCardID(study: study, exerciseKeys: options.exerciseKeys), options: options,
                            result: cache.result(for: study, options: options, in: history))
            }
        }
        // Charts with matching history come first, in ranked order.
        let filled = cards.filter { $0.result.figure != nil }
        return ChartSearchResults(
            answer: answer, cards: filled + cards.filter { $0.result.figure == nil }, note: note,
            scope: query.scopeChips(unit: history.unit), suggestion: filled.isEmpty ? query.suggestion : nil)
    }

    /// Short filters answer instantly. Questions are worth a model request.
    static func asksModel(_ query: ChartQuery) -> Bool {
        query.isQuestion && UnrecordedMeasure.reason(for: query) == nil
    }

    private static func answer(for query: ChartQuery, plan: ChartSearchPlan?, history: StudyHistory) -> GalleryCard? {
        let result: StudyResult
        if let unrecorded = ChartAnswer.unrecorded(query) {
            result = unrecorded
        } else if AnswerMetric.isAsked(by: query),
                  // The model may choose what to count only when the words ask for a number without naming it.
                  let metric = AnswerMetric.named(by: query) ?? plan?.total ?? AnswerMetric(asking: query) {
            result = ChartAnswer.result(metric, for: query, history: history)
        } else {
            return nil
        }
        var options = StudyOptions()
        options.exerciseKeys = query.exerciseKeys
        options.muscles = query.muscles
        return GalleryCard(id: GalleryCardID(study: result.id, exerciseKeys: options.exerciseKeys, isAnswer: true),
                           options: options, result: result)
    }

    private static func note(for query: ChartQuery, history: StudyHistory) -> String? {
        if history.sessions.isEmpty && history.workouts.isEmpty {
            return "Your workout log has no workouts yet."
        }
        let unlogged = query.unloggedLifts.isEmpty ? [] : ["No logged sets for \(query.unloggedLifts.formatted(.list(type: .and)))."]
        let notes = unlogged + query.notes
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }
}

/// Chart results for one logged history. Refining a search, clearing it, or applying the model's
/// plan then computes only the charts it hasn't shown yet.
final class ChartResultCache {
    private var revision: Int?
    private var entries: [TrainingStudy: [(options: StudyOptions, result: StudyResult)]] = [:]
    private var count = 0

    func result(for study: TrainingStudy, options: StudyOptions, in history: StudyHistory) -> StudyResult {
        // New sets, a new day or another unit change every chart. A long session of searches starts over too.
        if revision != history.revision || count > 300 {
            entries = [:]
            count = 0
            revision = history.revision
        }
        if let saved = entries[study]?.first(where: { $0.options == options }) { return saved.result }
        let result = history.result(for: study, options: options)
        entries[study, default: []].append((options, result))
        count += 1
        return result
    }
}
