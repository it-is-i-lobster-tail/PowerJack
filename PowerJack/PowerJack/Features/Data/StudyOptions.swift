import Foundation

enum StudyPeriod: Hashable, Codable {
    case original, all
    case year(Int)
    case month(year: Int, month: Int)

    case day(year: Int, month: Int, day: Int)
    /// Any span of days, as search reads "last 3 months" or "since September". `end` is excluded.
    case range(start: Date, end: Date)

    var usesDailyBuckets: Bool {
        switch self {
        case .month, .day: true
        case let .range(start, end): end.timeIntervalSince(start) <= 62 * 24 * 60 * 60
        default: false
        }
    }

    var label: String {
        switch self {
        case .original: "Chart default"
        case .all: "All history"
        case .year(let year): String(year)
        case let .day(year, month, day):
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day))?.formatted(.dateTime.month(.wide).day().year()) ?? String(year)
        case .month(let year, let month):
            Calendar.current.date(from: DateComponents(year: year, month: month))?.formatted(.dateTime.month(.wide).year())
                ?? String(year)
        case let .range(start, end):
            (start..<max(start, end.addingTimeInterval(-1))).formatted(.interval.month(.abbreviated).day().year())
        }
    }
}

enum StudyParameter: String, Codable, Hashable {
    case load, reps, sets, sessions, gapDays, minutes, goalReps, lookback, comparisonDays, weeks

    var range: ClosedRange<Int> {
        switch self {
        case .load: 0...12000
        case .reps, .sets: 1...100
        case .sessions, .lookback, .weeks: 1...100
        case .gapDays, .comparisonDays: 1...365
        case .minutes: 1...600
        case .goalReps: 1...100000
        }
    }

    func label(for study: TrainingStudy) -> String {
        switch self {
        case .load: "Working load"
        case .reps: study == .milestones ? "Minimum reps" : "Target reps"
        case .sets: "Working sets"
        case .sessions: study == .blocks ? "Blocks" : (study == .returnToSquat ? "Return sessions" : "Sessions")
        case .gapDays: "Break length in days"
        case .minutes: "Time budget in minutes"
        case .goalReps: "Rep goal"
        case .lookback: "Baseline sessions"
        case .comparisonDays: "Days per period"
        case .weeks: "Weeks shown"
        }
    }
}

struct StudyOptions: Equatable, Codable {
    var period: StudyPeriod = .original
    var muscles: [Muscle] = []
    var exerciseKeys: [String] = []
    var secondExercise: String?
    var transpose = false
    var presentation: StudyPresentation = .original
    var parameters: [StudyParameter: Int] = [:]

    /// Keep a search phrase only while its original selection still describes the chart.
    var searchFocus: StudySearchFocus?
    var showsFullSearchTitle: Bool?

    var horizontalLift: String { exerciseKeys.first ?? StudyHistory.squat }

    mutating func selectHorizontalLift(_ keys: [String]) {
        let previous = horizontalLift
        exerciseKeys = keys
        if secondExercise == horizontalLift && previous != horizontalLift {
            secondExercise = previous
        }
    }
}

extension StudyOptions {
    /// Points the chart at `newKey` wherever it showed one of `oldKeys`, such as after a merge.
    mutating func replaceExercise(_ oldKeys: [String], with newKey: String) {
        exerciseKeys = exerciseKeys.map { oldKeys.contains($0) ? newKey : $0 }.uniqued()
        if let secondExercise, oldKeys.contains(secondExercise) { self.secondExercise = newKey }
    }

    /// Saved chart views and starred charts that showed a merged exercise show its target.
    static func replaceExercise(_ oldKeys: [String], with newKey: String, in defaults: UserDefaults) {
        if let data = defaults.data(forKey: SavedStudyViews.storageKey),
           let updated = try? SavedStudyViews(data: data).replacingExercise(oldKeys, with: newKey) {
            defaults.set(updated, forKey: SavedStudyViews.storageKey)
        }
        if let data = defaults.data(forKey: FavoriteCharts.storageKey),
           let updated = try? FavoriteCharts(data: data).replacingExercise(oldKeys, with: newKey) {
            defaults.set(updated, forKey: FavoriteCharts.storageKey)
        }
    }
}

/// Keep each chart's last applied controls under its stable study ID. An unreadable entry only affects its own card.
struct SavedStudyViews {
    static let storageKey = "data.chartOptions.v1"
    private let entries: [String: Any]

    init(data: Data) {
        entries = data.isEmpty ? [:] : (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    subscript(id: TrainingStudy) -> StudyOptions {
        guard let entry = entries[String(id.rawValue)] as? [String: Any],
            let data = try? JSONSerialization.data(withJSONObject: entry),
            let options = try? JSONDecoder().decode(StudyOptions.self, from: data)
        else { return StudyOptions() }
        return options
    }

    /// Nil when no saved view showed one of `oldKeys`.
    func replacingExercise(_ oldKeys: [String], with newKey: String) throws -> Data? {
        var data: Data?
        var views = self
        for id in TrainingStudy.allCases where entries[String(id.rawValue)] != nil {
            var options = views[id]
            let before = options
            options.replaceExercise(oldKeys, with: newKey)
            guard options != before else { continue }
            let saved = try views.saving(options, for: id)
            views = SavedStudyViews(data: saved)
            data = saved
        }
        return data
    }

    func saving(_ options: StudyOptions, for id: TrainingStudy) throws -> Data {
        var updated = entries
        let key = String(id.rawValue)
        if options == StudyOptions() {
            updated.removeValue(forKey: key)
        } else {
            updated[key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(options))
        }
        return try JSONSerialization.data(withJSONObject: updated)
    }
}

extension TrainingStudy {
    var hasMuscleFocus: Bool {
        switch self {
        case .legWork, .armReps, .gluteSources, .frequency, .repRanges, .repChanges, .legMax, .skipped, .recency,
            .sessionLedger:
            true
        default: false
        }
    }

    var multipleExercises: Bool {
        switch self {
        case .armReps, .gluteSources, .frequency, .repRanges, .repChanges, .legMax, .yearlyRecords, .skipped, .recency,
            .sessionLedger:
            true
        default: false
        }
    }

    var exerciseRole: String {
        switch self {
        case .relationship: "Horizontal exercise"
        case .substitutions: "Planned exercise"
        case .duration: "Exercise in routine"
        default: multipleExercises ? "Exercises" : "Exercise"
        }
    }

    var parameters: [(StudyParameter, Int?)] {
        switch self {
        case .legWork, .frequency, .missingEstimates: [(.weeks, 6)]
        case .repChanges, .repMix: [(.comparisonDays, 28)]
        case .records: [(.reps, nil)]
        case .fixedSquat: [(.load, 1850)]
        case .milestones: [(.reps, 5)]
        case .repeatBench: [(.load, 1850), (.sets, 3), (.reps, 5)]
        case .yearlyRecords, .squatSuccess: [(.reps, 5)]
        case .effort: [(.sessions, 12)]
        case .lastCurl: [(.load, 300)]
        case .benchSets: [(.load, 1350), (.sets, 4), (.sessions, 4)]
        case .exerciseOrder: [(.load, 300), (.reps, nil)]
        case .returnToSquat: [(.load, 1850), (.gapDays, 21), (.lookback, 3), (.sessions, 6)]
        case .blocks: [(.sessions, 3)]
        case .duration: [(.minutes, 50)]
        case .goal: [(.goalReps, 1000)]
        case .typicalBench: [(.lookback, 12)]
        case .forecast: [(.lookback, 3), (.sessions, 12)]
        case .pushups: [(.sets, 3)]
        default: []
        }
    }
}

extension TrainingStudy {
    var defaultRangeLabel: String {
        switch self {
        case .armReps, .yearlyRecords, .goal: "2026 (default)"
        case .legWork, .frequency, .missingEstimates: "Recent weeks"
        case .gluteSources, .repRanges, .skipped: "Last 28 days"
        case .repChanges, .repMix: "Two recent periods"
        case .effort, .lastCurl, .benchSets, .returnToSquat, .blocks, .typicalBench, .forecast, .tonnage:
            "Latest matching sessions"
        case .recency: "Through today"
        default: "Recorded history"
        }
    }

    var defaultExerciseLabel: String {
        switch self {
        case .records, .fixedSquat, .milestones, .substitutions, .returnToSquat, .blocks, .goal, .relationship,
            .squatSuccess, .missingEstimates, .tonnage, .effort, .duration:
            "Back squat"
        case .repeatBench, .benchSets, .repMix, .typicalBench, .forecast: "Bench press"
        case .yearlyRecords: "Four barbell lifts"
        case .lastCurl, .exerciseOrder: "Cable curl"
        case .pushups: "Push-up"
        default: "All matching exercises"
        }
    }
}
