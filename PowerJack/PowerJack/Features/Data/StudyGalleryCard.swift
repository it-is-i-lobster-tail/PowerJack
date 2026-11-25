import Foundation

struct GalleryCardID: Hashable {
    let study: TrainingStudy
    let exerciseKeys: [String]
}

struct GalleryCard: Identifiable {
    let id: GalleryCardID
    let options: StudyOptions
    let source: StudyResult?
    let score: Int
    let variant: Int
    var related = false
    var answersVerifiedScope = false
}

extension StudySearch {
    /// The gallery and search quality checks use the same ordering and the same configured charts.
    func galleryCards(history: StudyHistory, saved: SavedStudyViews, parsed: StudyQuestion? = nil) -> [GalleryCard] {
        if let card = loggedCard(history, parsed: parsed, explainUnmatched: true) { return [card] }
        return browseCards(history: history, saved: saved)
    }

    private func loggedCard(_ history: StudyHistory, parsed: StudyQuestion?, explainUnmatched: Bool = false) -> GalleryCard? {
        guard !queryText.isEmpty else { return nil }
        let question = parsed ?? StudyQuestion(queryText, history: history, knownNames: knownExerciseNames)
        if StudyScopedChart.canAnswerDirectly(question), let scoped = StudyScopedChart(question, history: history) {
            var match = card(for: scoped.result, question: question, history: history)
            match.answersVerifiedScope = true
            return match
        }
        guard let result = question.result(history, explainUnmatched: explainUnmatched) else { return nil }
        return card(for: result, question: question, history: history)
    }

    private func card(for result: StudyResult, question: StudyQuestion, history: StudyHistory) -> GalleryCard {
        var options = StudyOptions()
        if !question.liftNames.isEmpty {
            options.exerciseKeys = Set(question.sessions(history).map(\.key)).sorted()
        }
        options.muscles = Muscle.allCases.filter(question.muscles.contains)
        return GalleryCard(id: .init(study: result.id, exerciseKeys: options.exerciseKeys),
                           options: options, source: result, score: 0, variant: 0)
    }

    private func browseCards(history: StudyHistory, saved: SavedStudyViews) -> [GalleryCard] {
        let cards = TrainingStudy.allCases.flatMap { study in
            matches(for: study, saved: saved[study]).enumerated().map { variant, options in
                let id = GalleryCardID(study: study, exerciseKeys: options.exerciseKeys)
                return GalleryCard(id: id, options: options,
                                   source: history.result(for: study, options: options),
                                   score: score(for: study, options: options), variant: variant)
            }
        }
        return cards.sorted { left, right in
            if (left.source?.figure != nil) != (right.source?.figure != nil) { return left.source?.figure != nil }
            if (left.variant == 0) != (right.variant == 0) { return left.variant == 0 }
            if left.score != right.score { return left.score > right.score }
            if left.id.study != right.id.study { return left.id.study.rawValue < right.id.study.rawValue }
            return left.variant < right.variant
        }
    }
}

extension StudyQueryPlan {
    /// The existing studies record workout duration and set completion, but lack these denominators.
    static func missingMeasurement(for query: String) -> String? {
        let words = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let workout = !words.isDisjoint(with: ["workout", "workouts", "sessions"])
        let fraction = !words.isDisjoint(with: ["percent", "percentage", "fraction", "share", "rate"]) || query.contains("%")
        if workout && fraction && !words.isDisjoint(with: ["planned", "scheduled", "prescribed"]) {
            return "This question needs both planned and completed workout counts."
        }
        if words.contains("rest") && words.contains("between") && !words.isDisjoint(with: ["set", "sets"]) {
            return "This question needs recorded rest intervals between sets."
        }
        if words.contains("relative") && (words.contains("bodyweight") || words.isSuperset(of: ["body", "weight"])) {
            return "This question needs body weight recorded alongside each lift."
        }
        return nil
    }

    var namedExercises: [String] {
        let generic: Set<String> = ["", "lift", "lifts", "exercise", "exercises", "all exercises", "all lifts", "workout", "workouts"]
        return exercises.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !generic.contains($0) }
    }
}

extension StudySearch {
    /// Check the displayed population and metric before letting a focused card end search.
    /// A pooled total is insufficient evidence for a comparison, even if its title names both lifts.
    static func needsToolReview(_ cards: [GalleryCard], parsed: StudyQuestion, history: StudyHistory) -> Bool {
        if cards.count == 1, cards[0].answersVerifiedScope { return false }
        guard StudyQuestionInterpreter.needsModel(parsed.original) else { return false }
        guard cards.count == 1, let source = cards.first?.source, source.question != nil else { return true }
        if source.hasUnresolvedIntent { return true }
        if source.figure == nil { return false }
        let words = Set(parsed.text.split(separator: " ").map(String.init))
        let comparison = parsed.liftNames.count > 1 || StudyQuestion.months(in: parsed.text).count > 1
            || !words.isDisjoint(with: ["compare","versus","vs","separately","difference","than","both"])
        let evidence = [source.displayTitle, source.scope, source.summary].joined(separator: " ").lowercased()
        if let configured = StudyScopedChart(parsed, history: history),
           let requested = configured.result.plottedValues {
            if comparison {
                let rows = (source.plottedValues?.rows ?? []) + (source.detail?.rows ?? [])
                return requested.rows.contains { expected in
                    !rows.contains { actual in
                        actual.contains(expected[2]) && (expected[0] == "All training" || actual.contains(expected[0]))
                            && (requested.rows.allSatisfy { $0[1] == expected[1] } || actual.contains(expected[1]))
                    }
                }
            }
            let labels = configured.metric.label(history.unit.symbol).lowercased()
            let value = requested.rows.first?[2] ?? ""
            let rows = source.plottedValues?.rows ?? []
            if source.id != configured.metric.study && !evidence.contains(labels) { return true }
            if value != "—" && !rows.contains(where: { $0.contains(value) }) && !evidence.contains(value) { return true }
        } else if comparison { return true }
        if parsed.interval != nil && source.scope == "Recorded history" { return true }
        let constrained = !words.isDisjoint(with:["exactly","above","below","before","after","only","saturdays","mondays","wednesdays"])
            || parsed.text.contains("at least") || parsed.text.contains("at most")
        if constrained {
            let qualifiers = words.filter { Double($0) != nil || ["saturdays","mondays","wednesdays","above","below","before","after"].contains($0) }
            if qualifiers.isEmpty || qualifiers.contains(where: { !evidence.contains($0) }) { return true }
        }
        return false
    }

    func questionCards(_ plan: StudyQueryPlan, query: String, history: StudyHistory,
                       exercises: [Exercise], saved: SavedStudyViews, parsed: StudyQuestion? = nil) -> [GalleryCard] {
        let question = parsed ?? StudyQuestion(query, history: history, knownNames: knownExerciseNames)
        let local = galleryCards(history: history, saved: saved, parsed: question)
        guard Self.needsToolReview(local, parsed: question, history: history) else { return local }
        if let nomination = plan.configuredMetric, let configured = StudyScopedChart(question, history: history),
           configured.metric == nomination {
            return [card(for: configured.result, question: question, history: history)]
        }
        if let card = loggedCard(history, parsed: question) { return [card] }
        let scoped = interpreted(plan, query: query, history: history, exercises: exercises)
        if scoped != nil {
            let question = parsed ?? StudyQuestion(query, history: history, knownNames: knownExerciseNames)
            if let result = question.modelResult(plan, history: history) {
                return [card(for: result, question: question, history: history)]
            }
        }
        let proposals = modelCards(plan, scoped: scoped, history: history, saved: saved)
        if proposals.contains(where: { !$0.related }) { return proposals }
        return local
    }

    func modelCards(_ plan: StudyQueryPlan, query: String, history: StudyHistory,
                    exercises: [Exercise], saved: SavedStudyViews) -> [GalleryCard] {
        modelCards(plan, scoped: interpreted(plan, query: query, history: history, exercises: exercises),
                   history: history, saved: saved)
    }

    private func modelCards(_ plan: StudyQueryPlan, scoped: StudySearch?, history: StudyHistory,
                            saved: SavedStudyViews) -> [GalleryCard] {
        guard StudyQueryPlan.missingMeasurement(for: queryText) == nil else { return [] }
        let pair = plan.namedExercises.count > 1
        let primary = scoped?.rankedQuestionCards(plan, pair: pair, history: history, saved: saved) ?? []
        guard scoped != nil else {
            return browseCards(history: history, saved: saved).filter { $0.source?.figure != nil }.map { card in
                var related = card
                related.related = true
                return related
            }
        }
        guard primary.count < 4, !pair else { return primary }
        // A model can decline a query or over-specify the exercise. Keep other populated
        // local matches discoverable, explicitly marked as related, with their actual scope.
        let displayed = Set(primary.map(\.id))
        let related = browseCards(history: history, saved: saved).compactMap { card -> GalleryCard? in
            guard card.source?.figure != nil, !displayed.contains(card.id) else { return nil }
            var alternative = card
            alternative.related = true
            return alternative
        }
        return primary + related
    }

    private func rankedQuestionCards(_ plan: StudyQueryPlan, pair: Bool, history: StudyHistory,
                                     saved: SavedStudyViews) -> [GalleryCard] {
        var seen = Set<TrainingStudy>()
        var cards: [GalleryCard] = []
        let modelStudies = Array(plan.charts.prefix(4).map(\.study))
        guard !modelStudies.isEmpty else { return [] }
        for study in modelStudies {
            guard seen.insert(study).inserted, plan.grouping.supports(study) else { continue }
            if pair && !study.multipleExercises && study != .relationship { continue }
            if plan.wholeTraining && plan.namedExercises.isEmpty && !study.hasMuscleFocus && !study.multipleExercises { continue }
            let variants = matches(for: study, saved: saved[study], modelSelected: true)
            for (variant, options) in variants.enumerated() {
                let result = history.result(for: study, options: options)
                guard result.figure != nil else { continue }
                if pair && study != .relationship {
                    // Require observations for each operand. A title or an exercise filter alone is insufficient.
                    let labels = Set((result.detail?.rows ?? []).flatMap { $0 } + (result.plottedValues?.rows ?? []).flatMap { $0 })
                    guard options.exerciseKeys.count >= 2,
                          options.exerciseKeys.allSatisfy({ labels.contains(history.exerciseName(for: $0)) }) else { continue }
                }
                cards.append(GalleryCard(id: .init(study: study, exerciseKeys: options.exerciseKeys),
                                         options: options, source: result,
                                         score: (modelStudies.firstIndex(of: study).map { (4 - $0) * 28 } ?? 0)
                                            + score(for: study, options: options),
                                         variant: variant))
            }
        }
        return cards.sorted {
            if $0.variant != $1.variant { return $0.variant < $1.variant }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.id.study.rawValue < $1.id.study.rawValue
        }
    }
}
