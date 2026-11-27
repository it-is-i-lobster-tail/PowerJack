//
//  ProgramListSectionsTests.swift
//  PowerJackTests
//
//  The My Programs list: current programs on top, past ones grouped by the year they started.
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct ProgramListSectionsTests {
    private struct Item: Equatable {
        let name: String
        let status: Status
        let start: Date?
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func sections(_ items: [Item]) -> ProgramListSections<Item> {
        ProgramListSections(items, status: \.status, startedAt: \.start, calendar: Self.calendar)
    }

    @Test("The active program comes first, then programs not started; past ones stay out")
    func currentGroup() {
        let result = sections([
            Item(name: "Planned", status: .planned, start: nil),
            Item(name: "Done", status: .complete, start: Self.date(2025, 3, 1)),
            Item(name: "Active", status: .active, start: Self.date(2026, 9, 1)),
        ])
        #expect(result.current.map(\.name) == ["Active", "Planned"])
        #expect(result.past.flatMap(\.items).map(\.name) == ["Done"])
    }

    @Test("Finished, stopped and skipped programs are past")
    func pastStatuses() {
        let result = sections([
            Item(name: "Finished", status: .complete, start: Self.date(2026, 1, 5)),
            Item(name: "Stopped", status: .stopped, start: Self.date(2026, 3, 5)),
            Item(name: "Skipped", status: .skipped, start: Self.date(2026, 2, 5)),
        ])
        #expect(result.current.isEmpty)
        #expect(result.past.flatMap(\.items).map(\.name) == ["Stopped", "Skipped", "Finished"])
    }

    @Test("A program belongs to the year it started, even when it ended the next year")
    func yearByStartDate() {
        let result = sections([
            Item(name: "Winter", status: .complete, start: Self.date(2024, 12, 2)),
            Item(name: "Spring", status: .complete, start: Self.date(2025, 4, 1)),
        ])
        #expect(result.past.map(\.year) == [2025, 2024])
        #expect(result.past.last?.items.map(\.name) == ["Winter"])
    }

    @Test("Years run newest first, and so do programs within a year")
    func ordering() {
        let result = sections([
            Item(name: "A", status: .complete, start: Self.date(2024, 2, 1)),
            Item(name: "B", status: .stopped, start: Self.date(2026, 1, 10)),
            Item(name: "C", status: .complete, start: Self.date(2024, 9, 1)),
            Item(name: "D", status: .complete, start: Self.date(2026, 6, 1)),
            Item(name: "E", status: .complete, start: Self.date(2025, 5, 1)),
        ])
        #expect(result.past.map(\.year) == [2026, 2025, 2024])
        #expect(result.past.map { $0.items.map(\.name) } == [["D", "B"], ["E"], ["C", "A"]])
    }

    @Test("Past programs that never started a workout go last, without a year")
    func undated() {
        let result = sections([
            Item(name: "Never trained", status: .stopped, start: nil),
            Item(name: "Done", status: .complete, start: Self.date(2024, 2, 1)),
        ])
        #expect(result.past.map(\.year) == [2024, nil])
        #expect(result.past.last?.items.map(\.name) == ["Never trained"])
    }

    // MARK: Date range

    private func range(_ start: Date, _ end: Date?) -> String {
        ProgramDateRange.text(from: start, to: end, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
    }

    @Test("A range within one year leaves the year out")
    func sameYearRange() {
        #expect(range(Self.date(2025, 3, 3), Self.date(2025, 5, 12)) == "Mar 3 – May 12")
    }

    @Test("A range that crosses a year shows the year on both sides")
    func crossYearRange() {
        #expect(range(Self.date(2025, 12, 1), Self.date(2026, 2, 9)) == "Dec 1, 2025 – Feb 9, 2026")
    }

    @Test("A single day, or no end, shows one date")
    func singleDay() {
        #expect(range(Self.date(2025, 3, 3), Self.date(2025, 3, 3).addingTimeInterval(3_600)) == "Mar 3")
        #expect(range(Self.date(2025, 3, 3), nil) == "Mar 3")
    }
}
