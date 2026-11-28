import Foundation

/// Ranks the gallery's charts by meaning, with the bundled sentence-embedding model.
///
/// Each chart is described by a few questions a lifter might ask. A search scores each chart by
/// its closest question, plus a small bonus for shared words, so rare words such as "tonnage" or
/// "RIR" count even when the model has a weak sense of them. To teach search a new phrasing,
/// add it to `searchPhrases`. Phrases never name a lift: lifts are scope, not intent.
struct ChartIndex {
    static let shared = ChartIndex(encoder: .bundled)

    /// Words that describe a measure, so search never reads them as part of a lift name.
    static let vocabulary: Set<String> = Set(TrainingStudy.allCases.flatMap { study in
        study.searchPhrases.flatMap(terms)
    }).union(synonyms.keys)

    private let encoder: ExerciseTextEncoder?
    private let vectors: [TrainingStudy: [[Float]]]
    private let chartTerms: [TrainingStudy: Set<String>]
    private let weights: [String: Float]

    init(encoder: ExerciseTextEncoder?) {
        self.encoder = encoder
        vectors = Dictionary(uniqueKeysWithValues: TrainingStudy.allCases.map { study in
            (study, encoder.map { encoder in study.searchPhrases.map(encoder.vector) } ?? [])
        })
        chartTerms = Dictionary(uniqueKeysWithValues: TrainingStudy.allCases.map { study in
            (study, Set(study.searchPhrases.flatMap(Self.terms)))
        })
        var counts: [String: Int] = [:]
        for terms in chartTerms.values {
            for term in terms { counts[term, default: 0] += 1 }
        }
        let charts = Float(TrainingStudy.allCases.count)
        weights = counts.mapValues { log(1 + charts / Float($0)) }
    }

    /// Every chart with its score, best first. An empty intent scores nothing.
    func scores(for intent: String) -> [(study: TrainingStudy, score: Float)] {
        let terms = Set(Self.terms(intent))
        guard !terms.isEmpty else { return [] }
        let query = encoder?.vector(for: intent) ?? []
        // Words no chart uses still count against a match, so "saxophone volume" ranks below "volume".
        let rarest = log(1 + Float(TrainingStudy.allCases.count))
        let total = terms.reduce(0) { $0 + (weights[$1] ?? rarest) }
        return TrainingStudy.allCases.map { study in
            let meaning = vectors[study]?.map { ExerciseTextEncoder.similarity(query, $0) }.max() ?? 0
            let shared = terms.intersection(chartTerms[study] ?? []).reduce(0) { $0 + (weights[$1] ?? 0) }
            return (study, meaning + 0.4 * shared / (1 + total))
        }
        .sorted { $0.score == $1.score ? $0.study.rawValue < $1.study.rawValue : $0.score > $1.score }
    }

    /// The top three charts, plus any others close to the best match, best first. Nil when the
    /// intent has no words to rank by, as in "arms October". Empty when nothing is close.
    /// `include` limits the ranking to charts that can show the search, so a push-up search
    /// ranks the bodyweight charts instead of losing its best matches to load-based ones.
    func relevant(for intent: String, limit: Int = 6,
                  where include: (TrainingStudy) -> Bool = { _ in true }) -> [TrainingStudy]? {
        guard !Self.terms(intent).isEmpty else { return nil }
        let scored = scores(for: intent).filter { include($0.study) }
        guard let best = scored.first?.score else { return [] }
        // Without the embedding model, scores come from shared words alone and run lower.
        guard best >= (encoder == nil ? 0.1 : Self.minimumScore) else { return [] }
        return scored.enumerated()
            .prefix { $0.offset < 3 || $0.element.score >= best - Self.margin }
            .prefix(limit).map(\.element.study)
    }

    static let minimumScore: Float = 0.3
    static let margin: Float = 0.2

    private static func terms(_ text: String) -> [String] {
        SearchWords.tokens(text).map(SearchWords.singular).filter { !SearchWords.stopWords.contains($0) }
            .map { synonyms[$0] ?? $0 }
    }

    /// Words lifters use for the same measure count as one word.
    private static let synonyms = ["pb": "pr", "record": "pr", "best": "pr", "1rm": "e1rm", "orm": "e1rm"]
}

extension TrainingStudy {
    /// Questions this chart answers, in a lifter's words. The first one also describes the chart to the language model.
    var searchPhrases: [String] {
        switch self {
        case .legWork:
            ["How many sets did each muscle get each week?", "weekly sets per muscle group",
             "weekly training volume by muscle", "am I doing enough volume for this muscle"]
        case .armReps:
            ["How many reps did I do each month?", "monthly rep totals", "total reps over time", "rep count per muscle"]
        case .gluteSources:
            ["Which exercises gave this muscle the most work?", "which exercises contribute to this muscle's volume",
             "where does my volume come from by exercise"]
        case .frequency:
            ["Which days of the week do I train?", "sets by weekday", "how often do I train each muscle",
             "training frequency and schedule", "what day of the week do I lift most"]
        case .repRanges:
            ["What rep ranges do I train in?", "sets by rep range", "do I train heavy or with high reps",
             "rep range distribution", "how many reps per set do I usually do"]
        case .repChanges:
            ["Which exercises gained or lost reps?", "change in reps between two periods", "did my reps go up or down"]
        case .legMax:
            ["Am I getting stronger?", "estimated one rep max trend", "is this lift improving",
             "strength progress over time", "e1rm 1rm estimated max"]
        case .records:
            ["What is my heaviest set for this many reps?", "personal records by rep count", "my best lift ever",
             "PRs", "most weight I have lifted"]
        case .fixedSquat:
            ["Am I doing more reps at the same weight?", "reps at a fixed load over time"]
        case .milestones:
            ["When did I first lift this weight for these reps?", "first time I hit a weight", "load milestones"]
        case .repeatBench:
            ["How often did I complete all my prescribed sets?", "did I hit my target sets and reps",
             "sets reaching their target"]
        case .yearlyRecords:
            ["How do this year's records compare with my all-time bests?", "lifetime personal records", "yearly records"]
        case .skipped:
            ["How much planned work did I skip?", "skipped sets", "missed sets", "did I miss planned work"]
        case .effort:
            ["Was my effort on target?", "reps in reserve ratings", "how hard were my sets", "how close to failure",
             "RIR"]
        case .lastCurl:
            ["How did my last two sessions compare?", "how did today compare with last time",
             "session to session comparison"]
        case .benchSets:
            ["Where do my reps drop off across sets?", "fatigue across sets", "reps from first set to last set"]
        case .substitutions:
            ["What did I do instead of my planned exercise?", "exercise substitutions", "swapped exercises"]
        case .exerciseOrder:
            ["Do I do better when I do this exercise first?", "exercise order effect",
             "performance early or late in the workout"]
        case .returnToSquat:
            ["How long did it take to come back after a break?", "performance after time off",
             "detraining after a layoff or vacation"]
        case .blocks:
            ["Which training block gave the biggest strength gain?", "gains per training block", "compare training cycles"]
        case .duration:
            ["How long are my workouts?", "workout duration in minutes", "do I finish within my time budget",
             "average session length"]
        case .goal:
            ["How close am I to my rep goal?", "progress toward a rep target", "cumulative reps toward a goal"]
        case .recency:
            ["Which muscles have gone longest without training?", "days since I last trained each muscle",
             "neglected muscles"]
        case .repMix:
            ["Did my weight change at the same reps?", "load by rep range", "average weight at each rep count"]
        case .relationship:
            ["Do two exercises improve together?", "relationship between two exercises",
             "does one exercise's strength track another's"]
        case .typicalBench:
            ["Was my latest session outside my usual range?", "is my recent strength normal",
             "typical range of my estimated max"]
        case .forecast:
            ["How accurate are my strength predictions?", "forecast my next max", "predicted versus actual strength"]
        case .squatSuccess:
            ["How often do I hit my reps at each weight?", "success rate at each load", "rep target success"]
        case .missingEstimates:
            ["Why are there gaps in my strength chart?", "missing estimated maxes", "sessions without an estimate"]
        case .pushups:
            ["Are my bodyweight exercises improving?", "bodyweight reps over time", "bodyweight exercise progress",
             "best set and total reps for a bodyweight exercise"]
        case .tonnage:
            ["Why did my volume load change?", "total weight lifted", "tonnage", "weight times reps per workout"]
        case .sessionLedger:
            ["What exactly did I do in my workout?", "workout log details", "show the sets from a workout",
             "workout history", "what did I do in my last workout", "my last workout"]
        }
    }
}
