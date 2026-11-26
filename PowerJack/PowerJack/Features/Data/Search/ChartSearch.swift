import Foundation

/// What the gallery shows for a search: an optional direct answer, then the charts that answer it best.
struct ChartSearchResults {
    var answer: GalleryCard?
    var cards: [GalleryCard] = []
    var note: String?

    var isEmpty: Bool { answer == nil && cards.isEmpty }
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
            return ChartSearchResults(answer: answer, note: note)
        }
        // Each chart configured for the search's scope. A chart that can't show the scope has none.
        let configurations = Dictionary(uniqueKeysWithValues: TrainingStudy.allCases.map { study in
            (study, query.options(for: study, saved: saved[study], history: history))
        })
        func rank(_ intent: String) -> [TrainingStudy] {
            // A search made only of scope, such as "arms October", narrows every chart.
            index.relevant(for: intent) { configurations[$0]?.isEmpty == false } ?? TrainingStudy.allCases
        }
        var ranked = unrecorded ? TrainingStudy.allCases : rank(query.intent)
        // Search runs while typing, so a last word that matches nothing may be unfinished: "how lo", "bench prog".
        // Without it, a scoped search shows every chart for its scope. A long word on its own is a real miss.
        if ranked.isEmpty, let last = query.intent.split(separator: " ").last {
            let rest = query.intent.dropLast(last.count).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty || query.hasScope || last.count < 4 { ranked = rank(rest) }
        }
        let studies = ((plan?.studies ?? []) + ranked).uniqued()
        let cards = studies.flatMap { study in
            (configurations[study] ?? []).map { options in
                GalleryCard(id: GalleryCardID(study: study, exerciseKeys: options.exerciseKeys), options: options,
                            result: cache.result(for: study, options: options, in: history))
            }
        }
        // Charts with matching history come first, in ranked order.
        return ChartSearchResults(
            answer: answer,
            cards: cards.filter { $0.result.figure != nil } + cards.filter { $0.result.figure == nil },
            note: note)
    }

    /// Short filters answer instantly. Questions are worth a model request.
    static func asksModel(_ query: ChartQuery) -> Bool {
        query.isQuestion && UnrecordedMeasure.reason(for: query) == nil
    }

    private static func answer(for query: ChartQuery, plan: ChartSearchPlan?, history: StudyHistory) -> GalleryCard? {
        let result: StudyResult
        if let unrecorded = ChartAnswer.unrecorded(query) {
            result = unrecorded
        } else if let metric = AnswerMetric(asking: query) ?? (query.isQuestion ? plan?.total : nil) {
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
        guard !query.unloggedLifts.isEmpty else { return nil }
        return "No logged sets for \(query.unloggedLifts.formatted(.list(type: .and)))."
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
