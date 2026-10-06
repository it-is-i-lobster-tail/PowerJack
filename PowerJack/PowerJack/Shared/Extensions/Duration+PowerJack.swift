//
//  Duration+PowerJack.swift
//  PowerJack
//

import Foundation

extension Duration {
    /// Minutes and seconds, e.g. "2:15".
    var minuteSecondText: String {
        formatted(.time(pattern: .minuteSecond))
    }

    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
