//
//  FocusedSetField.swift
//  PowerJack
//
//  Created on 6/29/26.
//

import Foundation

enum FocusedSetField: Hashable {
    case reps(WorkoutSet.ID)
    case weight(WorkoutSet.ID)
}
