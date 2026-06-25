//
//  Workout.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import Foundation
import SwiftData

@Model
final class Workout {
    var order: Int
    var status: Status
    
    init(
        order: Int,
        status: Status = .active
    ){
        self.order = order
        self.status = status
    }
}
