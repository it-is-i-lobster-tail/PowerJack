import CryptoKit
import Foundation
import SwiftData
import TabularData

struct FitNotesSet: Sendable {
    let key: String
    let day: String
    let name: String
    let category: String
    let weight: Int?
    let reps: Int?
    let distance: Double?
    let distanceUnit: String
    let seconds: Int?
    let comment: String
}

nonisolated struct FitNotesError: LocalizedError {
    var errorDescription: String?
    init(_ text: String) { errorDescription = text }
}

nonisolated enum FitNotesImport {
    static let columns = ["Date", "Exercise", "Category", "Weight", "Weight Unit", "Reps",
                          "Distance", "Distance Unit", "Time", "Comment"]

    static func read(_ url: URL) async throws -> [FitNotesSet] {
        try await Task.detached {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try parse(Data(contentsOf: url))
        }.value
    }

    static func parse(_ data: Data) throws -> [FitNotesSet] {
        let types = Dictionary(uniqueKeysWithValues: columns.map { ($0, CSVType.string) })
        let table = try DataFrame(csvData: data, types: types, options: .init(nilEncodings: [""]))
        guard Set(columns).isSubset(of: table.columns.map(\.name)), !table.rows.isEmpty else {
            throw FitNotesError("Choose a FitNotes workout CSV with at least one set.")
        }
        let dates = DateFormatter()
        dates.locale = Locale(identifier: "en_US_POSIX")
        dates.timeZone = TimeZone(secondsFromGMT: 0)
        dates.dateFormat = "yyyy-MM-dd"
        var occurrences: [String: Int] = [:]
        return try table.rows.enumerated().map { index, row in
            let fields = columns.map { row[$0] as? String ?? "" }
            let error = FitNotesError("Check the exercise name, date, units and numbers in CSV row \(index + 2).")
            guard !fields[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let date = dates.date(from: fields[0]), dates.string(from: date) == fields[0] else { throw error }
            var weight: Int?
            if !fields[3].isEmpty {
                let unit: WeightUnit
                switch fields[4].lowercased() {
                case "lb", "lbs": unit = .pounds
                case "kg", "kgs": unit = .kilograms
                default: throw error
                }
                guard let value = Double(fields[3]), abs(value) < Double(Int.max) / 100 else { throw error }
                weight = unit.tenthsPounds(from: value)
            }
            let reps = Int(fields[5])
            let distance = Double(fields[6])
            guard fields[5].isEmpty || (reps ?? -1) >= 0,
                  fields[6].isEmpty || (distance?.isFinite == true && (distance ?? -1) >= 0 && !fields[7].isEmpty)
            else { throw error }
            var seconds: Int?
            if !fields[8].isEmpty {
                let parts = fields[8].split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 3, let hours = Int(parts[0]), (0...Int.max / 3600 - 1).contains(hours),
                      let minutes = Int(parts[1]), (0..<60).contains(minutes),
                      let remainder = Int(parts[2]), (0..<60).contains(remainder) else { throw error }
                seconds = hours * 3600 + minutes * 60 + remainder
            }
            // Equal rows often represent successive sets. Their occurrence distinguishes them
            // while keeping keys stable across overlapping exports.
            let encoded = try JSONEncoder().encode(fields)
            let digest = Data(SHA256.hash(data: encoded)).base64EncodedString()
            let occurrence = occurrences[digest, default: 0] + 1
            occurrences[digest] = occurrence
            return FitNotesSet(key: "\(digest).\(occurrence)", day: fields[0], name: fields[1],
                               category: fields[2], weight: weight, reps: reps, distance: distance,
                               distanceUnit: fields[7], seconds: seconds, comment: fields[9])
        }
    }

    @MainActor
    static func save(_ rows: [FitNotesSet], matches: [String: Exercise], in context: ModelContext) throws -> Int {
        var known = Set(try context.fetch(FetchDescriptor<ImportedSet>()).map(\.sourceKey))
        var added = 0
        try context.transaction {
            for (index, row) in rows.enumerated() where known.insert(row.key).inserted {
                guard let exercise = matches[row.name] else { throw FitNotesError("Confirm each exercise before importing.") }
                exercise.assignSyncID()
                let set = ImportedSet()
                set.sourceKey = row.key
                set.trainingDay = row.day
                set.sourceExercise = row.name
                set.sourceCategory = row.category
                set.exerciseKey = exercise.syncKey!
                set.exerciseName = exercise.exerciseName
                set.muscle = exercise.primaryMuscleFocus.rawValue
                set.weightTenthsPounds = row.weight
                set.reps = row.reps
                set.distance = row.distance
                set.distanceUnit = row.distanceUnit
                set.durationSeconds = row.seconds
                set.comment = row.comment
                set.sourceOrder = index
                context.insert(set)
                added += 1
            }
        }
        return added
    }
}
