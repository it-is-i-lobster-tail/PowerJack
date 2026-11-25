import Foundation

enum WorkoutReminderTiming {
    nonisolated static let defaultEveningMinute = 20 * 60

    struct Prediction: Equatable {
        let workout: Date
        let send: Date
        let nightBefore: Bool

        func title(calendar: Calendar) -> String {
            if nightBefore { return "Tomorrow morning’s lift" }
            if calendar.component(.hour, from: workout) >= 17 { return "Tonight’s lift" }
            return "Today’s lift"
        }

    }

    static func next(
        starts: [Date], now: Date, calendar: Calendar, eveningMinute: Int
    ) -> Prediction? {
        let today = calendar.startOfDay(for: now)
        let startsByDay = Dictionary(grouping: starts.filter { $0 < today }) {
            calendar.startOfDay(for: $0)
        }

        let alreadyLiftedToday = starts.contains { $0 >= today && $0 <= now }
        return (0...7).compactMap { offset -> Prediction? in
            guard offset > 0 || !alreadyLiftedToday,
                  let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let previousWeeks = (1...7).compactMap { week -> [Int]? in
                guard let occurrence = calendar.date(byAdding: .day, value: -7 * week, to: day),
                      occurrence < today else { return nil }
                return (startsByDay[occurrence] ?? []).map { start in
                    calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
                }
            }
            guard let minute = typicalMinute(Array(previousWeeks.prefix(6))),
                  let workout = time(on: day, minute: minute, calendar: calendar) else { return nil }

            let nightBefore = minute < 9 * 60
            let send: Date?
            if nightBefore, let previousDay = calendar.date(byAdding: .day, value: -1, to: day) {
                send = time(on: previousDay, minute: eveningMinute, calendar: calendar)
            } else {
                send = calendar.date(byAdding: .hour, value: -3, to: workout)
            }
            guard let send, send > now else { return nil }
            return Prediction(workout: workout, send: send, nightBefore: nightBefore)
        }.min { $0.send < $1.send }
    }

    /// Each calendar occurrence contributes at most one start, even on a double-session day.
    private static func typicalMinute(_ weeks: [[Int]]) -> Int? {
        // The first start in any qualifying window is one of the observed start times.
        let clusters = Set(weeks.flatMap { $0 }).sorted().compactMap { lower -> [Int]? in
            let matches = weeks.compactMap { week in
                week.filter { (lower...lower + 120).contains($0) }
                    .min { abs($0 - (lower + 60)) < abs($1 - (lower + 60)) }
            }.sorted()
            return matches.count >= 5 ? matches : nil
        }
        let best = clusters.min { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return (lhs[lhs.count - 1] - lhs[0], lhs[0]) < (rhs[rhs.count - 1] - rhs[0], rhs[0])
        }
        guard let best else { return nil }
        return (best[(best.count - 1) / 2] + best[best.count / 2]) / 2
    }

    static func time(on day: Date, minute: Int, calendar: Calendar) -> Date? {
        guard let time = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
              calendar.isDate(time, inSameDayAs: day) else { return nil }
        return time
    }
}
