import Foundation
import Testing

@testable import PowerJack

/// The parser reads scope from the user's words. Each case is a phrase a lifter types and what it must mean.
@MainActor
struct ChartQueryTests {
    let history = ChartSearchFixture.history()
    typealias F = ChartSearchFixture

    private func query(_ text: String) -> ChartQuery { ChartQuery(text, history: history) }

    @Test("Lift names match logged exercises, preferring the closest name")
    func lifts() {
        #expect(query("bench progress").exerciseKeys == [F.bench.key], "bench means flat bench, not incline")
        #expect(query("incline bench").exerciseKeys == [F.incline.key])
        #expect(query("Bench presses this year").exerciseKeys == [F.bench.key])
        #expect(query("squats").exerciseKeys == [F.squat.key])
        #expect(query("cable curls").exerciseKeys == [F.curl.key])
        #expect(query("push-ups").exerciseKeys == [F.pushUp.key])
        #expect(query("push ups").exerciseKeys == [F.pushUp.key])
        let pair = query("compare squat and deadlift")
        #expect(pair.lifts.map(\.exerciseKeys) == [[F.squat.key], [F.deadlift.key]])
    }

    @Test("A muscle word inside a lift name stays part of the lift")
    func anatomyInsideNames() {
        let backSquat = query("back squat volume")
        #expect(backSquat.exerciseKeys == [F.squat.key])
        #expect(backSquat.muscles.isEmpty)
        let back = query("back volume")
        #expect(back.lifts.isEmpty)
        #expect(back.muscles == [.back])
    }

    @Test("Muscle groups and their everyday names")
    func muscles() {
        #expect(query("arms").muscles == [.biceps, .triceps])
        #expect(Set(query("legs strength").muscles) == Set(StudyHistory.legs))
        #expect(query("pecs").muscles == [.chest])
        #expect(query("upper body volume").muscleGroups.map(\.name) == ["upper body"])
        #expect(query("Which muscles have I neglected?").muscles == Muscle.allCases)
    }

    @Test("Dates read anywhere in the text, relative to today")
    func dates() {
        #expect(query("upper body volume Oct").period == .month(year: 2026, month: 10))
        #expect(query("How many October sessions did I finish?").period == .month(year: 2026, month: 10))
        #expect(query("bench on Oct 12").period == .day(year: 2026, month: 10, day: 12))
        #expect(query("squat March 2025").period == .month(year: 2025, month: 3))
        #expect(query("records in 2025").period == .year(2025))
        #expect(query("this month").period == .month(year: 2026, month: 11))
        #expect(query("last month").period == .month(year: 2026, month: 10))
        #expect(query("last year").period == .year(2025))
        #expect(query("yesterday").period == .day(year: 2026, month: 11, day: 24))
        #expect(query("volume in December").period == .month(year: 2025, month: 12), "the most recent December")
        #expect(query("may I see my squats").period == nil, "may as a verb is not a month")
        #expect(query("squats in May").period == .month(year: 2026, month: 5))
        #expect(query("sets in October versus November").periods == [.month(year: 2026, month: 10), .month(year: 2026, month: 11)])
    }

    @Test("Numbers with units become chart controls")
    func parameters() {
        #expect(query("Did I hit 3x5 at 185 lb?").parameters == [.sets: 3, .reps: 5, .load: 1850])
        #expect(query("squat 100 kg").parameters[.load] == WeightUnit.kilograms.tenthsPounds(from: 100))
        #expect(query("heaviest bench for 5 reps").parameters == [.reps: 5])
        #expect(query("workouts under 50 minutes").parameters == [.minutes: 50])
    }

    @Test("Scope words leave the intent, which is what ranks the charts")
    func intent() {
        #expect(query("Is my bench press getting stronger in October?").intent == "is my getting stronger in")
        #expect(query("arms October").intent.isEmpty)
    }

    @Test("A catalog lift with no logged sets is named, and stays in scope with nothing logged")
    func unloggedLift() {
        let front = query("front squat progress")
        #expect(front.unloggedLifts == ["Barbell Front Squat"])
        #expect(front.exerciseKeys.isEmpty)
        #expect(front.hasScope)
    }

    @Test("Questions ask the model. Short filters don't.")
    func questions() {
        for filter in ["", "arms", "legs strength", "upper body volume Oct", "press"] {
            #expect(!query(filter).isQuestion, "\(filter)")
        }
        for question in ["How often do I bench?", "Compare squat and deadlift", "did my squat go up", "bench?"] {
            #expect(query(question).isQuestion, "\(question)")
        }
    }
}
