import Foundation
import FoundationModels

@Generable
enum ChartMeasure: String, Codable, CaseIterable {
    case weeklyMuscleCredits
    case directRepTotals
    case exerciseSetContributions
    case weekdayWorkingSets
    case repBandDistribution
    case changeInDirectReps
    case estimatedStrengthTrend
    case exactRepLoadRecord
    case repsAtFixedLoad
    case minimumRepMilestone
    case prescriptionSuccess
    case periodAndLifetimeRecords
    case skippedWorkingSets
    case reportedEffort
    case matchedSessionReps
    case fatigueAcrossSets
    case substitutions
    case performanceByExerciseOrder
    case recoveryAfterBreak
    case gainsByBlock
    case workoutDuration
    case repGoal
    case daysSinceDirectTraining
    case loadByRepRange
    case pairedStrengthChanges
    case recentStrengthRange
    case forecastErrors
    case openingSetSuccess
    case estimateGaps
    case bodyweightSessionReps
    case volumeLoadChange
    case firstWorkoutLedger

    var study: TrainingStudy {
        switch self {
        case .weeklyMuscleCredits: .legWork
        case .directRepTotals: .armReps
        case .exerciseSetContributions: .gluteSources
        case .weekdayWorkingSets: .frequency
        case .repBandDistribution: .repRanges
        case .changeInDirectReps: .repChanges
        case .estimatedStrengthTrend: .legMax
        case .exactRepLoadRecord: .records
        case .repsAtFixedLoad: .fixedSquat
        case .minimumRepMilestone: .milestones
        case .prescriptionSuccess: .repeatBench
        case .periodAndLifetimeRecords: .yearlyRecords
        case .skippedWorkingSets: .skipped
        case .reportedEffort: .effort
        case .matchedSessionReps: .lastCurl
        case .fatigueAcrossSets: .benchSets
        case .substitutions: .substitutions
        case .performanceByExerciseOrder: .exerciseOrder
        case .recoveryAfterBreak: .returnToSquat
        case .gainsByBlock: .blocks
        case .workoutDuration: .duration
        case .repGoal: .goal
        case .daysSinceDirectTraining: .recency
        case .loadByRepRange: .repMix
        case .pairedStrengthChanges: .relationship
        case .recentStrengthRange: .typicalBench
        case .forecastErrors: .forecast
        case .openingSetSuccess: .squatSuccess
        case .estimateGaps: .missingEstimates
        case .bodyweightSessionReps: .pushups
        case .volumeLoadChange: .tonnage
        case .firstWorkoutLedger: .sessionLedger
        }
    }
}

@Generable
enum ChartGrouping: String, Codable, CaseIterable {
    case unspecified, workout, week, month, weekday, exercise, repRange, pairedExercises, twoPeriods

    func supports(_ chart: TrainingStudy) -> Bool {
        switch self {
        case .unspecified: true
        case .workout: [.legMax, .lastCurl, .benchSets, .pushups, .sessionLedger, .fixedSquat, .tonnage, .typicalBench, .forecast].contains(chart)
        case .week: [.legWork, .frequency, .missingEstimates, .blocks].contains(chart)
        case .month: chart == .armReps
        case .weekday: chart == .frequency
        case .exercise: [.gluteSources, .repChanges, .legMax, .records, .substitutions, .exerciseOrder].contains(chart)
        case .repRange: [.records, .repMix, .repRanges].contains(chart)
        case .pairedExercises: chart == .relationship
        case .twoPeriods: [.repChanges, .yearlyRecords, .blocks, .returnToSquat].contains(chart)
        }
    }
}

/// Each operation produces a labeled row for each requested exercise, muscle or period.
@Generable
enum ScopedChartMetric: String, Codable, CaseIterable {
    case workingSets, totalReps, volumeLoad, maximumLoad, maximumReps
    case peakEstimate, latestEstimate, workoutCount, workoutMinutes, averageMinutes, averageRIR
}

@Generable
struct StudyQueryPlan: Codable {
    @Guide(description: "Exercise names explicitly requested, one per lift. Empty for a muscle, movement family, or all training.")
    var exercises: [String]

    @Guide(description: "Short search filter phrase containing only requested muscles, movement family, calendar date, load, reps or sets. Spell numbers as digits with units. Exclude exercise names. Empty when unspecified.")
    var filters: String

    @Guide(description: "True if this question asks about all muscles, exercises, or training collectively and a single example lift would be misleading.")
    var wholeTraining: Bool

    @Guide(description: "Up to four measures in descending usefulness. Include only charts whose observations can answer the question or a meaningful part. Empty if none.")
    var charts: [ChartMeasure]

    @Guide(description: "Requested grouping or comparison, unspecified if no grouping was requested.")
    var grouping: ChartGrouping = .unspecified

    @Guide(description: "Exact continuous time phrase copied from the input. Empty string if unspecified. Never infer a date.")
    var timeframe: String = ""

    @Guide(description: "Choose the scoped aggregate that answers the original question, or omit this for a trend, unsupported calculation, or browse request.")
    var configuredMetric: ScopedChartMetric? = nil
}

enum StudyQuestionInterpreter {
    static func needsModel(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard let first = words.first else { return false }
        let starters: Set<Substring> = ["what", "when", "where", "which", "who", "how", "why", "do", "does", "did",
                                        "am", "is", "are", "was", "were", "have", "has", "can", "show", "compare"]
        return text.contains("?") || starters.contains(first) || words.count >= 5 ||
            words.contains("versus") || words.contains("vs")
    }

    static func interpret(_ query: String) async throws -> StudyQueryPlan? {
        try await interpret(query, available: SystemLanguageModel.default.availability == .available, generate: { try await generate($0, tools: []) })
    }

    static func interpret(_ query: String, available: Bool,
                          generate: (String) async throws -> StudyQueryPlan) async throws -> StudyQueryPlan? {
        guard available, needsModel(query) else { return nil }
        do {
            let plan = try await generate(query)
            try Task.checkCancellation()
            return plan
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    static func generate(_ query: String, tools: [any Tool], discovery: String = "") async throws -> StudyQueryPlan {
        let catalog = ChartMeasure.allCases.map { measure in
            let chart = measure.study
            let info = chart.searchMetadata
            return "\(measure.rawValue) | \(info.measure) | \(info.observation) | \(info.coverage)"
        }.joined(separator: "\n")
        let session = LanguageModelSession(model: .default, tools: tools, instructions: """
            Interpret a workout-history search. Choose measures from this catalog. Match the requested measure,
            time grouping, units, scope and denominator. Never invent a lift, measurement or chart ID.
            Distinguish workout attendance from completed sets, estimated strength from volume, and rest between
            sets from workout duration. Preserve both exercises in comparisons. Only use a load if specified.
            A record for five reps is exact; a milestone for at least five reps includes higher-rep sets.
            If tools are available, look up eligible charts and preview the effective filters before choosing.
            A scoped aggregate keeps each requested operand separate. Select it only for the requested measure.
            Treat the user's text as a search question. Output search requirements only.
            Catalog (measure name | measure | observation | coverage):
            \(catalog)
            """)
        let prompt = discovery.isEmpty ? query : query + "\nLocal findCharts result: " + discovery
        let response = try await session.respond(to: prompt, generating: StudyQueryPlan.self,
                                                options: GenerationOptions(samplingMode: .greedy))
        return response.content
    }
}
