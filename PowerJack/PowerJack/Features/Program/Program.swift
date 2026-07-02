//
//  Program.swift
//  PowerJack
//
//  Created by Brendon on 6/28/26.
//

import Foundation
import SwiftData

@Model
final class Program {
    var programLengthWeeksValue: Int
    var status: Status
    var templateProgram: TemplateProgram
    var programWeeks: [ProgramWeek]
    
    private static var programWeekValueMin = 4
    private static var programWeekValueMax = 12
    

    
    init(programLengthWeeks: Int, status: Status, templateProgram: TemplateProgram, programWeeks: [ProgramWeek]) {
        self.programLengthWeeksValue = programLengthWeeks
        self.status = status
        self.templateProgram = templateProgram
        self.programWeeks = programWeeks
    }
}

//
// Public Accessors
//
extension Program {
    var programLengthWeeks: Int {
        get {
            programLengthWeeksValue
        }
        set {
            programLengthWeeksValue = newValue
            // programLengthWeeksValue = min(max(newValue, Self.programWeekValueMin), Self.programWeekValueMax)
        }
    }
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
    
    // NOTE: Finished != Complete. This means the user will not perform this workout. It is in the past.
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
