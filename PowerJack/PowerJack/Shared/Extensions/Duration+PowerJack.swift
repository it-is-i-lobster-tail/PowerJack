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

extension Date {
    /// Training rules count days as 24 hours, whatever the calendar does around them.
    static let secondsPerDay: TimeInterval = 86_400

    /// This date moved by `days` 24-hour days. Negative goes back.
    func adding(days: Int) -> Date {
        addingTimeInterval(Double(days) * Self.secondsPerDay)
    }

    /// 24-hour days from `date` to this date, with the part of a day left over.
    func days(since date: Date) -> Double {
        timeIntervalSince(date) / Self.secondsPerDay
    }
}

extension TimeInterval {
    /// Elapsed time, e.g. "2:15", or "1:02:15" once it passes an hour.
    var elapsedText: String {
        let duration = Duration.seconds(Int(self))
        return self < 3600 ? duration.minuteSecondText : duration.formatted(.time(pattern: .hourMinuteSecond))
    }
}
