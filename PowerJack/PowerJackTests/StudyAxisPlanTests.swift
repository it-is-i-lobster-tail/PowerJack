import Foundation
import Testing

@testable import PowerJack

struct StudyAxisPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func range(_ start: Date, _ end: Date) -> DateInterval { DateInterval(start: start, end: end) }

    // MARK: Values

    @Test("No data and all zero values get a 0 to 5 count floor or 0 to 1 measure floor, with a note")
    func emptyValues() {
        let none = StudyAxisPlan.valueAxis(values: [], kind: .count, includesZero: true)
        #expect(none.domain == 0...5)
        #expect(none.ticks == [0, 1, 2, 3, 4, 5])
        #expect(none.note == StudyAxisPlan.emptyNote)
        let zeros = StudyAxisPlan.valueAxis(values: [0, 0, 0], kind: .measure(unit: "lb"), includesZero: false)
        #expect(zeros.domain == 0...1)
        #expect(zeros.ticks.first == 0 && zeros.ticks.last == 1)
        #expect(zeros.note != nil)
    }

    @Test("One point sits inside its axis, not on an edge")
    func onePoint() {
        let axis = StudyAxisPlan.valueAxis(values: [225], kind: .measure(unit: "lb"), includesZero: false)
        #expect(axis.domain.lowerBound < 225 && axis.domain.upperBound > 225)
        #expect(axis.ticks.count >= 2)
        #expect(axis.note == nil)
    }

    @Test("Lines and dots keep a gap above the floor and below the top")
    func linesClearTheAxis() {
        for values in [[5.0, 6, 9, 12], [185, 190, 200], [0.4, 0.9], [1000, 1010, 1100]] {
            let axis = StudyAxisPlan.valueAxis(values: values, kind: .measure(unit: "lb"), includesZero: false)
            #expect(axis.domain.lowerBound < values.min()!, "\(values)")
            #expect(axis.domain.upperBound > values.max()!, "\(values)")
        }
        // Bars still stand on zero.
        #expect(StudyAxisPlan.valueAxis(values: [3, 8], kind: .count, includesZero: true).domain.lowerBound == 0)
    }

    @Test("A huge outlier still gets a handful of round ticks that cover it")
    func outlier() {
        let axis = StudyAxisPlan.valueAxis(values: [3, 4, 5, 4, 980], kind: .count, includesZero: true)
        #expect(axis.domain.upperBound >= 980)
        #expect(axis.ticks.count <= 7)
        let step = axis.ticks[1] - axis.ticks[0]
        let magnitude = pow(10, log10(step).rounded(.down))
        #expect([1.0, 2, 5].contains(step / magnitude))
    }

    @Test("Counts never get fractional ticks")
    func wholeTicks() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            let values = (0..<Int.random(in: 1...20, using: &generator)).map { _ in
                Double(Int.random(in: 0...Int.random(in: 1...400, using: &generator), using: &generator))
            }
            let axis = StudyAxisPlan.valueAxis(values: values, kind: .count, includesZero: Bool.random(using: &generator))
            #expect(axis.ticks.allSatisfy { $0 == $0.rounded() }, "\(values)")
            #expect(axis.ticks.count >= 2)
        }
        // Two sessions at most is 0, 1, 2, not 0.5 steps.
        #expect(StudyAxisPlan.valueAxis(values: [0, 1, 2, 1], kind: .count, includesZero: true).ticks == [0, 1, 2, 3])
    }

    @Test("Pounds and kilograms both land on round steps")
    func units() {
        let pounds = StudyAxisPlan.valueAxis(values: [225, 245, 275, 315], kind: .measure(unit: "lb"), includesZero: false)
        let kilograms = StudyAxisPlan.valueAxis(
            values: [102.5, 110, 122.5, 142.5], kind: .measure(unit: "kg"), includesZero: false)
        for axis in [pounds, kilograms] {
            let step = axis.ticks[1] - axis.ticks[0]
            #expect(axis.ticks.allSatisfy { ($0 / step).rounded() * step == $0 })
            #expect((3...7).contains(axis.ticks.count))
        }
        #expect(pounds.domain.contains(225) && pounds.domain.contains(315))
        #expect(kilograms.domain.contains(102.5) && kilograms.domain.contains(142.5))
    }

    // MARK: Time

    @Test("A 2026 axis never ticks before January 1 2026 and shows the year once")
    func yearTicks() {
        let year = range(date(2026, 1, 1), date(2027, 1, 1))
        let ticks = StudyAxisPlan.timeTicks(in: year, calendar: calendar)
        #expect(!ticks.isEmpty)
        #expect(ticks.allSatisfy { $0.date >= year.start && $0.date < year.end })
        #expect(ticks.allSatisfy { calendar.component(.day, from: $0.date) == 1 })
        #expect(ticks.first?.year == "2026")
        #expect(ticks.dropFirst().allSatisfy { $0.year == nil })
        let plan = StudyAxisPlan(x: .time(year, bucket: nil), y: .count, values: [1], calendar: calendar)
        #expect(plan.timeDomain == year)
        #expect(plan.timeTicks.allSatisfy { $0.date >= year.start })
    }

    @Test("Ticks step by day, week, month or year from the span, and the year shows where it changes")
    func strides() {
        #expect(StudyAxisPlan.tickUnit(for: range(date(2026, 3, 1), date(2026, 3, 15))) == .day)
        #expect(StudyAxisPlan.tickUnit(for: range(date(2026, 3, 1), date(2026, 5, 1))) == .weekOfYear)
        #expect(StudyAxisPlan.tickUnit(for: range(date(2025, 3, 1), date(2026, 5, 1))) == .month)
        #expect(StudyAxisPlan.tickUnit(for: range(date(2023, 9, 26), date(2026, 11, 24))) == .year)

        let span = range(date(2025, 9, 1), date(2026, 6, 1))
        let ticks = StudyAxisPlan.timeTicks(in: span, maximumCount: 12, calendar: calendar)
        let january = ticks.first { calendar.component(.month, from: $0.date) == 1 }
        #expect(ticks.first?.year == "2025")
        #expect(january?.year == "2026")

        let history = range(date(2023, 9, 26), date(2026, 11, 24))
        let years = StudyAxisPlan.timeTicks(in: history, calendar: calendar)
        #expect(years.map(\.label) == ["2024", "2025", "2026"])
    }

    @Test("A day range has a single day bucket and a tick naming it")
    func dayRange() {
        let day = range(date(2026, 11, 21), date(2026, 11, 22))
        let timeline = StudyTimeline(range: day, unit: .weekOfYear, calendar: calendar)
        #expect(timeline.buckets.count == 1)
        #expect(timeline.buckets[0].interval == day)
        #expect(timeline.buckets[0].label == "Nov 21")
        let ticks = StudyAxisPlan.timeTicks(in: day, calendar: calendar)
        #expect(ticks.map(\.date) == [day.start])
    }

    @Test("A week crossing New Year starts on January 1 and is named by its first day in range")
    func newYearWeek() {
        let year = range(date(2026, 1, 1), date(2027, 1, 1))
        let timeline = StudyTimeline(range: year, unit: .weekOfYear, calendar: calendar)
        #expect(timeline.buckets.first?.interval.start == year.start)
        #expect(timeline.buckets.first?.label == "Jan 1")
        #expect(timeline.buckets.last?.interval.end == year.end)
        #expect(Set(timeline.buckets.map(\.label)).count == timeline.buckets.count)
        for (a, b) in zip(timeline.buckets, timeline.buckets.dropFirst()) {
            #expect(a.interval.end == b.interval.start)
        }
        #expect(timeline.bucket(containing: date(2026, 1, 2))?.label == "Jan 1")
        #expect(timeline.bucket(containing: date(2025, 12, 31)) == nil)
    }

    @Test("Buckets across a daylight saving change stay whole days that start at midnight")
    func daylightSaving() {
        let spring = range(date(2026, 2, 20), date(2026, 4, 1))
        let timeline = StudyTimeline(range: spring, unit: .weekOfYear, calendar: calendar)
        for bucket in timeline.buckets {
            let start = calendar.dateComponents([.hour, .minute], from: bucket.interval.start)
            #expect(start.hour == 0 && start.minute == 0)
        }
        let ticks = StudyAxisPlan.timeTicks(in: range(date(2026, 3, 1), date(2026, 3, 15)), maximumCount: 14,
                                            calendar: calendar)
        #expect(ticks.allSatisfy { calendar.component(.hour, from: $0.date) == 0 })
        #expect(Set(ticks.map(\.label)).count == ticks.count)
    }

    @Test("Long weekly ranges switch to months over two years, quarters over six, and stay under 400 marks")
    func longRanges() {
        let year = range(date(2025, 1, 1), date(2026, 1, 1))
        #expect(StudyTimeline.unit(forWeekly: year, series: 4) == .weekOfYear)
        let three = range(date(2023, 9, 26), date(2026, 11, 24))
        #expect(StudyTimeline.unit(forWeekly: three, series: 4) == .month)
        let ten = range(date(2016, 11, 1), date(2026, 11, 24))
        let unit = StudyTimeline.unit(forWeekly: ten, series: 4)
        #expect(unit == .quarter)
        let timeline = StudyTimeline(range: ten, unit: unit, calendar: calendar)
        #expect(timeline.buckets.count * 4 < StudyAxisPlan.maximumMarks)
        #expect(timeline.buckets.first?.label == "Q4 2016")
        #expect(timeline.buckets.allSatisfy { ten.start <= $0.interval.start && $0.interval.end <= ten.end })
        #expect(timeline.adjective == "quarterly")
    }

    // MARK: Category labels

    @Test("Short names stay level, a 40-character name tilts or stands up, and words are never cut")
    func labelOrder() {
        let metrics = StudyAxisPlan.TextMetrics.estimate()
        let weekdays = StudyAxisPlan.categoryLabels(
            ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], slot: 46, metrics: metrics, maximumHeight: 110)
        #expect(weekdays.style == .horizontal)
        #expect(weekdays.shown.count == 7)

        let long = "Single Leg Romanian Deadlift With Dumbbells"
        let names = [long, "Hip Thrust", "Back Squat", "Leg Curl", "Leg Extension"]
        let tilted = StudyAxisPlan.categoryLabels(names, slot: 64, metrics: metrics, maximumHeight: 110)
        #expect(tilted.style == .diagonal || tilted.style == .vertical)
        #expect(tilted.shown.count == names.count)
        for (name, text) in tilted.shown {
            let kept = text.replacingOccurrences(of: "…", with: "")
            #expect(name.hasPrefix(kept))
            #expect(kept == name || name.split(separator: " ").map(String.init).contains(kept.split(separator: " ").last.map(String.init)!))
        }

        let crowded = StudyAxisPlan.categoryLabels(
            (1...30).map { "Exercise number \($0)" }, slot: 11, metrics: metrics, maximumHeight: 110)
        #expect(crowded.style == .vertical)
        #expect(crowded.shown.count < 30)
    }

    @Test("Larger text needs more room, so labels tilt sooner and the axis grows")
    func dynamicType() {
        let names = ["Hip Thrust", "Back Squat", "Leg Curl", "Leg Extension"]
        let regular = StudyAxisPlan.categoryLabels(names, slot: 80, metrics: .estimate(size: 12), maximumHeight: 110)
        let large = StudyAxisPlan.categoryLabels(names, slot: 80, metrics: .estimate(size: 28), maximumHeight: 110)
        #expect(regular.style == .horizontal)
        #expect(large.style != .horizontal)
        #expect(large.height > regular.height)
        #expect(large.height <= 110)
    }

    @Test("More than six series keep the five largest and fold the rest into Other")
    func manySeries() {
        let groups = (1...10).map { "Lift \($0)" }
        let bars = ["Jan", "Feb"].flatMap { label in
            groups.enumerated().map { StudyBar(label: label, value: Double($0.offset + 1), group: $0.element) }
        }
        let merged = StudyResult.limitingSeries(bars, sums: true)
        let names = merged.map(\.group).studyUnique
        #expect(names.count == 6)
        #expect(names.last == "Other")
        #expect(Set(names.dropLast()) == Set(["Lift 6", "Lift 7", "Lift 8", "Lift 9", "Lift 10"]))
        let total = { (list: [StudyBar]) in list.reduce(0) { $0 + $1.value } }
        #expect(total(merged) == total(bars))
        #expect(StudyResult.limitingSeries(Array(bars.prefix(6)), sums: true) == Array(bars.prefix(6)))
        #expect(StudyResult.limitingSeries(bars, sums: false).count == bars.count)
    }
}
