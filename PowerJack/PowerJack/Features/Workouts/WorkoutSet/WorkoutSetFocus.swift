//
//  Untitled.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import Foundation

enum FocusedSetField: Hashable {
    case reps(WorkoutSet.ID)
    case weight(WorkoutSet.ID)
}
