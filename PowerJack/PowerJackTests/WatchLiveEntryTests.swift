//
//  WatchLiveEntryTests.swift
//  PowerJackTests
//
//  Weight and reps entered on a set still to do show on the other device before it's logged.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WatchLiveEntryTests {
    private let t0 = Date.now.addingTimeInterval(-3600)

    @Test("Reps dialed in on the watch show on the iPhone before the set is logged")
    func watchRepsReachIPhone() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        let phoneSet = try devices.onPhone(watchSet)
        let plannedWeight = phoneSet.weightTenthsPounds

        var entry = SetEntry(for: watchSet, unit: .pounds)
        entry.reps = 7
        devices.onWatch { $0.enter(entry, on: watchSet, of: watchExercise) }
        #expect(watchSet.reps == 7)

        #expect(try devices.sendChanges())

        #expect(phoneSet.reps == 7)
        #expect(phoneSet.status == .active)
        // Only what was changed is entered: the weight still shows its target.
        #expect(phoneSet.weightTenthsPounds == plannedWeight)
        #expect(devices.replica.pending.isEmpty)
    }

    @Test("Weight dialed in on the watch carries to the later sets on the iPhone, as typing it there does")
    func watchWeightCarries() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        try #require(!watchExercise.isTopSet(watchSet))
        let laterSet = try #require(watchExercise.workingSets.dropFirst().first)
        let phoneLaterSet = try devices.onPhone(laterSet)
        // The later set still holds what the first one did, so the new weight carries to it.
        try #require(phoneLaterSet.weightTenthsPounds == watchSet.weightTenthsPounds)
        let dialed = watchSet.upcomingWeightTenthsPounds == 950 ? 1050 : 950

        var entry = SetEntry(for: watchSet, unit: .pounds)
        entry.weight = Double(dialed) / 10
        devices.onWatch { $0.enter(entry, on: watchSet, of: watchExercise) }
        try devices.sendChanges()

        #expect(try devices.onPhone(watchSet).weightTenthsPounds == dialed)
        #expect(phoneLaterSet.weightTenthsPounds == dialed)
        #expect(laterSet.weightTenthsPounds == dialed)
    }

    @Test("Turning the Digital Crown keeps one waiting change for the set, holding the latest values")
    func dialingCoalesces() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        var entry = SetEntry(for: watchSet, unit: .pounds)
        devices.onWatch(together: false) { actions in
            for reps in [9, 8, 5] {
                entry.reps = reps
                actions.enter(entry, on: watchSet, of: watchExercise)
            }
            entry.weight = 60
            actions.enter(entry, on: watchSet, of: watchExercise)
        }

        #expect(devices.replica.pending.count == 1)
        #expect(devices.replica.pending.first?.action == .enterSet(weightTenthsPounds: 600, reps: 5))

        try devices.sendChanges()
        let phoneSet = try devices.onPhone(watchSet)
        #expect(phoneSet.reps == 5)
        #expect(phoneSet.weightTenthsPounds == 600)
    }

    @Test("A set the iPhone already logged keeps its log when the watch's dialed values arrive")
    func loggedSetIgnoresEntry() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        let phoneSet = try devices.onPhone(watchSet)
        phoneSet.reps = 10
        phoneSet.weightTenthsPounds = 1000
        phoneSet.workoutExerciseValue?.completeSet(phoneSet, at: t0)
        try devices.phoneContext.save()

        var entry = SetEntry(for: watchSet, unit: .pounds)
        entry.reps = 6
        devices.onWatch(together: false) { $0.enter(entry, on: watchSet, of: watchExercise) }
        try devices.sendChanges()

        #expect(phoneSet.status == .complete)
        #expect(phoneSet.reps == 10)
        // The watch takes the iPhone's log.
        #expect(watchSet.status == .complete)
        #expect(watchSet.reps == 10)
    }

    @Test("Reps typed on the iPhone reach the watch, whose dial then starts from them")
    func phoneRepsReachWatch() throws {
        let (devices, watchSet, _) = try startedOnWatch()
        let dialed = SetEntry(for: watchSet, unit: .pounds)
        let typed = dialed.reps == 7 ? 6 : 7
        let phoneSet = try devices.onPhone(watchSet)
        phoneSet.reps = typed
        try devices.phoneContext.save()

        #expect(try devices.sendProgram())

        #expect(watchSet.reps == typed)
        #expect(!dialed.matches(watchSet, repsOnly: false))
        #expect(SetEntry(for: watchSet, unit: .pounds).reps == typed)
    }

    @Test("Values the dial already shows aren't entered again")
    func unchangedEntryRecordsNothing() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        let entry = SetEntry(for: watchSet, unit: .pounds)
        devices.onWatch { $0.enter(entry, on: watchSet, of: watchExercise) }
        #expect(devices.replica.pending.isEmpty)
    }

    // MARK: Helpers

    /// A workout started on the watch and on the iPhone, and its first working set on the watch.
    private func startedOnWatch() throws -> (TwoDevices, WorkoutSet, WorkoutExercise) {
        let devices = try TwoDevices()
        try devices.sendProgram()
        let watchProgram = try devices.watchProgram
        let workout = try #require(watchProgram.nextWorkout)
        devices.onWatch { $0.start(workout, in: watchProgram, at: t0.addingTimeInterval(-60)) }
        try devices.sendChanges()
        let workoutExercise = try #require(workout.workoutExercises.first { $0.exercise?.repsOnly == false })
        if workoutExercise.checkInPending {
            devices.onWatch { $0.resolveCheckIn(of: workoutExercise, with: .continue) }
            try devices.sendChanges()
        }
        return (devices, try #require(workoutExercise.workingSets.first), workoutExercise)
    }
}
