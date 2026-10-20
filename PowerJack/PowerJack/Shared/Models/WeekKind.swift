//
//  WeekKind.swift
//  PowerJack
//
//  What a program week is for in its training block.
//

import Foundation

enum WeekKind: String, Codable {
    /// A normal training week.
    case build
    /// A lighter week that sheds fatigue at the end of a block.
    case deload
    /// A lighter week after a long break.
    case `return`
}
