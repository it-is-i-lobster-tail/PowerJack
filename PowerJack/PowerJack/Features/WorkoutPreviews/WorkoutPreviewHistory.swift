import Foundation
import SwiftData

struct WorkoutPreviewHistory {
    static let benchKey = "catalog:\(StrengthLifts.benchID)"

    struct Session {
        let ended: Date
        /// Includes skipped working sets so a missed set never looks like an increase in the prescription.
        let rows: [HistoryRow]
        let logged: [HistoryRow]

        func matching(_ lift: WorkoutPreview.Lift, in rows: [HistoryRow]) -> [HistoryRow] {
            guard let key = lift.key else { return [] }
            return rows.filter { $0.exerciseKey == key && $0.equipment == lift.equipment.displayName }
        }
    }

    private(set) var starts: [Date] = []
    private(set) var sessions: [Session] = []
    private(set) var precludesFirstProgram = false

    init(programs: [Program], in context: ModelContext, now: Date) throws {
        let livePrograms = programs.filter { !$0.isFromSnapshot }
        let liveProgramIDs = Set(livePrograms.compactMap(\.syncID))
        for program in livePrograms {
            let rows = HistoryExport.rows(for: program)
            if rows.isEmpty, program.status == .complete { precludesFirstProgram = true }
            include(rows, now: now)
        }
        let archived = try HistoryArchive.records(in: context).filter { record in
            record.programID.map { !liveProgramIDs.contains($0) } ?? true
        }
        for records in Dictionary(grouping: archived, by: { $0.programID ?? $0.batchID }).values {
            include(records.map(\.row), now: now)
        }
        sessions.sort { $0.ended < $1.ended }
    }

    init(rows: [HistoryRow], now: Date) {
        for program in Dictionary(grouping: rows, by: \.programID).values {
            include(program, now: now)
        }
        sessions.sort { $0.ended < $1.ended }
    }

    static func wasLogged(_ row: HistoryRow, by date: Date) -> Bool {
        guard row.setType == "Top" || row.setType == "Working",
              row.setStatus == Status.complete.rawValue.capitalized,
              let logged = row.setLogged, logged <= date,
              let reps = row.reps, reps > 0 else { return false }
        let timed = row.setStarted.map { $0 <= logged } ?? false
        let beforeEnd = row.workoutEnded.map { logged < $0 && $0 <= date } ?? false
        return timed || beforeEnd
    }

    private mutating func include(_ rows: [HistoryRow], now: Date) {
        struct Day: Hashable {
            let week: Int
            let day: Int
            let start: Date?
            let end: Date?
        }
        let days = Dictionary(grouping: rows) { Day(week: $0.week, day: $0.day, start: $0.workoutStarted, end: $0.workoutEnded) }
        let complete = Status.complete.rawValue.capitalized
        if let first = rows.first, [.completed, .deleted].contains(first.programStatus) {
            // Older archives can lack session dates or whole days. Only claim a first finish
            // when a previous ended program is demonstrably incomplete. A future archive
            // cannot affect a historical replay.
            let knownEnds = days.keys.compactMap(\.end)
            let endedInTime = knownEnds.isEmpty || knownEnds.allSatisfy { $0 <= now }
            let incomplete = rows.contains { row in
                [Status.skipped, .stopped, .planned, .active].contains { $0.rawValue.capitalized == row.workoutStatus }
            }
            if endedInTime && !incomplete { precludesFirstProgram = true }
        }
        for (day, sets) in days {
            let working = sets.filter { $0.setType == "Top" || $0.setType == "Working" }
            let logged = working.filter { Self.wasLogged($0, by: now) }
            guard let end = day.end, end <= now else { continue }
            if let start = day.start, logged.contains(where: { row in
                row.setLogged.map { start <= $0 && $0 < end } == true
            }) { starts.append(start) }
            if !working.isEmpty, sets.first?.workoutStatus == complete {
                sessions.append(Session(ended: end, rows: working, logged: logged))
            }
        }
    }

    func previousSets(for lift: WorkoutPreview.Lift, before date: Date) -> [HistoryRow] {
        for session in sessions.reversed() where session.ended <= date {
            let matching = session.matching(lift, in: session.rows)
            let slots = Dictionary(grouping: matching, by: \.exerciseNumber)
            let order = slots.keys.sorted()
            if order.indices.contains(lift.occurrence), let previous = slots[order[lift.occurrence]] {
                return previous.sorted { $0.setNumber < $1.setNumber }
            }
        }
        return []
    }

    /// Compare the same lift on the same curve, independent of whether an older set has a rating.
    static func estimate(curve: StrengthCurve, reps: Int?, weight: Int?) -> Double? {
        guard let reps, (1...10).contains(reps), let weight, weight > 0 else { return nil }
        return Double(weight) / curve.share(repsToFailure: reps)
    }
}
