//
//  SyncState.swift
//  PowerJack
//
//  Plain copies of the program's rows, as the iPhone sends them straight to the watch.
//  Each row carries its sync ID, which is the same on both devices (their stores give rows
//  different IDs), so the watch updates its own copy instead of making a second one.
//

import Foundation

/// Which device did something. Stored as text, so a new kind of device never breaks old rows.
enum SyncDevice {
    static let iPhone = "iPhone"
    static let watch = "Apple Watch"

    /// The device this runs on. Tests acting as the watch set it for a moment.
    static var current: String = {
        #if os(watchOS)
        watch
        #else
        iPhone
        #endif
    }()
}

struct ProgramState: Codable, Equatable {
    var syncID: UUID
    var programLengthWeeks: Int
    var status: Status
    var locked: Bool
    var workoutsPerWeek: Int
    var templateName: String
    var templateMuscleFocus: [Muscle]
    var templateType: TemplateType
    var weeks: [WeekState]
}

struct WeekState: Codable, Equatable {
    var syncID: UUID
    var order: Int
    var status: Status
    var locked: Bool
    var weekKind: String
    var blockWeek: Int
    var returnBand: Int
    var workouts: [WorkoutState]
}

struct WorkoutState: Codable, Equatable {
    struct LayoutEntry: Codable, Equatable {
        var exerciseKey: String
        var supersetID: UUID?
    }

    var syncID: UUID
    var order: Int
    var status: Status
    var locked: Bool
    var startedAt: Date?
    var endedAt: Date?
    var createdAt: Date?
    var createdOn: String?
    var startedOn: String?
    /// The day's exercises from next week on, when it was edited after it started.
    var nextWeekLayout: [LayoutEntry]?
    var exercises: [WorkoutExerciseState]
}

struct WorkoutExerciseState: Codable, Equatable {
    var syncID: UUID
    var exerciseKey: String?
    var order: Int
    var status: Status
    var locked: Bool
    var feedback: FeedbackState?
    var checkIn: ManualCheckIn
    var checkInSourcePain: LevelOfPain?
    var warmupsDisabled: Bool
    var warmupRestoreCount: Int?
    var supersetID: UUID?
    var rirTarget: Int?
    var progressionCode: String?
    var progressionNote: String?
    var strengthRole: String?
    var targetReps: Int?
    var repOffset: Int?
    var intendedLoadKg: Double?
    var powerJackRole: String?
    var powerJackTag: String?
    var powerJackTopSets: Int
    var powerJackTopRIR: Int?
    var powerJackLoadTarget: Double?
    var powerJackTopLoadTarget: Double?
    var powerJackCalibrating: Bool
    var sets: [SetState]
}

struct FeedbackState: Codable, Equatable {
    var levelOfEffort: LevelOfEffort
    var levelOfPain: LevelOfPain
    var effortScaleVersion: Int
}

struct SetState: Codable, Equatable {
    var syncID: UUID
    var order: Int
    var setType: String
    var reps: Int?
    var repsPlanned: Int?
    var weightTenthsPounds: Int?
    var weightTenthsPoundsPlanned: Int?
    var status: Status
    var locked: Bool
    var completedAt: Date?
    var startedAt: Date?
}

struct ExerciseState: Codable, Equatable {
    var key: String
    var catalogID: String?
    var syncID: UUID?
    var name: String
    var equipment: Equipment
    var primaryMuscle: Muscle
    var secondaryMuscles: [Muscle]
    var userCreated: Bool
    var createdAt: Date
    var minReps: Int
    var maxReps: Int
    var fatigueLevel: FatigueLevel
    var customRestTime: Int?
}

struct StrengthLogState: Codable, Equatable {
    var date: Date
    var version: String
    var state: Data
    var sessionID: UUID?
}

extension Status {
    /// How far along a row is, so merging two copies of it never moves it back.
    var progress: Int {
        switch self {
        case .planned: 0
        case .active: 1
        case .complete, .skipped, .stopped: 2
        }
    }
}
