//
//  Logger+PowerJack.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import OSLog

extension Logger {
    private static let subsystem = "PowerJack"

    static let workout = Logger(subsystem: subsystem, category: "Workout")
    static let workoutExercise = Logger(subsystem: subsystem, category: "WorkoutExercise")
    static let workoutSet = Logger(subsystem: subsystem, category: "WorkoutSet")
    static let program = Logger(subsystem: subsystem, category: "Program")
    static let programWeek = Logger(subsystem: subsystem, category: "ProgramWeek")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let restTimer = Logger(subsystem: subsystem, category: "RestTimer")
}
