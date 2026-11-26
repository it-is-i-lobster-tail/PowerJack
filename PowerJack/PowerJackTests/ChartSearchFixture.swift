import Foundation

@testable import PowerJack

/// A small, hand-written training log with answers that are easy to check by hand.
///
/// | Date   | Minutes | Sets                                                       |
/// |--------|---------|------------------------------------------------------------|
/// | Oct 5  | 50      | bench 3×5 @ 185, squat 3×5 @ 225                           |
/// | Oct 8  | 40      | cable curl 3×10 @ 30, push-up 2×20                         |
/// | Oct 12 | 60      | bench 3×5 @ 190, incline bench 2×8 @ 135, squat 3×5 @ 235  |
/// | Nov 2  | 45      | bench 2×5 @ 195, deadlift 1×5 @ 315                        |
/// | Nov 20 | 55      | squat 3×5 @ 245, cable curl 2×12 @ 30                      |
///
/// Today is Nov 25, 2026, in a fixed Gregorian calendar.
enum ChartSearchFixture {
    struct Lift {
        let key: String
        let name: String
        let muscle: Muscle
        let equipment: Equipment
    }

    static let bench = Lift(key: StudyHistory.bench, name: "Barbell Bench Press", muscle: .chest, equipment: .barbell)
    static let incline = Lift(key: "catalog:incline-barbell-bench-press", name: "Incline Barbell Bench Press",
                              muscle: .chest, equipment: .barbell)
    static let squat = Lift(key: StudyHistory.squat, name: "Barbell Back Squat", muscle: .quads, equipment: .barbell)
    static let deadlift = Lift(key: "catalog:barbell-deadlift", name: "Barbell Deadlift", muscle: .back, equipment: .barbell)
    static let curl = Lift(key: StudyHistory.curl, name: "Cable Curl", muscle: .biceps, equipment: .cable)
    static let pushUp = Lift(key: "catalog:push-up", name: "Push Up", muscle: .chest, equipment: .bodyweight)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 17))!
    }

    static let today = date(11, 25)

    struct Workout {
        let date: Date
        let minutes: Double
        let slots: [Slot]
    }

    struct Slot {
        let lift: Lift
        /// Each set's reps and pounds. Pounds are nil for bodyweight.
        let sets: [(reps: Int, pounds: Double?)]

        init(_ lift: Lift, _ count: Int, _ reps: Int, _ pounds: Double?) {
            self.lift = lift
            sets = Array(repeating: (reps, pounds), count: count)
        }
    }

    static let workouts: [Workout] = [
        Workout(date: date(10, 5), minutes: 50, slots: [Slot(bench, 3, 5, 185), Slot(squat, 3, 5, 225)]),
        Workout(date: date(10, 8), minutes: 40, slots: [Slot(curl, 3, 10, 30), Slot(pushUp, 2, 20, nil)]),
        Workout(date: date(10, 12), minutes: 60,
                slots: [Slot(bench, 3, 5, 190), Slot(incline, 2, 8, 135), Slot(squat, 3, 5, 235)]),
        Workout(date: date(11, 2), minutes: 45, slots: [Slot(bench, 2, 5, 195), Slot(deadlift, 1, 5, 315)]),
        Workout(date: date(11, 20), minutes: 55, slots: [Slot(squat, 3, 5, 245), Slot(curl, 2, 12, 30)]),
    ]

    static func history(unit: WeightUnit = .pounds) -> StudyHistory {
        let program = UUID()
        let batch = UUID()
        var records: [HistoryRecord] = []
        for (index, workout) in workouts.enumerated() {
            for (slot, entry) in workout.slots.enumerated() {
                let lift = entry.lift
                for (number, set) in entry.sets.enumerated() {
                    var row = HistoryRow(programID: program)
                    row.programName = "Fixture"
                    row.week = index + 1
                    row.day = 1
                    row.workoutStatus = "Complete"
                    row.workoutStarted = workout.date
                    row.workoutEnded = workout.date.addingTimeInterval(workout.minutes * 60)
                    row.workoutSeconds = workout.minutes * 60
                    row.exerciseNumber = slot + 1
                    row.exerciseKey = lift.key
                    row.exerciseName = lift.name
                    row.primaryMuscle = lift.muscle.rawValue
                    row.equipment = lift.equipment.displayName
                    row.setType = "Working"
                    row.setNumber = number + 1
                    row.setStatus = "Complete"
                    row.reps = set.reps
                    row.targetReps = set.reps
                    row.weightTenthsPounds = set.pounds.map { Int($0 * 10) }
                    records.append(HistoryRecord(row, batchID: batch, savedAt: workout.date,
                                                 programStarted: workouts[0].date, order: records.count))
                }
            }
        }
        return StudyHistory(programs: [], archive: records, logs: [], unit: unit, today: today, calendar: calendar)
    }

    static let empty = StudyHistory(programs: [], archive: [], logs: [], unit: .pounds, today: today, calendar: calendar)
}
