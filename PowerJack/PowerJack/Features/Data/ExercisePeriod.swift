import Foundation

enum HistoryWindow {
    static let limit = 12

    /// Include both ends of the visible range, with at most five evenly spaced labels.
    static func tickIndices(in visible: Range<Int>) -> [Int] {
        guard visible.count > 5 else { return Array(visible) }
        return (0..<5).map { tick in
            visible.lowerBound + Int((Double(tick * (visible.count - 1)) / 4).rounded())
        }
    }

    static func maximumSpan(count: Int) -> Double {
        min(1, Double(limit) / Double(max(1, count)))
    }

    static func index(at fraction: Double, count: Int, window: ClosedRange<Double>) -> Int {
        let visible = indices(count: count, window: window)
        return visible.lowerBound + min(visible.count - 1, max(0, Int(fraction * Double(visible.count))))
    }

    /// Snap both edges together so a partially panned or zoomed window never draws a thirteenth mark.
    static func indices(count: Int, window: ClosedRange<Double>) -> Range<Int> {
        let width = min(count, limit, max(1, Int(((window.upperBound - window.lowerBound) * Double(count)).rounded())))
        let first = min(count - width, max(0, Int((window.lowerBound * Double(count)).rounded())))
        return first..<(first + width)
    }
}

struct ExercisePeriod: Identifiable {
    let id: Date
    let index: Int
    var sessionIndices: [Int] = []
    private(set) var targetLoad = Mean()
    private(set) var load = Mean()
    private(set) var targetReps = Mean()
    private(set) var reps = Mean()

    struct Mean {
        private var total = 0.0
        private var count = 0
        var value: Double? { count > 0 ? total / Double(count) : nil }

        mutating func add(_ value: Int?) {
            guard let value else { return }
            total += Double(value)
            count += 1
        }
    }

    mutating func record(_ set: ProgramExerciseHistory.LoggedSet) {
        targetLoad.add(set.targetLoad)
        load.add(set.load)
        targetReps.add(set.targetReps)
        reps.add(set.reps)
    }

    static func weeks(_ exercise: ProgramExerciseHistory,
                        now: Date = .now, calendar: Calendar = .current) -> [Self] {
        guard let firstDate = VolumeRange.days90.start(before: now, calendar: calendar),
              var date = calendar.dateInterval(of: .weekOfYear, for: firstDate)?.start else { return [] }
        var periods: [Self] = []
        var lookup: [Date: Int] = [:]
        while date <= now {
            lookup[date] = periods.count
            periods.append(Self(id: date, index: periods.count))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: date), next > date else { break }
            date = next
        }
        for (index, session) in exercise.sessions.enumerated() {
            guard let date = session.date, let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
                  let period = lookup[start] else { continue }
            periods[period].sessionIndices.append(index)
            for set in exercise.sets[(session.firstSet - 1)..<session.lastSet] {
                periods[period].record(set)
            }
        }
        return periods
    }
}
