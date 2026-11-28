import Foundation
import Testing

@testable import PowerJack

struct StudyRecentRangeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("Last 4 weeks is the 28 days through the end of today")
    func fourWeeks() {
        let span = StudyRecentSpan.fourWeeks.interval(today: date(2026, 11, 28, hour: 20), calendar: calendar)
        #expect(span.start == date(2026, 11, 1))
        #expect(span.end == date(2026, 11, 29))
        #expect(calendar.dateComponents([.day], from: span.start, to: span.end).day == 28)
    }

    @Test("Last 3 months starts the day after the same date three months back, even at month ends")
    func threeMonths() {
        let cases: [(today: Date, start: Date)] = [
            (date(2026, 11, 28, hour: 9), date(2026, 8, 29)),
            // May 31 back three months clamps to February 28, so the span opens March 1.
            (date(2026, 5, 31), date(2026, 3, 1)),
            (date(2024, 5, 31), date(2024, 3, 1)),
            (date(2026, 3, 31), date(2026, 1, 1)),
            (date(2026, 1, 15), date(2025, 10, 16)),
        ]
        for (today, start) in cases {
            let span = StudyRecentSpan.threeMonths.interval(today: today, calendar: calendar)
            #expect(span.start == start, "\(today)")
            #expect(span.end == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)))
        }
    }

    @Test("Both spans start and end at midnight across a daylight saving change")
    func daylightSaving() {
        for today in [date(2026, 3, 20, hour: 12), date(2026, 11, 3, hour: 1)] {
            for span in StudyRecentSpan.allCases {
                let interval = span.interval(today: today, calendar: calendar)
                for edge in [interval.start, interval.end] {
                    let parts = calendar.dateComponents([.hour, .minute], from: edge)
                    #expect(parts.hour == 0 && parts.minute == 0, "\(span) \(today)")
                }
            }
        }
        let spring = StudyRecentSpan.fourWeeks.interval(today: date(2026, 3, 20, hour: 12), calendar: calendar)
        #expect(calendar.dateComponents([.day], from: spring.start, to: spring.end).day == 28)
    }

    @Test("Four weeks ticks every week and three months every week or second week")
    func ticks() {
        let today = date(2026, 11, 28)
        let four = StudyRecentSpan.fourWeeks.interval(today: today, calendar: calendar)
        let three = StudyRecentSpan.threeMonths.interval(today: today, calendar: calendar)
        #expect(StudyAxisPlan.tickUnit(for: four) == .weekOfYear)
        #expect(StudyAxisPlan.tickUnit(for: three) == .weekOfYear)
        for span in [four, three] {
            let ticks = StudyAxisPlan.timeTicks(in: span, calendar: calendar)
            #expect(ticks.count >= 2)
            #expect(ticks.allSatisfy { span.contains($0.date) })
            let gaps = zip(ticks, ticks.dropFirst()).map {
                calendar.dateComponents([.day], from: $0.date, to: $1.date).day ?? 0
            }
            #expect(gaps.allSatisfy { $0 == 7 || $0 == 14 }, "\(gaps)")
        }
    }

    @Test("The range picker offers both spans and labels them")
    func pickerChoices() {
        let choices = StudyPeriodPicker.choices(current: .original)
        #expect(choices.contains(.fourWeeks) && choices.contains(.threeMonths))
        #expect(!choices.contains(.range))
        #expect(StudyPeriodPicker.choices(current: .range(start: .now, end: .now)).contains(.range))
        #expect(StudyPeriod.recent(.fourWeeks).label == "Last 4 weeks")
        #expect(StudyPeriod.recent(.threeMonths).label == "Last 3 months")
        #expect(StudyPeriod.recent(.fourWeeks).usesDailyBuckets)
        #expect(!StudyPeriod.recent(.threeMonths).usesDailyBuckets)
    }

    @Test("Saved chart views from before still load, and a saved recent span stays recent")
    func savedViews() throws {
        // As earlier builds wrote them: a year, all history and a span of days.
        let older = #"{"1":{"period":{"year":{"_0":2025}},"muscles":[],"exerciseKeys":[],"transpose":false,"presentation":"bar","parameters":[]},"#
            + #""2":{"period":{"all":{}},"muscles":[],"exerciseKeys":[],"transpose":true,"presentation":"original","parameters":[]},"#
            + #""4":{"period":{"range":{"start":800000000,"end":800864000}},"muscles":[],"exerciseKeys":[],"transpose":false,"presentation":"original","parameters":[]}}"#
        let saved = SavedStudyViews(data: Data(older.utf8))
        #expect(saved[.legWork].period == .year(2025))
        #expect(saved[.legWork].presentation == .bar)
        #expect(saved[.armReps].period == .all)
        #expect(saved[.armReps].transpose)
        #expect(saved[.frequency].period == .range(start: Date(timeIntervalSinceReferenceDate: 800000000),
                                                    end: Date(timeIntervalSinceReferenceDate: 800864000)))

        var recent = StudyOptions()
        recent.period = .recent(.threeMonths)
        let data = try SavedStudyViews(data: Data(older.utf8)).saving(recent, for: .recency)
        let restored = SavedStudyViews(data: data)
        #expect(restored[.recency].period == .recent(.threeMonths))
        #expect(restored[.legWork].period == .year(2025))
    }

    @MainActor
    @Test("Charts over the last 4 weeks and 3 months stay inside their span")
    func historyUsesSpans() throws {
        let history = try ChartAxisFixture.history()
        for span in StudyRecentSpan.allCases {
            var options = StudyOptions()
            options.period = .recent(span)
            let chosen = span.interval(today: history.today, calendar: history.calendar)
            let weekly = history.result(for: .legWork, options: options)
            #expect(weekly.xRange == chosen)
            #expect(weekly.timeline?.unit == .weekOfYear)
            #expect(weekly.timeline?.buckets.first?.interval.start == chosen.start)
            #expect(weekly.displayTitle.hasSuffix(span.label))
            let goal = history.result(for: .pushups, options: options)
            if case .traces(let series, true) = goal.figure {
                #expect(goal.dateDomain(for: series) == chosen)
            }
        }
    }
}

struct StudyMatrixTests {
    @Test("Dark mode cells start at a quarter fill, light at an eighth, and both top out together")
    func cellOpacity() {
        #expect(StudyMatrix.opacity(0, dark: true) == 0.25)
        #expect(StudyMatrix.opacity(0, dark: false) == 0.12)
        #expect(StudyMatrix.opacity(1, dark: true) == StudyMatrix.opacity(1, dark: false))
        #expect(StudyMatrix.opacity(0.1, dark: true) > StudyMatrix.opacity(0.1, dark: false))
    }

    @Test("A heatmap opens on its first column with data")
    func firstColumn() {
        #expect(StudyMatrix.firstDataColumn([[nil, nil, 3, nil], [nil, 0, nil, nil]]) == 1)
        #expect(StudyMatrix.firstDataColumn([[nil, nil], [nil, nil]]) == nil)
        #expect(StudyMatrix.firstDataColumn([[2]]) == 0)
    }
}
