import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import PowerJack

@MainActor
struct TrainingStudyTests {
    @Test("All 32 charts have short unique captions and respect missing data")
    func emptyGallery() {
        let history = StudyHistory(programs: [], archive: [], logs: [], unit: .pounds)
        let studies = TrainingStudy.allCases
        #expect(studies.count == 32)
        #expect(Set(studies.map(\.caption)).count == 32)
        for study in studies {
            #expect((3...6).contains(study.caption.split(separator: " ").count))
            #expect(history.result(for: study).figure == nil)
        }
    }

    #if DEBUG && targetEnvironment(simulator)
        @Test("The sample history supplies all 32 charts through real model rows")
        func populatedGallery() throws {
            let store = PowerJackStore(inMemory: true)
            let context = store.container.mainContext
            let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 24)))
            try SimulatorTrainingHistory.populate(in: context, now: date)
            let programs = try context.fetch(FetchDescriptor<Program>())
            let history = StudyHistory(
                programs: programs, archive: try HistoryArchive.records(in: context),
                logs: try context.fetch(FetchDescriptor<WorkoutLog>()), unit: .pounds, today: date)
            for study in TrainingStudy.allCases {
                let result = history.result(for: study)
                #expect(result.figure != nil, "\(study.caption) needs matching sample history")
                for presentation in result.availablePresentations {
                    for transpose in result.supportsTranspose ? [false, true] : [false] {
                        let displayed = result.presented(as: presentation, transpose: transpose)
                        #expect(
                            displayed.readingExample?.isEmpty == false,
                            "\(study.caption) needs a reading example for \(presentation), transposed: \(transpose)")
                    }
                }
                let preview = StudyFigureView(study: result, compact: true).frame(width: 158, height: 90)
                let image = try #require(ImageRenderer(content: preview).cgImage)
                // A transparent bitmap can be returned even if none of the chart's marks actually drew.
                let mask = try #require(
                    CGContext(
                        data: nil, width: 40, height: 24, bitsPerComponent: 8, bytesPerRow: 40,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
                mask.setFillColor(gray: 1, alpha: 1)
                mask.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
                mask.draw(image, in: CGRect(x: 0, y: 0, width: 40, height: 24))
                let bytes = try #require(mask.data).assumingMemoryBound(to: UInt8.self)
                let ink = UnsafeBufferPointer(start: bytes, count: 40 * 24).filter { $0 < 245 }
                #expect(ink.count > 5, "\(study.caption) needs visible chart marks")
            }
            let direct = history.sessions.filter { s in
                history.inYear(s.date) && s.primary.map(StudyHistory.arms.contains) == true
            }
            let expected = direct.flatMap(\.done).compactMap(\.reps).reduce(0, +)
            guard case .bars(let months) = history.result(for: .armReps).figure else {
                Issue.record("Expected monthly rep bars")
                return
            }
            #expect(expected > 0)
            #expect(months.map(\.value).reduce(0, +) == Double(expected))
            guard case .traces(let series, _) = history.result(for: .relationship).figure else {
                Issue.record("Expected paired changes")
                return
            }
            #expect(series[0].points.count >= 8)
            #expect(series[1].style == .fit)

            // The fifth block week straddles March and April. Only the April visit belongs in its point.
            var april = StudyOptions()
            april.period = .month(year: 2026, month: 4)
            let squats = history.lift(StudyHistory.squat)
            let aprilVisit = try #require(squats.first {
                history.calendar.component(.month, from: $0.date) == 4 && $0.blockWeek == 5 && $0.best != nil
            })
            let block = try #require(aprilVisit.block)
            let estimates = squats.filter { $0.block == block && $0.blockWeek == 1 }
                .compactMap { $0.best.map { Double($0.tenthsPounds) } }
            let baseline = try #require(StudyHistory.quantile(estimates))
            let sessionBest = try #require(aprilVisit.best).tenthsPounds
            guard case .traces(let blocks, _) = history.result(for: .blocks, options: april).figure else {
                Issue.record("Missing April training blocks")
                return
            }
            let firstPoint = try #require(blocks.first?.points.first)
            #expect(firstPoint.x == 5)
            #expect(abs(firstPoint.y - (Double(sessionBest) / baseline - 1) * 100) < 0.0001)
        }
    #endif

    @Test("Calendar, exercise, muscle and target controls recompute archived workout data")
    func customizedArchive() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "GMT"))
        func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        let entries: [(Date, String, String, String, Int, Int)] = [
            (date(12, 15, year: 2025), StudyHistory.squat, "Back Squat", "Quads", 2450, 5),
            (date(3, 1), StudyHistory.squat, "Back Squat", "Quads", 2100, 5),
            (date(3, 12), StudyHistory.squat, "Back Squat", "Quads", 2050, 5),
            (date(4, 2), StudyHistory.squat, "Back Squat", "Quads", 1850, 5),
            (date(4, 10), StudyHistory.squat, "Back Squat", "Quads", 1950, 10),
            (date(4, 15), StudyHistory.curl, "Cable Curl", "Biceps", 300, 12),
            (date(5, 7), StudyHistory.squat, "Back Squat", "Quads", 2250, 5),
        ]
        let program = UUID()
        let batch = UUID()
        let records = entries.enumerated().map { index, entry in
            var row = HistoryRow(programID: program)
            row.day = index + 1
            row.exerciseNumber = 1
            row.workoutEnded = entry.0
            row.workoutStatus = "Complete"
            row.exerciseKey = entry.1
            row.exerciseName = entry.2
            row.primaryMuscle = entry.3
            row.equipment = "Barbell"
            row.setType = "Working"
            row.setStatus = "Complete"
            row.weightTenthsPounds = entry.4
            row.reps = entry.5
            return HistoryRecord(row, batchID: batch, savedAt: date(6, 1), programStarted: entries[0].0, order: index)
        }
        let history = StudyHistory(
            programs: [], archive: records.map(\.archived), logs: [], unit: .pounds, today: date(6, 1), calendar: calendar)
        var selection = StudyOptions()
        selection.period = .month(year: 2026, month: 4)
        selection.muscles = [.quads]
        let monthly = history.result(for: .armReps, options: selection)
        guard case .bars(let days) = monthly.figure else {
            Issue.record("Expected daily rep totals")
            return
        }
        #expect(monthly.xLabel == "Day")
        #expect(days.count == 30)
        #expect(days.map(\.value).reduce(0, +) == 15)
        #expect(days.allSatisfy { $0.group == "Quads" })

        let change = history.result(for: .repChanges, options: selection)
        guard case .bars(let deltas) = change.figure else {
            Issue.record("Missing comparison")
            return
        }
        // April 1–30 compares against March 2–31. The March 1 set falls outside this baseline.
        #expect(deltas.map(\.value) == [10])
        let recency = history.result(for: .recency, options: selection)
        guard case .bars(let recent) = recency.figure else {
            Issue.record("Missing latest exposure")
            return
        }
        #expect(recent.map(\.value) == [20])

        selection.muscles = [.biceps]
        selection.exerciseKeys = [StudyHistory.curl]
        guard case .bars(let curls) = history.result(for: .armReps, options: selection).figure else {
            Issue.record("Missing filtered curls")
            return
        }
        #expect(curls.map(\.value).reduce(0, +) == 12)
        selection.parameters[.load] = 300
        guard case .traces(let reps, _) = history.result(for: .fixedSquat, options: selection).figure else {
            Issue.record("Missing fixed-load curl")
            return
        }
        #expect(reps.first?.points.map(\.y) == [12])
        selection.parameters[.load] = 350
        #expect(history.result(for: .fixedSquat, options: selection).figure == nil)

        selection.muscles = []
        selection.exerciseKeys = [StudyHistory.squat]
        selection.parameters = [.reps: 5]
        let bests = history.result(for: .yearlyRecords, options: selection)
        guard case .comparison(let recordPoints, _) = bests.figure else {
            Issue.record("Expected period and lifetime records")
            return
        }
        // Compare the stored tenth-pound precision after display-unit conversion.
        #expect(recordPoints.map { history.unit.tenthsPounds(from: $0.value) }.sorted() == [1850, 2450])
        guard case .traces(let milestones, _) = history.result(for: .milestones, options: selection).figure else {
            Issue.record("Expected period milestones")
            return
        }
        #expect(milestones.first?.points.map { history.unit.tenthsPounds(from: $0.y) } == [1850, 1950])
        #expect(milestones.last?.points.map { history.unit.tenthsPounds(from: $0.y) } == [2450, 2450])
        selection.secondExercise = StudyHistory.squat
        let invalidPair = history.result(for: .relationship, options: selection)
        #expect(invalidPair.figure == nil)
        #expect(invalidPair.emptyReason.contains("different"))
    }

    @Test("A historical period includes the last fractional second and excludes the next midnight")
    func periodBoundaryPrecision() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "GMT"))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let program = UUID()
        let batch = UUID()
        let records = [end.addingTimeInterval(-0.25), end].enumerated().map { index, date in
            var row = HistoryRow(programID: program)
            row.day = index + 1
            row.workoutEnded = date
            row.workoutStatus = "Complete"
            row.exerciseName = "Barbell Back Squat"
            row.exerciseKey = StudyHistory.squat
            row.primaryMuscle = "Quads"
            row.equipment = "Barbell"
            row.setType = "Working"
            row.setStatus = "Complete"
            row.reps = 5
            row.weightTenthsPounds = index == 0 ? 1850 : 2050
            return HistoryRecord(row, batchID: batch, savedAt: end, programStarted: end, order: index)
        }
        let history = StudyHistory(programs: [], archive: records.map(\.archived), logs: [], unit: .pounds, today: end, calendar: calendar)
        var options = StudyOptions()
        options.period = .month(year: 2026, month: 4)
        guard case .traces(let series, _) = history.result(for: .milestones, options: options).figure else {
            Issue.record("Missing last workout of April")
            return
        }
        #expect(series.first?.points.map { history.unit.tenthsPounds(from: $0.y) } == [1850])
        guard case .bars(let muscles) = history.result(for: .recency, options: options).figure else {
            Issue.record("Missing April exposure")
            return
        }
        #expect(muscles.count == 1 && muscles.first?.value == 0)
    }

    @Test("Reps-only comparisons preserve the difference between bodyweight and added resistance")
    func repsOnlyVariants() {
        let now = Date.now
        let program = UUID()
        let batch = UUID()
        let equipment = [Equipment.bodyweight, .loadableBodyweight]
        var records: [HistoryRecord] = []
        for (index, equipment) in equipment.enumerated() {
            for set in 1...3 {
                var row = HistoryRow(programID: program)
                row.day = index + 1
                row.workoutEnded = now
                row.workoutStatus = "Complete"
                row.exerciseName = "Pull-up"
                row.exerciseKey = "pull-up-\(index)"
                row.equipment = equipment.displayName
                row.setType = "Working"
                row.setStatus = "Complete"
                row.reps = 8
                row.weightTenthsPounds = index == 0 ? nil : 250
                records.append(HistoryRecord(row, batchID: batch, savedAt: now, programStarted: now, order: index * 3 + set))
            }
        }
        let history = StudyHistory(programs: [], archive: records.map(\.archived), logs: [], unit: .pounds, today: now)
        var options = StudyOptions()
        options.exerciseKeys = ["pull-up-0"]
        #expect(history.result(for: .pushups, options: options).figure != nil)
        options.exerciseKeys = ["pull-up-1"]
        #expect(history.result(for: .pushups, options: options).figure == nil)
    }

    @Test("The automatic comparison lift has an eligible estimate and differs from the horizontal lift")
    func relationshipExerciseEligibility() {
        let now = Date.now
        let program = UUID()
        let batch = UUID()
        let records = [("high-rep", 25), ("high-rep", 30), ("eligible", 5)].enumerated().map { index, item in
            var row = HistoryRow(programID: program)
            row.day = index + 1
            row.workoutEnded = now
            row.workoutStatus = "Complete"
            row.exerciseKey = item.0
            row.exerciseName = "Barbell Reverse Lunge (per leg) · " + item.0
            row.equipment = Equipment.barbell.displayName
            row.setType = "Working"
            row.setStatus = "Complete"
            row.reps = item.1
            row.weightTenthsPounds = 850
            return HistoryRecord(row, batchID: batch, savedAt: now, programStarted: now, order: index)
        }
        let history = StudyHistory(programs: [], archive: records.map(\.archived), logs: [], unit: .pounds, today: now)
        #expect(history.relationshipVerticalKey(for: StudyHistory.squat) == "eligible")
        #expect(history.relationshipVerticalKey(for: "eligible") == nil)
    }

    @Test("WorkoutLog-only history can be queried in its original calendar year")
    func oldMuscleCreditHistory() throws {
        let calendar = Calendar(identifier: .gregorian)
        let recorded = try #require(calendar.date(from: DateComponents(year: 2020, month: 6, day: 15, hour: 12)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25)))
        let log = WorkoutLog(date: recorded, setsByMuscle: [.quads: 4.5])
        let history = StudyHistory(programs: [], archive: [], logs: [log], unit: .pounds, today: today, calendar: calendar)
        #expect(history.firstDate == recorded)
        var options = StudyOptions()
        options.period = .year(2020)
        options.muscles = [.quads]
        guard case .matrix(_, let rows, let values) = history.result(for: .legWork, options: options).figure else {
            Issue.record("Missing 2020 workout-log credits")
            return
        }
        #expect(rows == ["Quads"])
        #expect(values.flatMap { $0 }.compactMap { $0 } == [4.5])
        #expect(history.result(for: .repRanges, options: options).figure == nil)
    }

    @Test("Archived sets supply literal reps once and omit unsupported assisting credits")
    func archivedReps() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 2))!
        let id = UUID()
        var row = HistoryRow(programID: id)
        row.workoutEnded = day
        row.workoutStatus = "Complete"
        row.exerciseName = "Curl"
        row.primaryMuscle = "Biceps"
        row.setType = "Working"
        row.setStatus = "Complete"
        row.reps = 11
        let records = [1, 2].map {
            HistoryRecord(row, batchID: UUID(), savedAt: day.addingTimeInterval(Double($0)), programStarted: day, order: 0)
        }
        let history = StudyHistory(programs: [], archive: records.map(\.archived), logs: [], unit: .pounds, today: day)
        #expect(history.sessions.count == 1)
        #expect(history.sessions.first?.assisting == nil)
        guard case .bars(let bars) = history.result(for: .armReps).figure else {
            Issue.record("Missing archive reps")
            return
        }
        #expect(bars.map(\.value).reduce(0, +) == 11)
    }
}
