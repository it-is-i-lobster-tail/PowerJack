import Foundation
import Testing
@testable import PowerJack

@MainActor
struct StudyAnswerTests {
    private let date = Date(timeIntervalSince1970: 1_750_000_000)

    private func history(key: String, workouts: [[[Int?]]], bodyweight: Bool = false) -> StudyHistory {
        let program = UUID()
        let batch = UUID()
        var records: [HistoryRecord] = []
        for (workout, slots) in workouts.enumerated() {
            for (slot, reps) in slots.enumerated() {
                for (set, actual) in reps.enumerated() {
                    var row = HistoryRow(programID: program)
                    row.day = workout + 1
                    row.exerciseNumber = slot + 1
                    row.setNumber = set + 1
                    row.workoutEnded = date
                    row.workoutStatus = "Complete"
                    row.exerciseKey = key
                    row.exerciseName = key
                    row.primaryMuscle = Muscle.quads.rawValue
                    row.equipment = (bodyweight ? Equipment.bodyweight : .barbell).displayName
                    row.setType = "Working"
                    row.setStatus = actual == nil ? "Skipped" : "Complete"
                    row.rirTarget = "2"
                    row.effort = workout == 0 ? RepsInReserve.fiveOrMore.label : ""
                    row.targetReps = 5
                    row.targetWeightTenthsPounds = bodyweight ? nil : 1850
                    row.weightTenthsPounds = actual == nil || bodyweight ? nil : 1850
                    row.reps = actual
                    records.append(HistoryRecord(row, batchID: batch, savedAt: date, programStarted: date, order: records.count))
                }
            }
        }
        return StudyHistory(programs: [], archive: records.map(\.archived), logs: [], unit: .pounds, today: date)
    }

    @Test("A prescribed workout counts once and skipped sets still count toward its denominator")
    func prescribedBench() {
        let source = history(key: StudyHistory.bench, workouts: [
            [[5, 4, 5], [5, 6, 5]], [[5, 5, nil]], [[nil, nil, nil]], [[5, 5, 5, 5]],
        ])
        let study = source.result(for: .repeatBench)
        #expect(study.summary.contains("1 of 3 prescribed workouts"))
        #expect(study.detail?.rows.compactMap(\.last) == ["No", "No", "Yes"])
        #expect(study.presented(as: .table, transpose: false).figure == study.detail.map(StudyFigure.table))
    }

    @Test("Best and total push-up reps share a row for each workout on the same date")
    func pushupRows() {
        let source = history(key: "catalog:push-up", workouts: [[[3, 4], [5]], [[7, 8, 9]]], bodyweight: true)
        let table = source.result(for: .pushups).detail
        #expect(table?.rows.map { Array($0[1...2]) } == [["9", "24"], ["5", "12"]])
    }

    @Test("Missing final sets stay missing when comparing changes in reps")
    func fatigue() {
        let source = history(key: StudyHistory.bench, workouts: [[[8, 7, 6]], [[8, 6, nil]]])
        var options = StudyOptions()
        options.parameters = [.sets: 3, .load: 1850]
        let study = source.result(for: .benchSets, options: options)
        #expect(study.detail?.rows.map { $0[1] } == ["—", "-2"])
        #expect(study.summary.contains("-2 reps"))
    }

    @Test("The effort table preserves both unreported and open-ended ratings")
    func effortCoverage() {
        let source = history(key: StudyHistory.squat, workouts: [[[5]], [[5]]])
        let study = source.result(for: .effort)
        #expect(study.summary.contains("1 of 2"))
        #expect(study.detail?.rows.compactMap(\.last) == ["5+", "Unrated"])
        #expect(study.presented(as: .table, transpose: false).figure == study.detail.map(StudyFigure.table))
    }

    @Test("Volume change uses both completed sessions and rep totals use working sets")
    func workloadAnswers() {
        let source = history(key: StudyHistory.squat, workouts: [[[5, 5]], [[10, 10]]])
        let volume = source.result(for: .tonnage)
        #expect(volume.summary.contains("100%"))
        let bands = source.result(for: .repRanges)
        #expect(bands.summary.contains("4–6 reps: 2"))
        #expect(bands.summary.contains("7–11 reps: 2"))
    }
}
