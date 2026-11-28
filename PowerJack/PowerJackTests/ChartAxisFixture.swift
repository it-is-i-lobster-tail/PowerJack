import Foundation
import SwiftData

@testable import PowerJack

/// A made-up FitNotes export: three years of Monday, Wednesday and Friday lifting with slow progress,
/// a few long exercise names and a break. Shaped like a real export, built from no one's real log.
enum ChartAxisFixture {
    static let lifts: [(name: String, category: String, start: Int, reps: [Int])] = [
        ("Barbell Squat", "Legs", 135, [5, 5, 5]),
        ("Flat Barbell Bench Press", "Chest", 95, [8, 8, 6]),
        ("Deadlift", "Back", 185, [5, 3]),
        ("Cable Curl", "Biceps", 30, [12, 10, 10]),
        ("Lying Leg Curl Machine", "Legs", 60, [12, 12]),
        ("Single Leg Romanian Deadlift With Dumbbells", "Legs", 20, [10, 10]),
        ("Barbell Hip Thrust", "Legs", 95, [10, 8]),
        ("Push Up", "Chest", 0, [20, 15, 12]),
    ]

    static let first = DateComponents(year: 2023, month: 9, day: 4)
    static let last = DateComponents(year: 2026, month: 11, day: 20)
    static let today = DateComponents(year: 2026, month: 11, day: 23, hour: 20)

    /// The export text. Each workout day trains four of the lifts in turn.
    static func csv(calendar: Calendar) -> String {
        var lines = [FitNotesImport.columns.joined(separator: ",")]
        var day = calendar.date(from: first)!
        let end = calendar.date(from: last)!
        var session = 0
        let breakStart = calendar.date(from: DateComponents(year: 2025, month: 7, day: 1))!
        let breakEnd = calendar.date(from: DateComponents(year: 2025, month: 7, day: 29))!
        while day <= end {
            let weekday = calendar.component(.weekday, from: day)
            if [2, 4, 6].contains(weekday), !(breakStart..<breakEnd).contains(day) {
                let stamp = day.formatted(.iso8601.year().month().day())
                let weeks = session / 3
                for offset in 0..<4 {
                    let lift = lifts[(session + offset * 2) % lifts.count]
                    let load = lift.start == 0 ? 0 : lift.start + 5 * (weeks / 3) % 120
                    for reps in lift.reps {
                        lines.append("\(stamp),\(lift.name),\(lift.category),\(load).0,lbs,\(reps),,,,\"\"")
                    }
                }
                session += 1
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return lines.joined(separator: "\n")
    }

    /// The fixture imported the way Settings imports a file, matched to built-in lifts where search is sure.
    @MainActor
    static func history(calendar: Calendar = .current) throws -> StudyHistory {
        let rows = try FitNotesImport.parse(Data(csv(calendar: calendar).utf8))
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        var exercises = ExerciseCatalog.entries.map { $0.makeExercise() }
        exercises.forEach(context.insert)
        let index = ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
        var matches: [String: Exercise] = [:]
        for lift in lifts {
            if case .match(let exercise) = FitNotesMatcher.search(
                lift.name, category: lift.category, among: exercises, index: index, familiarity: .none).suggestion {
                matches[lift.name] = exercise
            } else {
                let exercise = Exercise(
                    exerciseName: lift.name, exerciseEquipment: .dumbbell,
                    primaryMuscleFocus: FitNotesMatcher.primaryMuscle(for: lift.name, category: lift.category) ?? .hamstrings,
                    userCreated: true)
                context.insert(exercise)
                exercises.append(exercise)
                matches[lift.name] = exercise
            }
        }
        _ = try FitNotesImport.save(rows, matches: matches, in: context)
        return StudyHistory(
            programs: [], archive: [], logs: [], imported: try context.fetch(FetchDescriptor<ImportedSet>()),
            exercises: exercises, unit: .pounds, today: calendar.date(from: today)!, calendar: calendar)
    }
}
