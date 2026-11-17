//
//  SharedHelperTests.swift
//  PowerJackTests
//
//  Small helpers several features lean on: day arithmetic, weight units, the Live Activity's own copy
//  of the weight text, folding synced rows, reordering, and which feedback questions an exercise asks.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct SharedHelperTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    // MARK: Days

    @Test("A day is 24 hours, forward and back")
    func days() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(start.adding(days: 14).timeIntervalSince(start) == 14 * 86_400)
        #expect(start.adding(days: -3) == start.addingTimeInterval(-3 * 86_400))
        #expect(start.adding(days: 2).addingTimeInterval(43_200).days(since: start) == 2.5)
        #expect(start.days(since: start.adding(days: 1)) == -1)
    }

    // MARK: Weight units

    @Test("Weights round-trip through tenths of a pound", arguments: WeightUnit.allCases)
    func weightRoundTrip(unit: WeightUnit) {
        for tenths in [0, 25, 450, 1355, 2250, 4536, 10_000] {
            #expect(unit.tenthsPounds(from: unit.value(fromTenthsPounds: tenths)) == tenths, "\(tenths) in \(unit.symbol)")
        }
    }

    @Test("The kilogram conversions match the kilograms unit")
    func kilogramConversions() {
        let kilograms: WeightUnit = .kilograms
        for tenths in [5, 1355, 2250, 9_999] {
            #expect(WeightUnit.kilograms(fromTenthsPounds: tenths) == kilograms.value(fromTenthsPounds: tenths))
        }
        #expect(WeightUnit.tenthsPounds(fromKilograms: 100) == 2205)
        // Sets store tenths of a pound, so a round trip lands within one tenth of a pound.
        #expect(abs(WeightUnit.kilograms(fromTenthsPounds: 2205) - 100) < WeightUnit.kilogramsPerPound / 10)
    }

    @Test("Weights show at most one decimal and never a thousands separator")
    func weightFormat() {
        #expect(WeightUnit.pounds.format(tenthsPounds: 2250) == "225")
        #expect(WeightUnit.pounds.format(tenthsPounds: 1355) == "135.5")
        #expect(WeightUnit.pounds.format(tenthsPounds: 10_000) == "1000")
        #expect(WeightUnit.kilograms.format(tenthsPounds: 2260) == "102.5")
    }

    @Test("The Live Activity writes weights as the app does", arguments: [false, true])
    func liveActivityWeightMatchesApp(inKilograms: Bool) {
        let unit: WeightUnit = inKilograms ? .kilograms : .pounds
        for tenths in [25, 450, 1355, 2250, 2260, 4535, 10_000] {
            #expect(ActivitySet.weight(tenthsPounds: tenths, inKilograms: inKilograms) == unit.format(tenthsPounds: tenths), "\(tenths)")
        }
        #expect(ActivitySet.weight(tenthsPounds: 0, inKilograms: inKilograms) == "BW")
    }

    @Test("The Live Activity adds the unit only to a weight it shows")
    func liveActivityWeightWithUnit() {
        var set = ActivitySet(label: "1", progress: .current, reps: 5, weightTenthsPounds: 2250, usesKilograms: false)
        #expect(set.weightWithUnit(repsOnly: false) == "225 lb")
        #expect(set.weightWithUnit(repsOnly: true) == "BW")
        set.weightTenthsPounds = 0
        #expect(set.weightWithUnit(repsOnly: false) == "BW")
        set.weightTenthsPounds = nil
        #expect(set.weightWithUnit(repsOnly: false) == "–")

        set = ActivitySet(label: "1", progress: .current, reps: 5, weightTenthsPounds: 2260, usesKilograms: true)
        #expect(set.weightWithUnit(repsOnly: false) == "102.5 kg")
    }

    // MARK: Folding synced rows

    private final class Row {
        let key: Int?
        var merged: [ObjectIdentifier] = []
        init(_ key: Int?) { self.key = key }
    }

    @Test("Folding merges each row into its first match and moves the rest over")
    func syncFold() {
        let one = Row(1), two = Row(2), oneAgain = Row(1)
        let otherOne = Row(1), three = Row(3), noKey = Row(nil)
        var moved: [ObjectIdentifier] = []

        SyncMerge.fold(
            [otherOne, three, noKey],
            into: [one, two, oneAgain],
            key: { $0.key.map(AnyHashable.init) },
            merge: { mine, theirs in mine.merged.append(ObjectIdentifier(theirs)) },
            move: { moved.append(ObjectIdentifier($0)) }
        )

        #expect(one.merged == [ObjectIdentifier(otherOne)])
        #expect(two.merged.isEmpty)
        #expect(oneAgain.merged.isEmpty)
        #expect(moved == [ObjectIdentifier(three), ObjectIdentifier(noKey)])
    }

    // MARK: Reordering

    private final class Item: OrderedModel {
        var order: Int
        let name: String
        init(_ name: String, order: Int) {
            self.name = name
            self.order = order
        }
    }

    @Test("Moving an item renumbers every order from 0, and a bad move changes nothing")
    func moveAndReorder() {
        var items = [Item("A", order: 5), Item("B", order: 9), Item("C", order: 1), Item("D", order: 0)]

        items.moveAndReorder(from: [3], to: 0)
        #expect(items.map(\.name) == ["D", "A", "B", "C"])
        #expect(items.map(\.order) == [0, 1, 2, 3])

        items.moveAndReorder(from: [7], to: 0)
        items.moveAndReorder(from: [0], to: 9)
        #expect(items.map(\.name) == ["D", "A", "B", "C"])
    }

    // MARK: Feedback questions

    @Test("An exercise outside a program asks for effort, and one in a program for reps left")
    func feedbackQuestions() throws {
        let loose = WorkoutExercise(exercise: makeExercise(), order: 0)
        container.mainContext.insert(loose)
        #expect(!FeedbackDraft(for: loose).ratesRepsInReserve)
        #expect(!FeedbackDraft(for: loose).asksTopSet)

        let program = try makeProgram()
        let inProgram = try #require(program.programWeeks.first?.workouts.first?.workoutExercises.first)
        #expect(FeedbackDraft(for: inProgram).ratesRepsInReserve)
    }

    @Test("Feedback asks for the top set once back sets were logged before it was rated")
    func feedbackAsksTopSet() throws {
        let program = try makeProgram()
        program.start()
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let workoutExercise = try #require(workout.workoutExercises.first)
        workoutExercise.powerJackTopSetsValue = 1
        #expect(!FeedbackDraft(for: workoutExercise).asksTopSet)

        let backSet = try #require(workoutExercise.workingSets.last)
        workoutExercise.completeSet(backSet)
        #expect(FeedbackDraft(for: workoutExercise).asksTopSet)
    }

    // MARK: Helpers

    private func makeExercise() -> Exercise {
        let exercise = Exercise(exerciseName: "Bench", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)
        container.mainContext.insert(exercise)
        return exercise
    }

    private func makeProgram() throws -> Program {
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        template.addTemplateWorkout().addTemplateExercise(exercise: makeExercise())
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        return program
    }
}
