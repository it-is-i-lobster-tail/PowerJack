import Foundation
import SwiftData

/// Reading and deleting the sets brought in from other apps, such as FitNotes.
enum ImportedData {
    /// One training day of imported sets, in the order the other app logged them.
    struct Day: Identifiable {
        let id: String
        let sets: [ImportedSet]

        var title: String { ImportedData.title(forDay: id) }
    }

    /// Newest day first, each day's sets in logged order.
    static func days(_ sets: [ImportedSet]) -> [Day] {
        Dictionary(grouping: sets, by: \.trainingDay)
            .map { Day(id: $0.key, sets: $0.value.sorted { $0.sourceOrder < $1.sourceOrder }) }
            .sorted { $0.id > $1.id }
    }

    /// One search document per imported lift, known by its PowerJack name and the name the other app used.
    @MainActor static func documents(for sets: [ImportedSet], exercises: [Exercise]) -> [ExerciseSearch.Document] {
        let byKey = Dictionary(exercises.compactMap { e in e.syncKey.map { ($0, e) } }, uniquingKeysWith: { first, _ in first })
        return Dictionary(grouping: sets, by: \.exerciseKey).map { key, sets in
            let otherNames = sets.flatMap { [$0.exerciseName, $0.sourceExercise] }.filter { !$0.isEmpty }
            guard let exercise = byKey[key] else {
                return ExerciseSearch.Document(key: key, names: otherNames.uniqued(),
                                               primary: Muscle(rawValue: sets[0].muscle) ?? .chest, secondary: [],
                                               equipment: .bodyweight)
            }
            let document = ExerciseSearch.Document(exercise)
            return ExerciseSearch.Document(key: key, names: (document.names + otherNames).uniqued(),
                                           primary: document.primary, secondary: document.secondary,
                                           equipment: document.equipment, pattern: document.pattern,
                                           structure: document.structure)
        }
    }

    /// The sets a search finds: every set when the search is empty. Until the index is ready,
    /// names that contain the text.
    static func matching(_ search: String, in sets: [ImportedSet], index: ExerciseSearch.Index?) -> [ImportedSet] {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return sets }
        guard let index else {
            return sets.filter { $0.exerciseName.localizedStandardContains(text) || $0.sourceExercise.localizedStandardContains(text) }
        }
        let keys = Set(index.rank(ExerciseQuery(text)).map(\.key))
        return sets.filter { keys.contains($0.exerciseKey) }
    }

    /// Deletes the sets, all or none. iCloud Backup removes them from iCloud too.
    static func delete(_ sets: [ImportedSet], in context: ModelContext) throws {
        guard !sets.isEmpty else { return }
        for set in sets { context.delete(set) }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// What was lifted, such as "135 lb × 8 reps", plus any time or distance.
    static func detail(_ set: ImportedSet, unit: WeightUnit) -> String {
        let weight = set.weightTenthsPounds.map { "\(unit.format(tenthsPounds: $0)) \(unit.symbol)" }
        let reps = set.reps.map { $0 == 1 ? "1 rep" : "\($0) reps" }
        let lift = [weight, reps].compactMap { $0 }.joined(separator: " × ")
        let time = set.durationSeconds.map { seconds in
            Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
        }
        let distance = set.distance.map { "\($0.formatted()) \(set.distanceUnit)" }
        return [lift.isEmpty ? nil : lift, time, distance].compactMap { $0 }.joined(separator: " · ")
    }

    /// The day as the lifter reads it, such as "Tue, Mar 4, 2025". Days are stored as yyyy-MM-dd.
    static func title(forDay day: String) -> String {
        guard let date = dayParser.date(from: day) else { return day }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()
        style.timeZone = .gmt
        return date.formatted(style)
    }

    private static let dayParser: DateFormatter = {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .gmt
        parser.dateFormat = "yyyy-MM-dd"
        return parser
    }()
}
