import Foundation
import Testing

@testable import PowerJack

/// Ranking with the bundled embedding model. Each question is worded differently from the phrases
/// in `TrainingStudy.searchPhrases`, so these check meaning, not copied text.
@MainActor
struct ChartIndexTests {
    let history = ChartSearchFixture.history()

    private func top(_ question: String, _ count: Int = 3) throws -> [TrainingStudy] {
        let index = try #require(ChartIndex.shared.relevant(for: ChartQuery(question, history: history).intent),
                                 "\(question) has words to rank by")
        return Array(index.prefix(count))
    }

    @Test("The bundled embedding model loads")
    func encoderLoads() {
        #expect(ExerciseTextEncoder.bundled != nil)
    }

    @Test("Lifters' questions find the chart that answers them in the top three", arguments: [
        ("Is my bench going up?", TrainingStudy.legMax), ("squat progress", .legMax),
        ("Am I getting stronger at deadlifts?", .legMax), ("weekly volume for chest", .legWork),
        ("How many sets am I doing for back each week?", .legWork), ("total reps last month", .armReps),
        ("Which exercises hit my glutes the most?", .gluteSources), ("Where does my quad work come from?", .gluteSources),
        ("What days do I usually lift?", .frequency), ("Do I mostly do sets of five or sets of ten?", .repRanges),
        ("Did my rep counts change this month?", .repChanges), ("heaviest squat for 5 reps", .records),
        ("What's my bench PR?", .records), ("best deadlift ever", .records),
        ("Can I do more reps at 185 now?", .fixedSquat), ("When did I first squat 225?", .milestones),
        ("Did I hit all my prescribed sets on bench?", .repeatBench), ("records this year versus all time", .yearlyRecords),
        ("How many sets did I skip?", .skipped), ("Were my sets too easy?", .effort),
        ("How close to failure am I training?", .effort), ("Compare this curl session with the previous one", .lastCurl),
        ("Do my reps fall off on later sets?", .benchSets), ("What did I swap squats for?", .substitutions),
        ("Does doing curls first help?", .exerciseOrder), ("How fast did I recover strength after vacation?", .returnToSquat),
        ("Which program block worked best?", .blocks), ("How long do my workouts take?", .duration),
        ("average session length", .duration), ("Am I close to my 1000 rep goal?", .goal),
        ("What muscles have I been neglecting?", .recency), ("Am I lifting heavier for the same reps?", .repMix),
        ("Does my bench improve when my squat does?", .relationship), ("Was today's bench unusually good?", .typicalBench),
        ("Predict my next bench max", .forecast), ("How often do I make my reps at 225?", .squatSuccess),
        ("Why is my strength chart missing weeks?", .missingEstimates), ("Are my push ups improving?", .pushups),
        ("total tonnage per session", .tonnage), ("How much weight did I move?", .tonnage),
        ("Show me the sets from my last workout", .sessionLedger),
    ])
    func ranksTheAnsweringChart(question: String, chart: TrainingStudy) throws {
        #expect(try top(question).contains(chart), "\(question): \(try top(question))")
    }

    @Test("Unambiguous questions rank their chart first")
    func clearWinners() throws {
        for (question, chart) in [("How long do my workouts take?", TrainingStudy.duration),
                                  ("How many sets did I skip?", .skipped), ("total tonnage per session", .tonnage),
                                  ("What muscles have I been neglecting?", .recency), ("Predict my next bench max", .forecast)] {
            #expect(try top(question, 1) == [chart], "\(question)")
        }
    }

    @Test("Text with no lifting meaning finds no charts")
    func unrelated() {
        #expect(ChartIndex.shared.relevant(for: "saxophone wallpaper") == [])
    }

    @Test("A search made only of scope has nothing to rank, so every chart is narrowed instead")
    func scopeOnly() {
        #expect(ChartIndex.shared.relevant(for: ChartQuery("arms October", history: history).intent) == nil)
    }

    @Test("Without the embedding model, shared words still rank charts")
    func lexicalFallback() {
        let index = ChartIndex(encoder: nil)
        #expect(index.relevant(for: "skipped sets")?.first == .skipped)
        #expect(index.relevant(for: "workout duration")?.first == .duration)
    }

    @Test("Ranking a search takes a few milliseconds")
    func latency() {
        let index = ChartIndex.shared
        _ = index.scores(for: "warm up")
        let start = ContinuousClock.now
        for _ in 0..<50 { _ = index.scores(for: "Am I getting stronger on my main lifts this year?") }
        #expect(ContinuousClock.now - start < .milliseconds(500), "under 10 ms per search")
    }
}
