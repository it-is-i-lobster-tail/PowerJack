//
//  SyncTidyUpTests.swift
//  PowerJackTests
//
//  The iPhone and the watch apart, syncing through iCloud: the latest log wins by when it was
//  logged, and the tidy-up folds every duplicate syncing leaves into one copy without losing a log.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct SyncTidyUpTests {
    private let morning = Date.now.addingTimeInterval(-8 * 3600)
    private var afternoon: Date { morning.addingTimeInterval(6 * 3600) }

    // MARK: Latest log wins

    @Test("A day logged on the iPhone in the morning and on the watch in the afternoon shows the afternoon")
    func afternoonWatchRunWins() throws {
        let devices = try TwoDevices()
        let workoutSet = try startedSet(in: devices)
        log(workoutSet, reps: 6, at: morning)

        // iCloud brings the watch's afternoon log of the same set.
        importLog(on: workoutSet, reps: 9, at: afternoon, from: SyncDevice.watch, in: devices.phoneContext)
        try SyncTidyUp.run(in: devices.phoneContext)

        #expect(workoutSet.reps == 9)
    }

    @Test("A watch that syncs a day late never wins over a newer iPhone log")
    func lateUploadLoses() throws {
        let devices = try TwoDevices()
        let workoutSet = try startedSet(in: devices)
        log(workoutSet, reps: 6, at: afternoon)

        // The watch logged it in the morning, but its upload only lands now and overwrites the set.
        importLog(on: workoutSet, reps: 9, at: morning, from: SyncDevice.watch, in: devices.phoneContext)
        #expect(workoutSet.reps == 9)
        try SyncTidyUp.run(in: devices.phoneContext)

        #expect(workoutSet.reps == 6)
        #expect(workoutSet.completedAt == afternoon)
        // Both runs are still on record.
        #expect(try devices.phoneContext.fetchCount(FetchDescriptor<SetReceipt>()) == 2)
    }

    @Test("A set reopened to fix it isn't logged again by the tidy-up")
    func reopenedSetStaysOpen() throws {
        let devices = try TwoDevices()
        let workoutSet = try startedSet(in: devices)
        log(workoutSet, reps: 6, at: morning)
        workoutSet.start()

        try SyncTidyUp.run(in: devices.phoneContext)

        #expect(workoutSet.status == .active)
    }

    // MARK: Snapshot copies

    @Test("The watch's copy of the program folds into the iPhone's own once iCloud brings it to the watch")
    func watchCopiesFoldIntoOriginals() throws {
        let devices = try TwoDevices()
        try devices.sendProgram()
        let copy = try devices.watchProgram
        let workout = try #require(copy.nextWorkout)
        let workoutExercise = workout.workoutExercises[0]
        let workoutSet = try #require(workoutExercise.workingSets.first)
        devices.onWatch { actions in
            actions.start(workout, in: copy, at: morning)
            var entry = SetEntry(for: workoutSet, unit: .pounds)
            entry.weight = 95
            entry.reps = 7
            actions.log(entry, on: workoutSet, of: workoutExercise, at: morning.addingTimeInterval(60))
        }
        let setID = workoutSet.syncID

        // The iPhone's own rows arrive through iCloud, from before the watch's log reached it.
        try ICloud.bring(devices.phoneProgram, into: devices.watchContext, asSnapshotCopies: false)
        try devices.onWatch { _ in try SyncTidyUp.run(in: devices.watchContext, running: devices.replica.runningOnIPhone) }

        let context = devices.watchContext
        #expect(try context.fetchCount(FetchDescriptor<Program>()) == 1)
        #expect(try context.fetch(FetchDescriptor<Program>()).allSatisfy { !$0.isFromSnapshot })
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSet>()) == devices.phoneContext.fetchCount(FetchDescriptor<WorkoutSet>()))
        #expect(try WorkoutSet.fromSnapshot(in: context).isEmpty)
        let merged = try #require(try context.fetch(FetchDescriptor<WorkoutSet>()).first { $0.syncID == setID })
        #expect(merged.status == .complete)
        #expect(merged.reps == 7)
        #expect(merged.workoutExerciseValue?.workoutValue?.status == .active)
    }

    @Test("The watch's copies that iCloud brings to the iPhone fold into its own rows, keeping the watch's logs")
    func copiesOnPhoneFold() throws {
        let devices = try TwoDevices()
        try devices.sendProgram()
        let copy = try devices.watchProgram
        let workout = try #require(copy.nextWorkout)
        devices.onWatch(together: false) { $0.train(workout, in: copy, at: morning) }
        let logged = workout.completedWorkingSets
        let setCount = try devices.phoneContext.fetchCount(FetchDescriptor<WorkoutSet>())

        try ICloud.bring(copy, into: devices.phoneContext, asSnapshotCopies: true)
        try SyncTidyUp.run(in: devices.phoneContext)

        let context = devices.phoneContext
        #expect(try context.fetchCount(FetchDescriptor<Program>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSet>()) == setCount)
        let phoneWorkout = try #require(try devices.phoneProgram.programWeeks[0].workouts.first)
        #expect(phoneWorkout.completedWorkingSets == logged)
        #expect(phoneWorkout.status == .complete)
    }

    // MARK: Duplicate days

    @Test("A day planned on both devices keeps the iPhone's copy when neither is logged")
    func duplicateDayKeepsIPhones() throws {
        let devices = try TwoDevices()
        let week = try devices.phoneProgram.programWeeks[0]
        let original = week.workouts[0]
        let count = week.workouts.count
        let duplicate = try addDuplicate(of: original, in: devices, createdOn: SyncDevice.watch)
        let duplicateID = duplicate.syncID

        try SyncTidyUp.run(in: devices.phoneContext)

        #expect(week.workouts.count == count)
        #expect(week.workouts[0] === original)
        #expect(try devices.phoneContext.fetch(FetchDescriptor<Workout>()).allSatisfy { $0.syncID != duplicateID })
    }

    @Test("A day planned on both devices keeps the logged sets of whichever copy was logged")
    func duplicateDayKeepsLogged() throws {
        let devices = try TwoDevices()
        let week = try devices.phoneProgram.programWeeks[0]
        let original = week.workouts[0]
        let duplicate = try addDuplicate(of: original, in: devices, createdOn: SyncDevice.watch)
        duplicate.startAndCascade(at: morning)
        let workoutSet = try #require(duplicate.workoutExercises[0].workingSets.first)
        log(workoutSet, reps: 8, at: morning)

        try SyncTidyUp.run(in: devices.phoneContext)

        // The iPhone's copy stays, so both devices pick the same one, and the watch's log moved into it.
        #expect(week.workouts.filter { $0.order == 0 }.count == 1)
        #expect(week.workouts[0] === original)
        #expect(original.status == .active)
        let kept = try #require(original.workoutExercises[0].workingSets.first)
        #expect(kept.status == .complete)
        #expect(kept.reps == 8)
    }

    @Test("Days saved before sync IDs that nothing tells apart both stay")
    func ambiguousDaysStay() throws {
        let devices = try TwoDevices()
        let week = try devices.phoneProgram.programWeeks[0]
        let original = week.workouts[0]
        let count = week.workouts.count
        let duplicate = try addDuplicate(of: original, in: devices, createdOn: SyncDevice.iPhone)
        // As rows saved before these were kept: no sync ID, device or time.
        for day in [original, duplicate] {
            var state = try #require(day.syncState)
            state.createdOn = nil
            state.createdAt = nil
            day.apply(state, exercises: [:])
            day.syncIDValue = nil
        }
        try devices.phoneContext.save()

        try SyncTidyUp.run(in: devices.phoneContext)

        #expect(week.workouts.count == count + 1)
    }

    @Test("A day logged on both devices keeps the latest run and folds the earlier one's other logs into it")
    func duplicateDayBothLogged() throws {
        let devices = try TwoDevices()
        let week = try devices.phoneProgram.programWeeks[0]
        let original = week.workouts[0]
        let duplicate = try addDuplicate(of: original, in: devices, createdOn: SyncDevice.watch)
        original.startAndCascade(at: morning)
        duplicate.startAndCascade(at: afternoon)
        let originalSets = original.workoutExercises[0].workingSets
        let duplicateSets = duplicate.workoutExercises[0].workingSets
        // The morning run logged both sets; the afternoon run only the first, heavier.
        log(originalSets[0], reps: 6, at: morning)
        log(originalSets[1], reps: 6, at: morning.addingTimeInterval(120))
        log(duplicateSets[0], reps: 9, at: afternoon)

        try SyncTidyUp.run(in: devices.phoneContext)

        #expect(week.workouts.filter { $0.order == 0 }.count == 1)
        let kept = week.workouts[0]
        #expect(kept === original)
        let sets = kept.workoutExercises[0].workingSets
        #expect(sets[0].reps == 9)
        #expect(sets[1].status == .complete)
        #expect(sets[1].reps == 6)
    }

    // MARK: History

    @Test("The same workout finished on both devices keeps one volume log, the latest")
    func duplicateWorkoutLogs() throws {
        let devices = try TwoDevices()
        let context = devices.phoneContext
        let session = UUID()
        context.insert(WorkoutLog(date: morning, setsByMuscle: [.chest: 3], sessionID: session))
        context.insert(WorkoutLog(date: afternoon, setsByMuscle: [.chest: 4], sessionID: session))
        context.insert(WorkoutLog(date: morning, setsByMuscle: [.back: 2], sessionID: UUID()))
        context.insert(WorkoutLog(date: morning, setsByMuscle: [.back: 2]))
        try context.save()

        try SyncTidyUp.run(in: context)

        let logs = try context.fetch(FetchDescriptor<WorkoutLog>())
        #expect(logs.count == 3)
        #expect(logs.filter { $0.sessionID == session }.map { $0.sets(for: .chest) } == [4])
    }

    @Test("A strength week closed on both devices keeps one log, the latest")
    func duplicateStrengthLogs() throws {
        let devices = try TwoDevices()
        let context = devices.phoneContext
        let session = UUID()
        context.insert(StrengthLog(date: morning, state: StrengthState(), sessionID: session))
        context.insert(StrengthLog(date: afternoon, state: StrengthState(), sessionID: session))
        try context.save()

        try SyncTidyUp.run(in: context)

        #expect(try context.fetch(FetchDescriptor<StrengthLog>()).map(\.date) == [afternoon])
    }

    // MARK: Running program

    @Test("Two running programs keep the one with logged workouts running and stop the other")
    func twoRunningPrograms() throws {
        let devices = try TwoDevices()
        let context = devices.phoneContext
        let trained = try devices.phoneProgram
        let workoutSet = try startedSet(in: devices)
        log(workoutSet, reps: 8, at: morning)
        let template = try #require(trained.templateProgram)
        let second = Program(programLengthWeeks: 2, templateProgram: template)
        try context.insertAndSave(second)
        second.start()
        try context.save()

        try SyncTidyUp.run(in: context)

        #expect(trained.status == .active)
        #expect(second.status == .stopped)
        #expect(try context.fetchCount(FetchDescriptor<Program>()) == 2)
        #expect(workoutSet.status == .complete)
    }

    @Test("On the watch, two running programs keep the one the iPhone says is running, and stay without its word")
    func twoRunningProgramsFollowIPhone() throws {
        let devices = try TwoDevices()
        let context = devices.phoneContext
        let trained = try devices.phoneProgram
        log(try startedSet(in: devices), reps: 8, at: morning)
        let second = Program(programLengthWeeks: 2, templateProgram: try #require(trained.templateProgram))
        try context.insertAndSave(second)
        second.start()
        try context.save()

        // Only the iPhone decides which program runs.
        try devices.onWatch { _ in try SyncTidyUp.run(in: context) }
        #expect(second.status == .active)
        #expect(trained.status == .active)

        try devices.onWatch { _ in try SyncTidyUp.run(in: context, running: second.syncID) }
        #expect(second.status == .active)
        #expect(trained.status == .stopped)
    }

    @Test("Nothing to tidy changes nothing")
    func nothingToTidy() throws {
        let devices = try TwoDevices()
        log(try startedSet(in: devices), reps: 8, at: morning)
        #expect(try !SyncTidyUp.run(in: devices.phoneContext))
    }

    // MARK: Helpers

    /// The first working set of the iPhone's next workout, started.
    private func startedSet(in devices: TwoDevices) throws -> WorkoutSet {
        let workout = try #require(try devices.phoneProgram.nextWorkout)
        if workout.status == .planned { workout.startAndCascade(at: morning.addingTimeInterval(-60)) }
        return try #require(workout.workoutExercises[0].workingSets.first)
    }

    private func log(_ workoutSet: WorkoutSet, reps: Int, at date: Date) {
        workoutSet.reps = reps
        workoutSet.weightTenthsPounds = 1000
        workoutSet.workoutExerciseValue?.completeSet(workoutSet, at: date)
    }

    /// What iCloud does with another device's log of `workoutSet`: its values overwrite the row, and its receipt arrives.
    private func importLog(on workoutSet: WorkoutSet, reps: Int, at date: Date, from device: String, in context: ModelContext) {
        guard var state = workoutSet.syncState else { return }
        state.reps = reps
        state.completedAt = date
        workoutSet.apply(state)
        context.insert(SetReceipt(for: workoutSet, device: device))
        try? context.save()
    }

    /// The same day as `workout`, planned by another device: new sync IDs, in the same place.
    private func addDuplicate(of workout: Workout, in devices: TwoDevices, createdOn device: String) throws -> Workout {
        var state = ICloud.renumbered(try #require(workout.syncState))
        state.createdOn = device
        state.createdAt = (workout.createdAt ?? .now).addingTimeInterval(-60)
        let exercises = Dictionary(
            try devices.phoneContext.fetch(FetchDescriptor<Exercise>()).compactMap { exercise in exercise.syncKey.map { ($0, exercise) } },
            uniquingKeysWith: { first, _ in first }
        )
        let duplicate = try ICloud.workout(state, exercises: exercises, asSnapshotCopy: false)
        try #require(workout.programWeekValue).attach(duplicate)
        try devices.phoneContext.save()
        return duplicate
    }
}
