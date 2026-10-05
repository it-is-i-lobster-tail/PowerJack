//
//  SetType.swift
//  PowerJack
//
//  Warmup sets are logged but never count toward progression.
//

import Foundation

enum SetType: String, Codable, CaseIterable, Identifiable {
    case warmup
    case working

    var id: Self { self }
}
