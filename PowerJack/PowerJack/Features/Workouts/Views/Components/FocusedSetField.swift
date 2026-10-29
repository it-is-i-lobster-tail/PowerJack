//
//  FocusedSetField.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import Foundation

enum FocusedSetField: Hashable {
    case reps(WorkoutSet.ID)
    case weight(WorkoutSet.ID)

    /// The set whose field has focus.
    var setID: WorkoutSet.ID {
        switch self {
        case .reps(let id), .weight(let id): id
        }
    }
}
