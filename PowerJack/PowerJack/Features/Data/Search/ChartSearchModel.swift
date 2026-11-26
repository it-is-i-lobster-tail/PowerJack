import Foundation
import FoundationModels

/// The charts the on-device language model picks for a question.
///
/// The model only chooses what to measure. The lifts, muscles and dates always come from the
/// typed text through `ChartQuery`, so a model mistake can reorder charts but never change what
/// they are about.
@Generable
struct ChartSearchPlan: Codable, Equatable {
    @Guide(description: "Up to four charts that answer the question, most useful first. Empty if no chart fits.")
    var charts: [ChartMeasure]

    @Guide(description: "The single number the question asks for. Omit it for a trend, comparison over time, or breakdown.")
    var total: AnswerMetric?
}

extension ChartSearchPlan {
    var studies: [TrainingStudy] { Array(charts.map(\.study).uniqued().prefix(4)) }
}

/// Asks Apple's on-device model to read a question. One request, no tools, greedy sampling.
@MainActor
final class ChartSearchModel {
    static let shared = ChartSearchModel()

    private var warmSession: LanguageModelSession?

    var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    /// Load the model before the question arrives, so the first answer is faster.
    func prewarm() {
        guard isAvailable, warmSession == nil else { return }
        let session = Self.makeSession()
        session.prewarm()
        warmSession = session
    }

    /// `suggestions` are the charts local search already found, a hint the model can overrule.
    func plan(for question: String, suggestions: [TrainingStudy]) async throws -> ChartSearchPlan {
        let session = warmSession ?? Self.makeSession()
        warmSession = nil
        var prompt = "Question: \(question)"
        if !suggestions.isEmpty {
            prompt += "\nCharts local search found: " + suggestions.map { ChartMeasure($0).rawValue }.joined(separator: ", ")
        }
        let response = try await session.respond(to: prompt, generating: ChartSearchPlan.self,
                                                 options: GenerationOptions(samplingMode: .greedy))
        return response.content
    }

    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: .default, instructions: instructions)
    }

    private static let instructions: String = {
        let catalog = ChartMeasure.allCases.map { "\($0.rawValue): \($0.study.searchPhrases[0])" }
        return """
            You pick charts from a lifter's workout log that answer their question. Choose only charts from \
            this catalog, by what they measure. The app applies the lifts, muscles and dates in the question \
            itself, so ignore those when choosing. If the question asks for one number, such as a count or a \
            heaviest weight, also choose that total.
            Catalog (chart: the question it answers):
            \(catalog.joined(separator: "\n"))
            """
    }()
}

/// Chart names written for the language model. Each names what its chart measures.
@Generable
enum ChartMeasure: String, Codable, CaseIterable {
    case weeklyMuscleSets, repTotals, exerciseContributions, weekdaySets, repRangeDistribution, repChanges
    case estimatedMaxTrend, repRecords, repsAtFixedLoad, loadMilestones, prescriptionSuccess, yearAndLifetimeRecords
    case skippedSets, reportedEffort, lastTwoSessions, repsAcrossSets, substitutions, exerciseOrder
    case returnAfterBreak, gainsByBlock, workoutDuration, repGoal, daysSinceTrained, loadByRepRange
    case twoLiftRelationship, recentStrengthRange, forecastErrors, successByLoad, estimateGaps
    case bodyweightReps, volumeLoadChange, workoutLog

    init(_ study: TrainingStudy) {
        self = Self.allCases.first { $0.study == study } ?? .workoutLog
    }

    var study: TrainingStudy {
        switch self {
        case .weeklyMuscleSets: .legWork
        case .repTotals: .armReps
        case .exerciseContributions: .gluteSources
        case .weekdaySets: .frequency
        case .repRangeDistribution: .repRanges
        case .repChanges: .repChanges
        case .estimatedMaxTrend: .legMax
        case .repRecords: .records
        case .repsAtFixedLoad: .fixedSquat
        case .loadMilestones: .milestones
        case .prescriptionSuccess: .repeatBench
        case .yearAndLifetimeRecords: .yearlyRecords
        case .skippedSets: .skipped
        case .reportedEffort: .effort
        case .lastTwoSessions: .lastCurl
        case .repsAcrossSets: .benchSets
        case .substitutions: .substitutions
        case .exerciseOrder: .exerciseOrder
        case .returnAfterBreak: .returnToSquat
        case .gainsByBlock: .blocks
        case .workoutDuration: .duration
        case .repGoal: .goal
        case .daysSinceTrained: .recency
        case .loadByRepRange: .repMix
        case .twoLiftRelationship: .relationship
        case .recentStrengthRange: .typicalBench
        case .forecastErrors: .forecast
        case .successByLoad: .squatSuccess
        case .estimateGaps: .missingEstimates
        case .bodyweightReps: .pushups
        case .volumeLoadChange: .tonnage
        case .workoutLog: .sessionLedger
        }
    }
}
