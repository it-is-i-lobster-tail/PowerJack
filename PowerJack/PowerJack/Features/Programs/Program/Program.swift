//
//  Program.swift
//  PowerJack
//
//  Created by Brendon on 6/28/26.
//

import Foundation
import SwiftData
import OSLog

@Model
final class Program {
    var programLengthWeeksValue: Int
    var statusValue: Status
    var templateProgramValue: TemplateProgram
    var programWeeksValue: [ProgramWeek]
    var lockedValue: Bool
    
    private static var programWeekValueMax = 12
    private static var initalWeekSets = 2
    
    init(programLengthWeeks: Int, templateProgram: TemplateProgram) {
        self.programLengthWeeksValue = min(1, programLengthWeeks)
        self.statusValue = .planned
        self.templateProgramValue = templateProgram
        self.programWeeksValue = []
        self.lockedValue = false
        buildInitalProgramWeeks()
        setupInitialProgramWeek()
    }
    
    private func buildInitalProgramWeeks() {
        for _ in 0...programLengthWeeksValue - 1 {
            _ = addProgramWeek()
        }
    }

    private func setupInitialProgramWeek() {
        guard let firstWeek = programWeeksValue.first else {
            Logger.program.warning("Cannot setup initial ProgramWeek because Program has no weeks.")
            return
        }
        
        for templateWorkout in templateProgramValue.templateWorkouts {
            guard let newWorkout = firstWeek.addWorkout() else {
                Logger.program.warning("Unable to add Workout to initial ProgramWeek.")
                continue
            }
            
            for templateExercise in templateWorkout.templateExercises {
                guard let newWorkoutExercise = newWorkout.addWorkoutExercise(exercise: templateExercise.exercise) else {
                    Logger.program.warning("Unable to add WorkoutExercise to an initial ProgramWeek's Workout.")
                    continue
                }
                
                for _ in 0...Self.initalWeekSets - 1 {
                    _ = newWorkoutExercise.addSet()
                }
            }
        }
    }
}

//
// Public Accessors
//
extension Program {
    // Status
    var status: Status { statusValue }
    // Program Length
    var programLengthWeeks: Int { programLengthWeeksValue }
    // Program Weeks
    var programWeeks: [ProgramWeek] { programWeeksValue.sorted { $0.order < $1.order }}
    // Template Program
    var templateProgram: TemplateProgram { templateProgramValue }
}

//
// Derived Values
//
extension Program {
    private var allWorkouts: [Workout] {
        var workouts: [Workout] = []
        for programWeek in self.programWeeks {
            for workout in programWeek.workouts {
                workouts.append(workout)
            }
        }
        return workouts
    }
    
    var totalWorkouts: Int { programLengthWeeks * templateProgram.workoutsPerWeek }
    
    // NOTE: Finished != Complete. Only count skipped or complete.
    var workoutsFinished: Int {
        var c: Int = 0
        for workout in allWorkouts {
            if workout.status == Status.complete || workout.status == Status.skipped {
                c = c + 1
            }
        }
        return c
    }
}

//
// Mutations
//
extension Program {
    func complete() {
        guard
            !lockedValue,
            status == .active
        else {
            Logger.program.warning("Cannot complete a locked Program.")
            return
        }
        statusValue = Status.complete
        lockedValue = true
        Logger.program.debug("Completed Program")
    }
    func stop() {
        guard
            !lockedValue,
            status == .planned || status == .active
        else {
            Logger.program.warning("Cannot stop a locked Program.")
            return
        }
        statusValue = Status.stopped
        lockedValue = true
        Logger.program.debug("Stopped Program")
    }
    func start() {
        guard
            lockedValue,
            status == .planned
        else {
            Logger.program.warning("Cannot start a locked Program.")
            return
        }
        statusValue = Status.active
        Logger.program.debug("Started Program")
    }
    func completeAndCascade() {
        guard status == .complete else {
            Logger.program.warning("Program status but be 'complete' before running completeAndCascade")
            return
        }
        for programWeek in programWeeksValue {
            programWeek.completeAndCascade()
        }
    }
    func stopAndCascade() {
        guard status == .stopped else {
            Logger.program.warning("Program status but be 'stopped' before running stopAndCascade")
            return
        }
        for programWeek in programWeeksValue {
            programWeek.stopAndCascade()
        }
    }
    func addProgramWeek() -> ProgramWeek? {
        guard
            !lockedValue,
            programWeeks.count <= Self.programWeekValueMax
        else {
            Logger.program.warning("Unable to add ProgramWeek. Max Weeks exceeded or Program is locked.")
            return nil
        }
        let newProgramWeek = ProgramWeek(order: programWeeksValue.count)
        programWeeksValue.append(newProgramWeek)
        Logger.program.info("New ProgramWeek added to Program")
        return newProgramWeek
    }
    func removeLastProgramWeek() -> ProgramWeek? {
        guard !lockedValue else {
            Logger.program.warning("Cannot remove last ProgramWeek of locked Program.")
            return nil
        }
        Logger.program.info("Removing last ProgramWeek from Program")
        return programWeeksValue.popLast()
    }
}
