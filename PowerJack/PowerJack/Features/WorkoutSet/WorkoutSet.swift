//
//  Item.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var order: Int
    var reps: Int
    var weightTenthsPounds: Int
    var status: Status
    var locked: Bool

    init(
        order: Int,
        reps: Int,
        weightTenthsPounds: Int,
        status: Status = .planned,
        locked: Bool = false
    ) {
        self.order = order
        self.reps = reps
        self.weightTenthsPounds = weightTenthsPounds
        self.status = status
        self.locked = locked
    }
    
    var weightInPounds: Double {
        return Double(self.weightTenthsPounds) / 10.0
    }

}
