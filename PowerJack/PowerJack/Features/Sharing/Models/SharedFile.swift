//
//  SharedFile.swift
//  PowerJack
//
//  A template or an exercise sent to another lifter as a .powerjack file.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist, so opening a .powerjack file launches PowerJack.
    nonisolated static let powerJackShare = UTType(exportedAs: "com.stanleycloud.powerjack.share")
}

/// What a .powerjack file holds: one template with every exercise it uses, or one exercise.
nonisolated struct SharedFile: Codable, Equatable, Sendable {
    /// Raised when the format changes in a way older versions can't read.
    static let currentVersion = 1

    var version = SharedFile.currentVersion
    var template: SharedTemplate?
    var exercises: [SharedExercise]
}

nonisolated struct SharedTemplate: Codable, Equatable, Sendable {
    var name: String
    var type: String
    var workoutsPerWeek: Int
    var muscleFocus: [String]
    /// Each day's exercises in order.
    var days: [[SharedTemplateRow]]
}

nonisolated struct SharedTemplateRow: Codable, Equatable, Sendable {
    /// Index into `SharedFile.exercises`.
    var exercise: Int
    /// Rows sharing an ID are one superset.
    var supersetID: UUID?
}

/// Enum values are stored as their raw strings, so this file can be decoded off the main actor;
/// `SharedImport` turns them back into values and rejects ones this version doesn't know.
nonisolated struct SharedExercise: Codable, Equatable, Sendable {
    /// Set for a built-in. The receiving phone uses its own copy and its own settings.
    var catalogID: String?
    var name: String
    var equipment: String
    var customEquipmentName: String?
    var primaryMuscle: String
    var secondaryMuscles: [String]
    var minReps: Int
    var maxReps: Int
    var fatigueLevel: String
    var customRestTime: Int?
    /// The first built-in this one moves like, as a `MovesLike` key, for versions that knew one.
    var movesLike: String?
    /// Every built-in it moves like, in order. Nil in files from versions that knew one.
    var movesLikeAll: [String]?

    /// The picks, read from either field.
    var movesLikeKeys: [String] { movesLikeAll ?? movesLike.map { [$0] } ?? [] }
}

enum SharedFileError: LocalizedError, Equatable {
    case unreadable
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .unreadable: "This file isn't a PowerJack template or exercise."
        case .newerVersion: "This file was shared from a newer version of PowerJack. Update the app, then open it again."
        }
    }
}

//
// Making a file
//
extension SharedFile {
    init(template: TemplateProgram) {
        var exercises: [SharedExercise] = []
        var indexes: [ObjectIdentifier: Int] = [:]
        var days: [[SharedTemplateRow]] = []
        for workout in template.templateWorkouts {
            var rows: [SharedTemplateRow] = []
            for row in workout.templateExercises {
                guard let exercise = row.exercise else { continue }
                let key = ObjectIdentifier(exercise)
                if indexes[key] == nil {
                    indexes[key] = exercises.count
                    exercises.append(SharedExercise(exercise))
                }
                rows.append(SharedTemplateRow(exercise: indexes[key]!, supersetID: row.supersetID))
            }
            days.append(rows)
        }
        self.template = SharedTemplate(
            name: template.templateName,
            type: template.templateType.rawValue,
            workoutsPerWeek: template.workoutsPerWeek,
            muscleFocus: template.templateMuscleFocus.map(\.rawValue),
            days: days
        )
        self.exercises = exercises
    }

    init(exercise: Exercise) {
        template = nil
        exercises = [SharedExercise(exercise)]
    }

    var name: String { template?.name ?? exercises.first?.name ?? "PowerJack" }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SharedFile {
        // Read the version first, so a newer file says so instead of failing to decode.
        struct Version: Decodable { var version: Int }
        guard let version = try? JSONDecoder().decode(Version.self, from: data).version else {
            throw SharedFileError.unreadable
        }
        guard version <= currentVersion else { throw SharedFileError.newerVersion }
        guard let file = try? JSONDecoder().decode(SharedFile.self, from: data) else {
            throw SharedFileError.unreadable
        }
        return file
    }

    /// What the share sheet sends.
    func item() throws -> SharedFileItem {
        SharedFileItem(name: name, data: try encoded())
    }
}

extension SharedExercise {
    init(_ exercise: Exercise) {
        catalogID = exercise.catalogID
        name = exercise.exerciseName
        equipment = exercise.equipment.rawValue
        customEquipmentName = exercise.customEquipmentName
        primaryMuscle = exercise.primaryMuscleFocus.rawValue
        secondaryMuscles = exercise.secondaryMuscles.map(\.rawValue)
        minReps = exercise.minReps
        maxReps = exercise.maxReps
        fatigueLevel = exercise.fatigueLevel.rawValue
        customRestTime = exercise.customRestTime
        let keys = exercise.catalogID == nil ? MovesLike.keys(of: exercise) : []
        movesLike = keys.first
        movesLikeAll = keys.count > 1 ? keys : nil
    }
}

/// A shared file, written out only when the lifter picks where to send it.
nonisolated struct SharedFileItem: Transferable, Sendable {
    let name: String
    let data: Data

    /// The template or exercise name, made safe to use as a file name.
    var fileName: String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cleaned.isEmpty ? "PowerJack" : cleaned).powerjack"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .powerJackShare) { item in
            // Its own folder, so two shares of the same name never collide.
            let folder = URL.temporaryDirectory.appending(path: "Shared-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: item.fileName)
            try item.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
