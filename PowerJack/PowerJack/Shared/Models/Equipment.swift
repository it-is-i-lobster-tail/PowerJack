//
//  Equipment.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import Foundation

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell
    case dumbbell
    case bodyweight
    case cable
    case machine
    case kettlebell
    case legPress
    
    var id: Self { self }
}
