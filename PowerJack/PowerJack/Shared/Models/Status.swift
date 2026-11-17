//
//  Status.swift
//  PowerJack
//
//  Created on 6/24/26.
//

import Foundation

enum Status: String, Codable, CaseIterable, Identifiable {
    case planned
    case active
    case complete
    case skipped
    case stopped

    var id: Self { self }

    /// Planned or in progress: it hasn't ended yet.
    var isOpen: Bool { self == .planned || self == .active }
    /// Complete, skipped, or stopped.
    var isFinished: Bool { !isOpen }
}
