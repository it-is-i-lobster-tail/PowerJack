//
//  status.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import Foundation

enum Status: String, Codable, CaseIterable, Identifiable {
    case planned
    case active
    case complete
    case skipped
    case stopped
    
    var id: Self { self }
}
