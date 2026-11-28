import Foundation

/// A chart the lifter starred, with the exact lifts, dates and view it showed.
struct FavoriteChart: Codable, Equatable, Identifiable {
    var id = UUID()
    let study: TrainingStudy
    let name: String
    let options: StudyOptions
}

/// The starred charts, kept on this device only, like the saved chart views. Each favorite decodes
/// on its own, so one unreadable entry, or data from another version, is skipped rather than lost.
struct FavoriteCharts {
    static let storageKey = "data.favoriteCharts"
    static let version = 1

    private(set) var charts: [FavoriteChart]

    init(data: Data) {
        guard let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              saved["version"] as? Int == Self.version, let entries = saved["charts"] as? [Any]
        else {
            charts = []
            return
        }
        charts = entries.compactMap { entry in
            guard let data = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? JSONDecoder().decode(FavoriteChart.self, from: data)
        }
    }

    /// The favorite showing this chart with exactly these choices, if there is one.
    func favorite(_ study: TrainingStudy, options: StudyOptions) -> FavoriteChart? {
        charts.first { $0.study == study && $0.options == options }
    }

    /// Stars the chart, newest first, or unstars it when it is already a favorite.
    func toggling(_ study: TrainingStudy, options: StudyOptions, name: String) throws -> Data {
        var updated = self
        if let existing = favorite(study, options: options) {
            updated.charts.removeAll { $0.id == existing.id }
        } else {
            updated.charts.insert(FavoriteChart(study: study, name: name, options: options), at: 0)
        }
        return try updated.encoded()
    }

    func removing(_ id: UUID) throws -> Data {
        var updated = self
        updated.charts.removeAll { $0.id == id }
        return try updated.encoded()
    }

    /// Nil when no favorite showed one of `oldKeys`.
    func replacingExercise(_ oldKeys: [String], with newKey: String) throws -> Data? {
        var updated = self
        for index in updated.charts.indices {
            var options = updated.charts[index].options
            options.replaceExercise(oldKeys, with: newKey)
            let chart = updated.charts[index]
            updated.charts[index] = FavoriteChart(id: chart.id, study: chart.study, name: chart.name, options: options)
        }
        return updated.charts == charts ? nil : try updated.encoded()
    }

    private func encoded() throws -> Data {
        let charts = try charts.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
        return try JSONSerialization.data(withJSONObject: ["version": Self.version, "charts": charts])
    }
}

extension TrainingStudy: Codable {}
