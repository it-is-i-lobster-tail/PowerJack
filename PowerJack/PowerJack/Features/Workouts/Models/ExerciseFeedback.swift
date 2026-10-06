//
//  ExerciseFeedback.swift
//  PowerJack
//
//  Created by trogdor on 7/15/26.
//

import SwiftData

enum LevelOfEffort: Int, Codable, CaseIterable, Identifiable, ScaleSelectorOption {
    case none = 0
    case veryEasy = 1
    case easy = 2
    case challenge = 3
    case veryHard = 4
    case brutal = 5

    var id: Self { self }

    var label: String {
        switch self {
        case .none: "None"
        case .veryEasy: "Very Easy"
        case .easy: "Easy"
        case .challenge: "Challenge"
        case .veryHard: "Very Hard"
        case .brutal: "Brutal"
        }
    }
}

enum LevelOfPain: Int, Codable, CaseIterable, Identifiable, ScaleSelectorOption {
    case none = 0
    case mild = 1
    case noticeable = 2
    case moderate = 3
    case severe = 4
    case extreme = 5

    var id: Self { self }

    var label: String {
        switch self {
        case .none: "None"
        case .mild: "Mild"
        case .noticeable: "Noticeable"
        case .moderate: "Moderate"
        case .severe: "Severe"
        case .extreme: "Extreme"
        }
    }
}

@Model
final class ExerciseFeedback {
    private var levelOfEffortValue: LevelOfEffort = LevelOfEffort.none
    private var levelOfPainValue: LevelOfPain = LevelOfPain.none
    var workoutExerciseValue: WorkoutExercise?

    init(levelOfEffort: LevelOfEffort, levelOfPain: LevelOfPain) {
        self.levelOfEffortValue = levelOfEffort
        self.levelOfPainValue = levelOfPain
    }
}

//
// Public
//
extension ExerciseFeedback {
    // Level of Effort
    var levelOfEffort: LevelOfEffort {
        get { levelOfEffortValue }
        set {
            levelOfEffortValue = newValue
        }
    }
    // Level of Pain
    var levelOfPain: LevelOfPain {
        get { levelOfPainValue }
        set {
            levelOfPainValue = newValue
        }
    }
}
