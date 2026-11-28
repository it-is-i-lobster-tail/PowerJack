import CoreGraphics
import Foundation

/// The axis rules every Data tab chart shares: what each axis spans, where its ticks go and how its labels sit.
/// Builders and views both read it, so a chart never picks its own tick count, label width or value range.
struct StudyAxisPlan: Equatable {
    enum XKind: Equatable {
        /// Dates across `range`. `bucket` is set when each mark covers a calendar week, month or quarter.
        case time(DateInterval, bucket: Calendar.Component?)
        /// Names in the order given.
        case category([String])
    }

    enum YKind: Equatable {
        /// Whole things such as sets, reps or sessions. Ticks never fall between two whole numbers.
        case count
        case measure(unit: String)
    }

    enum LabelStyle: Equatable { case horizontal, diagonal, vertical }

    /// How wide a label is and how tall one line is, in points, at the reader's text size.
    struct TextMetrics {
        var lineHeight: CGFloat
        var width: (String) -> CGFloat

        /// An estimate for a caption font of `size` points, close enough for tests and first layout.
        static func estimate(size: CGFloat = 12) -> TextMetrics {
            TextMetrics(lineHeight: (size * 1.2).rounded(.up)) { CGFloat($0.count) * size * 0.56 }
        }
    }

    struct TimeTick: Equatable {
        let date: Date
        let label: String
        /// Shown under the first tick and wherever the year changes.
        let year: String?
    }

    struct CategoryLabels: Equatable {
        var style: LabelStyle
        /// The labels with room to be drawn. A name too long for any style is shortened at a word.
        var shown: [String: String]
        /// Room the labels need under the plot.
        var height: CGFloat
    }

    struct ValueAxis: Equatable {
        var domain: ClosedRange<Double>
        var ticks: [Double]
        /// Set when there is nothing above zero to draw.
        var note: String?
    }

    static let emptyNote = "No sets in this range"
    static let maximumMarks = 400
    static let maximumSeries = 6

    let x: XKind
    let y: YKind
    let timeDomain: DateInterval?
    let timeTicks: [TimeTick]
    let categoryLabels: CategoryLabels?
    let valueAxis: ValueAxis

    init(
        x: XKind, y: YKind, values: [Double], includesZero: Bool = true, plotWidth: CGFloat = 300,
        metrics: TextMetrics = .estimate(), maximumLabelHeight: CGFloat = 110, calendar: Calendar = .current
    ) {
        self.x = x
        self.y = y
        valueAxis = Self.valueAxis(values: values, kind: y, includesZero: includesZero)
        switch x {
        case .time(let range, _):
            timeDomain = range
            let count = max(2, Int(plotWidth / 76))
            timeTicks = Self.timeTicks(in: range, maximumCount: count, calendar: calendar)
            categoryLabels = nil
        case .category(let names):
            timeDomain = nil
            timeTicks = []
            categoryLabels = Self.categoryLabels(
                names, slot: names.isEmpty ? plotWidth : plotWidth / CGFloat(names.count), metrics: metrics,
                maximumHeight: maximumLabelHeight)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.timeDomain == rhs.timeDomain && lhs.timeTicks == rhs.timeTicks
            && lhs.categoryLabels == rhs.categoryLabels && lhs.valueAxis == rhs.valueAxis
    }
}

// MARK: - Values

extension StudyAxisPlan {
    /// Bounds and ticks on steps of 1, 2 or 5 × 10ⁿ, as the comparison chart's dual axes pick them.
    static func valueAxis(values: [Double], kind: YKind, includesZero: Bool, maximumTicks: Int = 7) -> ValueAxis {
        let finite = values.filter(\.isFinite)
        let whole = kind == .count
        guard let low = finite.min(), let high = finite.max(), low != 0 || high != 0 else {
            let top: Double = whole ? 5 : 1
            return ValueAxis(domain: 0...top, ticks: ticks(0, top, step: whole ? 1 : 0.25), note: emptyNote)
        }
        var bottom = includesZero ? min(0, low) : low
        var top = includesZero ? max(0, high) : high
        let span = top - bottom
        let pad = span > 0 ? span * 0.08 : max(whole ? 1 : 0.5, abs(high) * 0.1)
        // Bars stand on zero. Lines and dots get room on both sides so they never sit on an axis.
        if !(includesZero && low >= 0) { bottom -= pad }
        if !(includesZero && high <= 0) { top += pad }
        if low >= 0 { bottom = max(0, bottom) }
        if high <= 0 { top = min(0, top) }

        // The smallest round step that needs no more than `maximumTicks` ticks.
        let magnitude = pow(10, log10(max((top - bottom) / Double(maximumTicks), 1e-9)).rounded(.down))
        let steps = [1.0, 2, 5, 10, 20, 50, 100].map { $0 * magnitude }.filter { !whole || $0 >= 1 }
        let fits = { (step: Double) in
            ((top / step).rounded(.up) - (bottom / step).rounded(.down)) <= Double(maximumTicks - 1)
        }
        let found = steps.first(where: fits) ?? steps.last ?? 1
        let step = whole ? found.rounded() : found
        let first = (bottom / step).rounded(.down) * step
        var last = (top / step).rounded(.up) * step
        if last <= first { last = first + step }
        return ValueAxis(domain: first...last, ticks: ticks(first, last, step: step), note: nil)
    }

    private static func ticks(_ first: Double, _ last: Double, step: Double) -> [Double] {
        let count = Int(((last - first) / step).rounded())
        // Multiply rather than add so 0.1 steps don't drift into 0.30000000000000004.
        return (0...count).map { ((first + Double($0) * step) / step).rounded() * step }
    }
}

// MARK: - Time

extension StudyAxisPlan {
    /// The calendar unit ticks step by, chosen from how long the axis is.
    static func tickUnit(for range: DateInterval) -> Calendar.Component {
        let days = range.duration / 86_400
        if days < 21 { return .day }
        if days < 92 { return .weekOfYear }
        if days < 730 { return .month }
        return .year
    }

    /// Ticks on whole calendar days, weeks, months or years inside `range`, never before its start.
    /// Labels start at their tick, so the last part of the axis keeps room for the widest one.
    /// `origin` keeps day and week ticks on the same dates while a zoomed axis pans.
    static func timeTicks(
        in range: DateInterval, origin: Date? = nil, maximumCount: Int = 4, calendar: Calendar = .current
    ) -> [TimeTick] {
        let unit = tickUnit(for: range)
        let multiples: [Int]
        switch unit {
        case .day: multiples = [1, 2, 3, 5, 7]
        case .weekOfYear: multiples = [1, 2, 4, 6]
        case .month: multiples = [1, 2, 3, 4, 6, 12]
        default: multiples = [1, 2, 5, 10, 20, 50]
        }
        let inner = DateInterval(
            start: range.start.addingTimeInterval(range.duration * 0.02),
            end: range.end.addingTimeInterval(-range.duration * 0.14))
        var dates: [Date] = []
        for multiple in multiples {
            dates = tickDates(unit, every: multiple, in: range, origin: origin ?? range.start, calendar: calendar)
                .filter { $0 >= inner.start && $0 <= inner.end }
            if dates.count <= maximumCount { break }
        }
        if dates.isEmpty {
            // A short range such as one day still names its date.
            dates = Array(tickDates(unit, every: 1, in: range, origin: origin ?? range.start, calendar: calendar).prefix(1))
        }
        var previousYear: Int?
        return dates.map { date in
            let year = calendar.component(.year, from: date)
            defer { previousYear = year }
            var style = Date.FormatStyle.dateTime
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            let label: String
            switch unit {
            case .day, .weekOfYear: label = date.formatted(style.month(.abbreviated).day())
            case .month: label = date.formatted(style.month(.abbreviated))
            default: label = date.formatted(style.year())
            }
            let showsYear = unit != .year && year != previousYear
            return TimeTick(date: date, label: label, year: showsYear ? date.formatted(style.year()) : nil)
        }
    }

    private static func tickDates(
        _ unit: Calendar.Component, every multiple: Int, in range: DateInterval, origin: Date, calendar: Calendar
    ) -> [Date] {
        var date: Date
        let step: Calendar.Component
        switch unit {
        case .day, .weekOfYear:
            step = .day
            let days = unit == .day ? multiple : multiple * 7
            var anchor = calendar.startOfDay(for: origin)
            if unit == .weekOfYear, let week = calendar.dateInterval(of: .weekOfYear, for: origin) {
                anchor = week.start
            }
            let offset = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: range.start)).day ?? 0
            let aligned = offset - ((offset % days) + days) % days
            date = calendar.date(byAdding: .day, value: aligned, to: anchor) ?? range.start
            var dates: [Date] = []
            while date <= range.end, dates.count < 400 {
                if date >= range.start { dates.append(date) }
                guard let next = calendar.date(byAdding: step, value: days, to: date) else { break }
                date = next
            }
            return dates
        case .month:
            step = .month
            date = calendar.dateInterval(of: .month, for: range.start)?.start ?? range.start
            let month = calendar.component(.month, from: date) - 1
            date = calendar.date(byAdding: .month, value: -(month % multiple), to: date) ?? date
        default:
            step = .year
            date = calendar.dateInterval(of: .year, for: range.start)?.start ?? range.start
            let year = calendar.component(.year, from: date)
            date = calendar.date(byAdding: .year, value: -(year % multiple), to: date) ?? date
        }
        var dates: [Date] = []
        while date <= range.end, dates.count < 400 {
            if date >= range.start { dates.append(date) }
            guard let next = calendar.date(byAdding: step, value: multiple, to: date) else { break }
            date = next
        }
        return dates
    }
}

// MARK: - Buckets

/// Calendar buckets across a chosen range, each trimmed to it, with the label each one shows.
struct StudyTimeline: Equatable {
    struct Bucket: Equatable {
        let label: String
        let interval: DateInterval
    }

    let range: DateInterval
    let unit: Calendar.Component
    let buckets: [Bucket]

    init(range: DateInterval, unit: Calendar.Component, calendar: Calendar = .current) {
        self.range = range
        self.unit = unit
        let intervals = Self.intervals(unit, in: range, calendar: calendar)
        let years = Set(intervals.map { calendar.component(.year, from: $0.start) })
        buckets = intervals.map {
            Bucket(label: Self.label($0.start, unit: unit, showsYear: years.count > 1, calendar: calendar), interval: $0)
        }
    }

    func bucket(containing date: Date) -> Bucket? {
        var low = 0
        var high = buckets.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let interval = buckets[middle].interval
            if date < interval.start { high = middle - 1 } else if date >= interval.end { low = middle + 1 } else {
                return buckets[middle]
            }
        }
        return nil
    }

    func interval(for label: String) -> DateInterval? { buckets.first { $0.label == label }?.interval }

    /// Weekly charts over long spans switch to months, then quarters, and stay under about 400 marks.
    static func unit(forWeekly range: DateInterval, series: Int = 1) -> Calendar.Component {
        let years = range.duration / (365.25 * 86_400)
        let units: [Calendar.Component] = years > 6 ? [.quarter, .year] : years > 2 ? [.month, .quarter, .year]
            : [.weekOfYear, .month, .quarter, .year]
        let budget = StudyAxisPlan.maximumMarks / max(1, series)
        return units.first { approximateCount($0, range) <= budget } ?? .year
    }

    private static func approximateCount(_ unit: Calendar.Component, _ range: DateInterval) -> Int {
        let days = range.duration / 86_400
        switch unit {
        case .day: return Int(days.rounded(.up))
        case .weekOfYear: return Int((days / 7).rounded(.up)) + 1
        case .month: return Int((days / 30.4).rounded(.up)) + 1
        case .quarter: return Int((days / 91.3).rounded(.up)) + 1
        default: return Int((days / 365.25).rounded(.up)) + 1
        }
    }

    /// Calendar buckets that tile `range`. The first and last are cut to the range, so a week
    /// crossing New Year in a yearly chart starts on January 1 and a day range is a single day.
    static func intervals(_ unit: Calendar.Component, in range: DateInterval, calendar: Calendar) -> [DateInterval] {
        var result: [DateInterval] = []
        var start = range.start
        while start < range.end, result.count < 2000 {
            guard let whole = interval(unit, containing: start, calendar: calendar), whole.end > start else { break }
            let end = min(whole.end, range.end)
            result.append(DateInterval(start: start, end: end))
            start = end
        }
        return result
    }

    private static func interval(_ unit: Calendar.Component, containing date: Date, calendar: Calendar) -> DateInterval? {
        guard unit == .quarter else { return calendar.dateInterval(of: unit, for: date) }
        // Foundation doesn't find quarters reliably, so count three months from January, April, July or October.
        guard let month = calendar.dateInterval(of: .month, for: date) else { return nil }
        let index = calendar.component(.month, from: date) - 1
        guard let start = calendar.date(byAdding: .month, value: -(index % 3), to: month.start),
            let end = calendar.date(byAdding: .month, value: 3, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func label(_ date: Date, unit: Calendar.Component, showsYear: Bool, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        switch unit {
        case .month: return date.formatted(showsYear ? style.month(.abbreviated).year() : style.month(.abbreviated))
        case .quarter:
            let quarter = (calendar.component(.month, from: date) - 1) / 3 + 1
            return "Q\(quarter) \(calendar.component(.year, from: date))"
        case .year: return date.formatted(style.year())
        default:
            return date.formatted(showsYear ? style.month(.abbreviated).day().year() : style.month(.abbreviated).day())
        }
    }

    /// "Week", "Month" or "Quarter", for the axis title.
    var noun: String {
        switch unit {
        case .day: "Day"
        case .month: "Month"
        case .quarter: "Quarter"
        case .year: "Year"
        default: "Week"
        }
    }

    /// "weekly", "monthly" or "quarterly", for titles that say how the chart groups time.
    var adjective: String {
        switch unit {
        case .day: "daily"
        case .month: "monthly"
        case .quarter: "quarterly"
        case .year: "yearly"
        default: "weekly"
        }
    }
}

// MARK: - Category labels

extension StudyAxisPlan {
    /// Labels stay level when they fit their slot on up to two lines, then tilt to 45°, then stand upright.
    /// A word is never split. When even upright labels crowd, every second (or third…) one is drawn.
    static func categoryLabels(
        _ names: [String], slot: CGFloat, metrics: TextMetrics, maximumHeight: CGFloat
    ) -> CategoryLabels {
        guard !names.isEmpty else { return CategoryLabels(style: .horizontal, shown: [:], height: 0) }
        let line = metrics.lineHeight
        let usable = slot - 4
        let levelLines = names.map { lines($0, width: usable, metrics: metrics) }
        if levelLines.allSatisfy({ $0 != nil && $0! <= 2 }) {
            let height = CGFloat(levelLines.compactMap { $0 }.max() ?? 1) * line
            return CategoryLabels(style: .horizontal, shown: Dictionary(names.map { ($0, $0) }) { a, _ in a },
                                  height: height)
        }
        let diagonal = sqrt(0.5)
        let style: LabelStyle
        var every = 1
        if slot >= line / diagonal {
            style = .diagonal
        } else {
            style = .vertical
            every = Int((line * 1.1 / max(1, slot)).rounded(.up))
        }
        let room = style == .diagonal ? maximumHeight / diagonal - line : maximumHeight
        var shown: [String: String] = [:]
        var widest: CGFloat = 0
        for (index, name) in names.enumerated() where index % every == 0 {
            let text = shortened(name, to: room, metrics: metrics)
            shown[name] = shown[name] ?? text
            widest = max(widest, metrics.width(text))
        }
        let height = style == .diagonal ? (widest + line) * diagonal : widest
        return CategoryLabels(style: style, shown: shown, height: min(maximumHeight, height.rounded(.up)))
    }

    /// Lines needed when wrapping only between words, or nil when one word is wider than the slot.
    private static func lines(_ text: String, width: CGFloat, metrics: TextMetrics) -> Int? {
        var count = 1
        var current = ""
        for word in text.split(separator: " ").map(String.init) {
            guard metrics.width(word) <= width else { return nil }
            let joined = current.isEmpty ? word : current + " " + word
            if metrics.width(joined) <= width {
                current = joined
            } else {
                count += 1
                current = word
            }
        }
        return count
    }

    /// Drops whole words from the end until the text fits, marking the cut with an ellipsis.
    static func shortened(_ text: String, to width: CGFloat, metrics: TextMetrics) -> String {
        guard metrics.width(text) > width else { return text }
        var words = text.split(separator: " ").map(String.init)
        while words.count > 1 {
            words.removeLast()
            let candidate = words.joined(separator: " ") + "…"
            if metrics.width(candidate) <= width { return candidate }
        }
        return words.first ?? text
    }

    /// The five largest series by total keep their names and colors. The rest share one "Other".
    static func keptSeries(_ totals: [(name: String, total: Double)]) -> [String] {
        guard totals.count > maximumSeries else { return totals.map(\.name) }
        let ranked = totals.enumerated().sorted {
            $0.element.total == $1.element.total ? $0.offset < $1.offset : $0.element.total > $1.element.total
        }
        let kept = Set(ranked.prefix(maximumSeries - 1).map(\.element.name))
        return totals.map(\.name).filter(kept.contains)
    }
}
