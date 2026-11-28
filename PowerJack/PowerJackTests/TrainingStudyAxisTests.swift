import Foundation
import Testing

@testable import PowerJack

/// Every chart built from three years of imported history keeps its axes inside the chosen dates.
extension TrainingStudyTests {
    private static let periods: [StudyPeriod] = [
        .all, .year(2024), .year(2026), .month(year: 2024, month: 6), .day(year: 2026, month: 11, day: 20),
    ]

    @Test("Date axes, buckets and ticks stay inside the chosen range for every chart and view")
    func axesStayInRange() throws {
        let history = try ChartAxisFixture.history()
        for period in Self.periods {
            var options = StudyOptions()
            options.period = period
            let chosen = period.interval(in: history.calendar)
                ?? DateInterval(start: history.calendar.startOfDay(for: history.firstDate), end: history.endOfToday)
            for study in TrainingStudy.allCases {
                let source = history.result(for: study, options: options)
                if let range = source.xRange {
                    #expect(range.start >= chosen.start && range.end <= chosen.end, "\(study.caption) \(period.label)")
                }
                if let timeline = source.timeline {
                    let labels = timeline.buckets.map(\.label)
                    #expect(Set(labels).count == labels.count, "\(study.caption) \(period.label) repeats a bucket")
                    #expect(timeline.buckets.allSatisfy { $0.interval.start >= chosen.start && $0.interval.end <= chosen.end },
                            "\(study.caption) \(period.label) has a bucket outside the range")
                }
                for style in source.availablePresentations {
                    for transpose in source.supportsTranspose ? [false, true] : [false] {
                        check(source.presented(as: style, transpose: transpose), in: chosen, period: period)
                    }
                }
            }
        }
    }

    private func check(_ study: StudyResult, in chosen: DateInterval, period: StudyPeriod) {
        let name = "\(study.id.caption) \(period.label) \(study.presentation)"
        switch study.figure {
        case .traces(let series, true), .liftPanels(let series):
            let domain = study.dateDomain(for: series)
            #expect(domain.start >= chosen.start && domain.end <= chosen.end, "\(name) date axis")
            let ticks = StudyAxisPlan.timeTicks(in: domain)
            #expect(ticks.allSatisfy { domain.contains($0.date) }, "\(name) tick outside its axis")
            #expect(Set(ticks.map(\.label)).count == ticks.count, "\(name) repeats a tick label")
            let shown = series.map { $0.inside(domain) }
            #expect(shown.allSatisfy { $0.points.allSatisfy { domain.contains(Date(timeIntervalSince1970: $0.x)) } })
            let values = shown.flatMap { $0.points.map(\.y) }
            wholeTicks(study, values, bars: shown.contains { $0.style == .bars }, name)
        case .bars(let bars):
            if let timeline = study.timeline {
                #expect(!study.legendLabels.contains { timeline.interval(for: $0) != nil }, "\(name) lists weeks in its legend")
            }
            #expect(study.legendLabels.count <= StudyAxisPlan.maximumSeries, "\(name) has too many series")
            wholeTicks(study, bars.map(\.value), bars: true, name)
        default:
            break
        }
    }

    private func wholeTicks(_ study: StudyResult, _ values: [Double], bars: Bool, _ name: String) {
        guard values.allSatisfy({ $0 == $0.rounded() }) else { return }
        let axis = study.valueAxis(values, bars: bars)
        if !study.yLabel.contains("(") {
            #expect(axis.ticks.allSatisfy { $0 == $0.rounded() }, "\(name) has fractional count ticks")
        }
        if let high = values.max() { #expect(axis.domain.upperBound >= high, "\(name) cuts off its top") }
    }

    @Test("Weekly charts over all of a three-year history group by month and say so")
    func longHistoryGroupsByMonth() throws {
        let history = try ChartAxisFixture.history()
        var options = StudyOptions()
        options.period = .all
        for study in [TrainingStudy.legWork, .frequency, .missingEstimates] {
            let result = history.result(for: study, options: options)
            let timeline = try #require(result.timeline, "\(study.caption)")
            #expect(timeline.unit == .month)
            #expect(result.displayTitle.lowercased().contains("monthly"), "\(result.displayTitle)")
            let marks = timeline.buckets.count * 4
            #expect(marks < StudyAxisPlan.maximumMarks)
        }
        options.period = .year(2025)
        #expect(history.result(for: .legWork, options: options).timeline?.unit == .weekOfYear)
    }

    @Test("The first week of a year starts on January 1 and a day range shows only that day")
    func bucketsAreTrimmed() throws {
        let history = try ChartAxisFixture.history()
        var options = StudyOptions()
        options.period = .year(2026)
        let year = history.result(for: .legWork, options: options)
        guard case .matrix(let columns, _, _) = year.figure else {
            Issue.record("Expected weekly credits")
            return
        }
        #expect(columns.first == "Jan 1")
        #expect(year.timeline?.buckets.first?.interval.start == history.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        options.period = .day(year: 2026, month: 11, day: 20)
        let day = history.result(for: .legWork, options: options)
        guard case .matrix(let dayColumns, _, _) = day.figure else {
            Issue.record("Expected one day of credits")
            return
        }
        #expect(dayColumns == ["Nov 20"])

        options.period = .year(2026)
        let months = history.result(for: .armReps, options: options)
        #expect(months.timeline?.buckets.first?.label == "Jan")
        #expect(months.timeline?.buckets.last?.label == "Nov")
    }

    @Test("A recent-range chart only plots sessions inside the chosen month")
    func recentRangeStaysInMonth() throws {
        let history = try ChartAxisFixture.history()
        var options = StudyOptions()
        options.period = .month(year: 2024, month: 6)
        let result = history.result(for: .typicalBench, options: options)
        guard case .traces(let series, true) = result.figure else { return }
        let domain = result.dateDomain(for: series)
        let june = try #require(options.period.interval(in: history.calendar))
        #expect(domain == june)
        #expect(series.map { $0.inside(domain) }.allSatisfy { $0.points.allSatisfy { june.contains(Date(timeIntervalSince1970: $0.x)) } })
    }
}
