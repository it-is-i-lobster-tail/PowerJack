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

extension TimeInterval {
    /// Elapsed time, e.g. "2:15", or "1:02:15" once it passes an hour.
    var elapsedText: String {
        let duration = Duration.seconds(Int(self))
        return self < 3600 ? duration.minuteSecondText : duration.formatted(.time(pattern: .hourMinuteSecond))
    }
}
