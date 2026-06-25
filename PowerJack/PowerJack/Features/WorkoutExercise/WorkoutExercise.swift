//
//  Lift.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import Foundation
import SwiftData

@Model
final class WorkoutExercise {
    var exercise: String
    var order: Int
    var status: Status
    var locked: Bool
    
    init(
        exercise: String,
        order: Int,
        status: Status = .planned,
        locked: Bool = false
    ){
        self.exercise = exercise
        self.order = order
        self.status = status
        self.locked = locked
    }
}
