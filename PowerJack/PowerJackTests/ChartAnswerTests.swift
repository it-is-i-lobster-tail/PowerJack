import Foundation
import Testing

@testable import PowerJack

/// Direct answers against the hand-written log in `ChartSearchFixture`, where every expected
/// number can be checked by adding up the table there.
@MainActor
struct ChartAnswerTests {
    let history = ChartSearchFixture.history()

    /// The value column of the answer, one entry per subject and period.
    private func values(_ question: String) throws -> [String] {
        let query = ChartQuery(question, history: history)
        let metric = try #require(AnswerMetric(asking: query), "\(question) asks for a number")
        let result = ChartAnswer.result(metric, for: query, history: history)
        #expect(result.question == question)
        let table: StudyTable
        if case .table(let single) = result.figure {
            table = single
        } else {
            table = try #require(result.detail)
        }
        return table.rows.map { $0[2] }
    }

    @Test("Counts and totals for one lift in one month", arguments: [
        ("How many bench sets did I do in October?", 6.0),
        ("How many workouts did I finish in November?", 2),
        ("How many reps of cable curl in November?", 24),
        ("How many push ups did I do?", 40),
        ("What's the heaviest bench for 5 reps?", 195),
        ("Total weight lifted on squat in October", 6900),
        ("Average workout minutes in October", 50),
        ("Most reps in one set of push ups", 20),
    ])
    func single(question: String, expected: Double) throws {
        #expect(try values(question) == [expected.studyNumber], "\(question)")
    }

    @Test("Two months or two lifts get one value each")
    func comparisons() throws {
        #expect(try values("How many sets did I do in October versus November?") == ["19", "8"])
        #expect(try values("How many sets of bench and squat did I do?") == ["8", "9"])
    }

    @Test("A comparison is drawn as bars, one per subject")
    func comparisonFigure() throws {
        let query = ChartQuery("How many sets of bench and squat did I do?", history: history)
        let result = ChartAnswer.result(.workingSets, for: query, history: history)
        guard case .bars(let bars) = result.figure else {
            Issue.record("Expected bars")
            return
        }
        #expect(bars.map(\.value) == [8, 9])
    }

    @Test("An estimated max uses only the named lift")
    func estimate() throws {
        let squat = history.sessions.filter { $0.key == ChartSearchFixture.squat.key }
        let best = try #require(squat.compactMap(\.best?.tenthsPounds).max())
        #expect(try values("What's my best estimated max on squat?") == [history.weight(best).studyNumber])
    }

    @Test("A named lift with no logged sets answers zero rather than another lift's number")
    func unloggedLift() throws {
        #expect(try values("How many front squat sets have I done?") == ["0"])
    }

    @Test("Breakdowns and trends are charts, not one number", arguments: [
        "sets per week for chest", "bench progress", "Why did my volume change?", "How has my squat trended?",
        "arms October", "Show my squat chart",
    ])
    func notANumber(question: String) {
        #expect(AnswerMetric(asking: ChartQuery(question, history: history)) == nil, "\(question)")
    }

    @Test("Questions about things the log doesn't record say so", arguments: [
        "Did sleep help my bench?", "What's my resting heart rate?", "How much protein do I eat?",
        "How has my bodyweight changed?", "How long do I rest between sets?",
    ])
    func unrecorded(question: String) throws {
        let result = try #require(ChartAnswer.unrecorded(ChartQuery(question, history: history)), "\(question)")
        #expect(result.figure == nil)
        #expect(result.summary.hasPrefix("Not enough data."))
    }

    @Test("Bodyweight exercises are not mistaken for a missing bodyweight measurement")
    func bodyweightExercise() {
        #expect(ChartAnswer.unrecorded(ChartQuery("bodyweight exercise reps", history: history)) == nil)
    }
}
