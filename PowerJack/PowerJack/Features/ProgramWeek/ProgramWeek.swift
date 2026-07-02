//
//  ProgramWeek.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import Foundation
import SwiftData

@Model
final class ProgramWeek{
    var order: Int
    var workouts: [Workout]
    
    init(order: Int, workouts: [Workout]) {
        self.order = order
        self.workouts = workouts
    }
}
