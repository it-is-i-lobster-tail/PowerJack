import Foundation
import Testing

@testable import PowerJack

@MainActor
struct StudyTitleTests {
    private func history(unit: WeightUnit = .pounds) -> StudyHistory {
        StudyHistory(programs: [], archive: [], logs: [], unit: unit)
    }

    @Test("The gallery has 32 unique generic names of three to six words")
    func genericNames() {
        let names = TrainingStudy.allCases.map(\.genericName)
        #expect(names.count == 32 && Set(names).count == names.count)
        #expect(TrainingStudy.armReps.genericName == "Rep totals over time")
        for id in TrainingStudy.allCases {
            #expect((3...6).contains(id.genericName.split(whereSeparator: \.isWhitespace).count))
            let history = history()
            var options = StudyOptions(transpose: true, presentation: .scatter)
            #expect(history.result(for: id, options: options).galleryCaption == id.genericName)
            options.period = .year(2026)
            let customized = history.result(for: id, options: options)
            #expect(customized.galleryCaption != id.genericName)
            #expect(customized.galleryAccessibilityLabel == customized.displayTitle)
            options = StudyOptions()
            let reset = history.result(for: id, options: options)
            #expect(reset.galleryCaption == id.genericName && reset.galleryAccessibilityLabel == id.genericName)
        }
    }

    @Test("Each chart names its period, including an empty month", arguments: TrainingStudy.allCases)
    func periods(_ id: TrainingStudy) {
        let history = history()
        let original = history.result(for: id)
        #expect(original.displayTitle == id.caption)
        var labels: Set<String> = []
        var captions: Set<String> = []
        for period in [StudyPeriod.year(2025), .year(2026), .month(year: 2026, month: 3),
                       .month(year: 2026, month: 11), .all] {
            let source = history.result(for: id, options: .init(period: period))
            #expect(source.displayTitle.contains(period.label))
            #expect((3...6).contains(source.galleryCaption.split(whereSeparator: \.isWhitespace).count))
            labels.insert(source.displayTitle)
            captions.insert(source.galleryCaption)
            #expect(source.presented(as: .table, transpose: true).title == source.title)
        }
        #expect(labels.count == 5)
        #expect(captions.count == 5)
    }

    @Test("Muscles and exercises are named together when both filters apply", arguments: TrainingStudy.allCases)
    func focus(_ id: TrainingStudy) {
        var options = StudyOptions(period: .month(year: 2026, month: 11))
        if id != .legWork { options.exerciseKeys = ["catalog:single-arm-dumbbell-row"] }
        if id.hasMuscleFocus { options.muscles = [.quads] }
        if id == .relationship { options.secondExercise = StudyHistory.bench }
        let history = history()
        let result = history.result(for: id, options: options)
        let title = result.displayTitle.lowercased()
        if id != .legWork { #expect(title.contains("single arm dumbbell row")) }
        if id.hasMuscleFocus { #expect(title.contains("quads")) }
        if id == .relationship { #expect(title.contains("barbell bench press")) }
        #expect(result.galleryCaption.contains("2026"))
        #expect((3...6).contains(result.galleryCaption.split(whereSeparator: \.isWhitespace).count))
        #expect(result.displayTitle != history.result(for: id, options: .init(period: options.period)).displayTitle)
    }

    @Test("Monthly selection names the daily bucket and distinct muscle selections")
    func repTotals() {
        var options = StudyOptions(period: .month(year: 2026, month: 11), muscles: [.quads])
        let history = history()
        let november = history.result(for: .armReps, options: options)
        #expect(november.displayTitle == "Daily reps for quads · " + options.period.label)
        #expect(november.galleryCaption.lowercased().contains("quads"))
        options.muscles = [.quads, .glutes]
        let legs = history.result(for: .armReps, options: options)
        options.muscles = [.biceps, .triceps]
        let arms = history.result(for: .armReps, options: options)
        #expect(legs.galleryCaption != arms.galleryCaption)
        #expect(arms.displayTitle.contains("biceps") && arms.displayTitle.contains("triceps"))
        options.period = .year(2025)
        #expect(history.result(for: .armReps, options: options).displayTitle.hasPrefix("Monthly reps"))
    }

    @Test("Titles use the selected load unit and only the settings active in the query")
    func parameters() {
        let history = history(unit: .kilograms)
        let options = StudyOptions(parameters: [.load: 1850, .reps: 8, .sets: 4])
        let name = history.result(for: .repeatBench, options: options).displayTitle
        #expect(name.contains(history.loadText(1850)))
        #expect(name.contains("8 reps") && name.contains("4 working sets"))
        var weeks = StudyOptions(parameters: [.weeks: 3])
        #expect(history.result(for: .frequency, options: weeks).displayTitle.contains("3 weeks"))
        #expect(history.result(for: .frequency, options: weeks).galleryCaption.contains("3-week"))
        weeks.period = .year(2025)
        #expect(!history.result(for: .frequency, options: weeks).displayTitle.contains("3 weeks"))
        let maximums = history.result(for: .yearlyRecords, options: .init(period: .all, exerciseKeys: [StudyHistory.bench]))
        #expect(maximums.displayTitle.contains("Lifetime") && maximums.displayTitle.contains("Bench Press"))
        #expect(!maximums.displayTitle.contains("Period"))
    }

    @Test("Editing each available chart setting updates the title", arguments: TrainingStudy.allCases)
    func eachSetting(_ id: TrainingStudy) {
        let history = history()
        for (key, _) in id.parameters {
            let first = history.result(for: id, options: .init(parameters: [key: 11]))
            let second = history.result(for: id, options: .init(parameters: [key: 22]))
            #expect(first.displayTitle != second.displayTitle)
            #expect(first.galleryCaption != second.galleryCaption)
            #expect((3...6).contains(second.galleryCaption.split(whereSeparator: \.isWhitespace).count))
        }
    }

    @Test("Changing the horizontal lift preserves a distinct comparison, including the implicit squat")
    func distinctComparison() {
        var options = StudyOptions(secondExercise: StudyHistory.bench)
        #expect(options.horizontalLift == StudyHistory.squat)
        options.selectHorizontalLift([StudyHistory.bench])
        #expect(options.secondExercise == StudyHistory.squat)
        options.selectHorizontalLift([])
        #expect(options.horizontalLift == StudyHistory.squat && options.secondExercise == StudyHistory.bench)
    }

    @Test("Saved views survive reopening independently, including their full control selection")
    func savedControls() throws {
        let comparison = StudyOptions(
            period: .year(2025), exerciseKeys: [StudyHistory.squat], secondExercise: StudyHistory.bench,
            presentation: .scatter)
        let reps = StudyOptions(
            period: .month(year: 2026, month: 11), muscles: [.quads, .glutes],
            exerciseKeys: [StudyHistory.squat], transpose: true, presentation: .line)
        let record = StudyOptions(exerciseKeys: [StudyHistory.bench], presentation: .bar, parameters: [.reps: 8])
        // The earlier gallery stored the same chart IDs and options in a single JSON dictionary.
        let previouslySaved = try JSONEncoder().encode(["25": comparison])
        var data = try SavedStudyViews(data: previouslySaved).saving(reps, for: .armReps)
        data = try SavedStudyViews(data: data).saving(record, for: .records)
        let restored = SavedStudyViews(data: data)
        #expect(restored[.relationship] == comparison)
        #expect(restored[.armReps] == reps)
        #expect(restored[.records] == record)
        #expect(restored[.frequency] == StudyOptions())
        let reset = SavedStudyViews(data: try restored.saving(StudyOptions(), for: .armReps))
        #expect(reset[.relationship] == comparison && reset[.records] == record)
        #expect(reset[.armReps] == StudyOptions())
    }

    @Test("A chart saved by another version cannot erase a different card’s settings")
    func preservesUnrecognizedChart() throws {
        let incompatible = Data(#"{"2":{"period":{"futureRange":{}}},"5":false}"#.utf8)
        let chart = StudyOptions(period: .year(2025))
        let data = try SavedStudyViews(data: incompatible).saving(chart, for: .records)
        let reopened = SavedStudyViews(data: data)
        #expect(reopened[.records] == chart)
        #expect(reopened[.armReps] == StudyOptions())
        #expect(reopened[.repRanges] == StudyOptions())
        let entries = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(entries["2"] != nil && entries["5"] != nil)
    }

    @Test("A date range with no records keeps remembered chart and axis choices")
    func emptyViewRetainsDisplay() {
        let options = StudyOptions(period: .month(year: 2026, month: 1), transpose: true, presentation: .line)
        let source = history().result(for: .armReps, options: options)
        #expect(source.availablePresentations.contains(.line) && source.transposeLabel == "Swap axes")
        let view = source.presented(as: options.presentation, transpose: options.transpose)
        #expect(view.figure == nil && view.presentation == .line)
        for id in TrainingStudy.allCases {
            let source = history().result(for: id)
            for choice in source.availablePresentations {
                let empty = source.presented(as: choice, transpose: source.supportsTranspose)
                #expect(empty.figure == nil && empty.presentation == choice)
            }
        }
    }
}
