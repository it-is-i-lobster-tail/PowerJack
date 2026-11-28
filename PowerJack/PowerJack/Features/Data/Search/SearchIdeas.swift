import Foundation

/// Five searches to try, built from the lifter's own log so each one finds their data.
enum SearchIdeas {
    static func make(from history: StudyHistory) -> [String] {
        let trained = history.sessions.filter { !$0.done.isEmpty }
        // Lifts with an external load, most logged first.
        let loaded = Dictionary(grouping: trained.filter(\.loaded), by: \.key)
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
            .compactMap { $0.value.last?.name }
        let muscle = Dictionary(grouping: trained.compactMap(\.primary), by: { $0 })
            .max { ($0.value.count, $1.key.rawValue) < ($1.value.count, $0.key.rawValue) }?.key
        let first = loaded.first ?? "Bench"
        let second = loaded.dropFirst().first ?? (loaded.isEmpty ? "Squat" : first)
        return [
            "\(first) progress",
            "\((muscle?.rawValue ?? "chest").capitalized) volume last month",
            "Heaviest \(second)",
            "When did I last train legs",
            "Workouts this year",
        ]
    }
}
