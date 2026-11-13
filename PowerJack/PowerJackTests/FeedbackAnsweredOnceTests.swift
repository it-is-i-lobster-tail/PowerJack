//
//  FeedbackAnsweredOnceTests.swift
//  PowerJackTests
//
//  Feedback and check-ins answered on one device are never asked again on the other. Both devices
//  ask once an exercise's last set is logged, so the first answer stands and closes the other's question.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct FeedbackAnsweredOnceTests {
    private let t0 = Date.now.addingTimeInterval(-3600)

    @Test("Feedback answered on the watch reaches the iPhone, which stops asking for it")
    func watchAnswerStopsIPhoneAsking() throws {
        let (devices, watchExercise, phoneExercise) = try lastSetLoggedOnWatch()
        // The watch's last set reached the iPhone first, so both devices are asking now.
        #expect(watchExercise.needsFeedback)
        #expect(phoneExercise.needsFeedback)

        devices.onWatch { $0.rate(watchExercise, feedback: feedback(pain: .mild, for: watchExercise), topSet: topSet(for: watchExercise)) }
        try devices.sendChanges()

        #expect(!phoneExercise.needsFeedback)
        #expect(phoneExercise.isDone)
        #expect(phoneExercise.feedback?.levelOfPain == .mild)
        #expect(!watchExercise.needsFeedback)
        #expect(devices.replica.pending.isEmpty)
    }

    @Test("Feedback answered on the iPhone first stands, and the watch stops asking once it hears")
    func phoneAnswerStopsWatchAsking() throws {
        let (devices, watchExercise, phoneExercise) = try lastSetLoggedOnWatch()

        #expect(phoneExercise.answerFeedback(feedback(pain: .moderate, for: phoneExercise), topSet: topSet(for: phoneExercise)))
        try devices.phoneContext.save()
        try devices.sendProgram()

        #expect(!watchExercise.needsFeedback)
        #expect(watchExercise.feedback?.levelOfPain == .moderate)
    }

    @Test("Both answered before they heard from each other: the iPhone keeps the answer it had first")
    func firstAnswerStands() throws {
        let (devices, watchExercise, phoneExercise) = try lastSetLoggedOnWatch()
        phoneExercise.answerFeedback(feedback(pain: .moderate, for: phoneExercise), topSet: topSet(for: phoneExercise))
        try devices.phoneContext.save()
        devices.onWatch { $0.rate(watchExercise, feedback: feedback(pain: .none, for: watchExercise), topSet: topSet(for: watchExercise)) }

        try devices.sendChanges()

        #expect(phoneExercise.feedback?.levelOfPain == .moderate)
        #expect(watchExercise.feedback?.levelOfPain == .moderate)
        // The watch's answer never left an extra feedback row behind on the iPhone.
        #expect(try devices.phoneContext.fetchCount(FetchDescriptor<ExerciseFeedback>()) == 1)
    }

    @Test("A second answer never replaces the first")
    func secondAnswerRefused() throws {
        let (_, _, phoneExercise) = try lastSetLoggedOnWatch()
        #expect(phoneExercise.answerFeedback(feedback(pain: .mild, for: phoneExercise), topSet: topSet(for: phoneExercise)))
        let topRating = phoneExercise.topSetRepsInReserve

        #expect(!phoneExercise.answerFeedback(feedback(pain: .severe, for: phoneExercise), topSet: phoneExercise.topSets > 0 ? .zero : nil))

        #expect(phoneExercise.feedback?.levelOfPain == .mild)
        #expect(phoneExercise.topSetRepsInReserve == topRating)
    }

    @Test("Feedback the iPhone already has isn't sent again from the watch")
    func watchSendsNothingOnceAnswered() throws {
        let (devices, watchExercise, phoneExercise) = try lastSetLoggedOnWatch()
        phoneExercise.answerFeedback(feedback(pain: .moderate, for: phoneExercise), topSet: topSet(for: phoneExercise))
        try devices.phoneContext.save()
        try devices.sendProgram()

        devices.onWatch { $0.rate(watchExercise, feedback: feedback(pain: .none, for: watchExercise), topSet: topSet(for: watchExercise)) }

        #expect(devices.replica.pending.isEmpty)
        #expect(watchExercise.feedback?.levelOfPain == .moderate)
    }

    // MARK: Helpers

    /// A workout started on the watch, with its first exercise's working sets all logged there and sent
    /// to the iPhone, which now holds the same exercise waiting on feedback.
    private func lastSetLoggedOnWatch() throws -> (TwoDevices, watch: WorkoutExercise, phone: WorkoutExercise) {
        let devices = try TwoDevices()
        try devices.sendProgram()
        let watchProgram = try devices.watchProgram
        let workout = try #require(watchProgram.nextWorkout)
        let workoutExercise = workout.workoutExercises[0]
        devices.onWatch { actions in
            actions.start(workout, in: watchProgram, at: t0)
            for (index, workoutSet) in workoutExercise.workingSets.enumerated() {
                var entry = SetEntry(for: workoutSet, unit: .pounds)
                if entry.weightTenthsPounds == nil { entry.weight = 100 }
                actions.log(entry, on: workoutSet, of: workoutExercise, at: t0.addingTimeInterval(Double(index + 1) * 60))
            }
        }
        try devices.sendChanges()
        let workingSet = try #require(workoutExercise.workingSets.first)
        let phoneExercise = try #require(try devices.onPhone(workingSet).workoutExerciseValue)
        return (devices, workoutExercise, phoneExercise)
    }

    private func feedback(pain: LevelOfPain, for workoutExercise: WorkoutExercise) -> ExerciseFeedback {
        workoutExercise.templateType?.ratesRepsInReserve == true
            ? ExerciseFeedback(repsInReserve: .two, levelOfPain: pain)
            : ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: pain)
    }

    private func topSet(for workoutExercise: WorkoutExercise) -> RepsInReserve? {
        workoutExercise.topSetsNeedRating ? .two : nil
    }
}
