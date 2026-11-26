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
    static func gallery(history: StudyHistory, saved: SavedStudyViews) -> ChartSearchResults {
        ChartSearchResults(cards: TrainingStudy.allCases.map { study in
            let options = saved[study]
            return GalleryCard(id: GalleryCardID(study: study, exerciseKeys: []), options: options,
                               result: history.result(for: study, options: options))
        })
    }

    static func results(for query: ChartQuery, plan: ChartSearchPlan? = nil, history: StudyHistory,
                        saved: SavedStudyViews, index: ChartIndex = .shared) -> ChartSearchResults {
        guard !query.isEmpty else { return gallery(history: history, saved: saved) }
        let answer = answer(for: query, plan: plan, history: history)
        let note = note(for: query, history: history)
        // "Did I sleep enough?" has no chart. "Did sleep help my bench?" still shows the bench's charts.
        let unrecorded = UnrecordedMeasure.reason(for: query) != nil
        if unrecorded && !query.hasScope {
            return ChartSearchResults(answer: answer, note: note)
        }
        // A search made only of scope, such as "arms October", narrows every chart.
        let ranked = unrecorded ? TrainingStudy.allCases : index.relevant(for: query.intent) ?? TrainingStudy.allCases
        let studies = ((plan?.studies ?? []) + ranked).uniqued()
        let cards = studies.flatMap { study in
            query.options(for: study, saved: saved[study], history: history).map { options in
                GalleryCard(id: GalleryCardID(study: study, exerciseKeys: options.exerciseKeys), options: options,
                            result: history.result(for: study, options: options))
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
