import Foundation

/// How much each lift belongs to the lifter's recent training, counted in sessions, not days.
/// Each session fades every earlier one a little, so time off changes nothing.
nonisolated struct ExerciseFamiliarity: Hashable, Sendable {
    static let none = Self(sessions: [])

    /// How much an older session still counts once a newer one is logged.
    static let fade = 0.85

    private let scores: [String: Double]

    /// Exercise keys logged in each session, oldest first.
    init(sessions: [Set<String>]) {
        var scores: [String: Double] = [:]
        for session in sessions {
            for key in scores.keys { scores[key]! *= Self.fade }
            for key in session { scores[key, default: 0] += 1 }
        }
        // A lift logged in every session approaches 1 / (1 - fade). Scale that to 1.
        self.scores = scores.mapValues { $0 * (1 - Self.fade) }
    }

    /// 0 for a lift never logged, approaching 1 for one logged every session.
    func score(_ key: String) -> Double { scores[key] ?? 0 }
}

extension ExerciseFamiliarity {
    /// Sessions from finished workouts and imported training days.
    @MainActor static func from(workouts: [Workout], imported: [ImportedSet], calendar: Calendar = .current) -> Self {
        var sessions: [(date: Date, keys: Set<String>)] = workouts.compactMap { workout in
            guard workout.status == .complete, let date = workout.endedAt ?? workout.startedAt else { return nil }
            let keys = workout.workoutExercises.compactMap { row -> String? in
                guard row.workingSets.contains(where: { $0.status == .complete }) else { return nil }
                return row.shownExercise?.searchKey
            }
            return keys.isEmpty ? nil : (date, Set(keys))
        }
        for (day, rows) in Dictionary(grouping: imported, by: \.trainingDay) {
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
            else { continue }
            sessions.append((date, Set(rows.map(\.exerciseKey).filter { !$0.isEmpty })))
        }
        return Self(sessions: sessions.sorted { $0.date < $1.date }.map(\.keys))
    }
}
