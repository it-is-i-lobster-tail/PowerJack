//
//  WatchPhoneSyncTests.swift
//  PowerJackTests
//
//  The iPhone and the watch synced straight to each other: the iPhone's program reaching a watch
//  that never synced through iCloud, and the iPhone refereeing sets both devices logged.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct SetRefereeTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func log(_ reps: Int, at seconds: TimeInterval, correction: Bool = false) -> SetLog {
        SetLog(weightTenthsPounds: 1000, reps: reps, completedAt: t0.addingTimeInterval(seconds), isCorrection: correction)
    }

    @Test("A set only the watch logged takes the watch's log")
    func onlyWatchLogged() {
        #expect(SetReferee.winner(iPhone: nil, watch: log(8, at: 0)) == .watch)
    }

    @Test("Together, the first log wins")
    func firstLogWins() {
        #expect(SetReferee.winner(iPhone: log(6, at: 30), watch: log(8, at: 0)) == .watch)
        #expect(SetReferee.winner(iPhone: log(6, at: 0), watch: log(8, at: 30)) == .iPhone)
    }

    @Test("Logs at the same moment go to the iPhone")
    func sameMomentGoesToIPhone() {
        #expect(SetReferee.winner(iPhone: log(6, at: 1.5), watch: log(8, at: 0)) == .iPhone)
        #expect(SetReferee.winner(iPhone: log(6, at: 0), watch: log(8, at: 1.5)) == .iPhone)
    }

    @Test("Fixing a logged set wins over a plain log, and the later of two fixes stands")
    func correctionsWin() {
        #expect(SetReferee.winner(iPhone: log(6, at: 60, correction: true), watch: log(8, at: 0)) == .iPhone)
        #expect(SetReferee.winner(iPhone: log(6, at: 0), watch: log(8, at: 60, correction: true)) == .watch)
        #expect(SetReferee.winner(iPhone: log(6, at: 0, correction: true), watch: log(8, at: 60, correction: true)) == .watch)
        #expect(SetReferee.winner(iPhone: log(6, at: 60, correction: true), watch: log(8, at: 0, correction: true)) == .iPhone)
    }

    @Test("A log made apart follows the iCloud rule: the latest wins")
    func apartLatestWins() {
        #expect(SetReferee.winner(iPhone: log(6, at: 0), watch: log(8, at: 3600), together: false) == .watch)
        #expect(SetReferee.winner(iPhone: log(6, at: 3600), watch: log(8, at: 0), together: false) == .iPhone)
    }

    @Test("The same weight and reps leave the iPhone's log as it is")
    func sameValuesKeepIPhone() {
        #expect(SetReferee.winner(iPhone: log(8, at: 60), watch: log(8, at: 0)) == .iPhone)
    }

    @Test("Apart, the log made last wins, whenever it uploaded")
    func latestLog() {
        let logs = [log(6, at: 3600), log(8, at: 0), log(7, at: 1800)]
        #expect(SetReferee.latest(logs) == log(6, at: 3600))
        #expect(SetReferee.latest([]) == nil)
    }
}

@MainActor
struct WatchPhoneSyncTests {
    private let t0 = Date.now.addingTimeInterval(-3600)

    @Test("A watch that never synced through iCloud gets the running program straight from the iPhone")
    func watchGetsProgram() throws {
        let devices = try TwoDevices()
        #expect(try devices.watchContext.fetchCount(FetchDescriptor<Program>()) == 0)

        try devices.sendProgram()

        let phoneProgram = try devices.phoneProgram
        let watchProgram = try devices.watchProgram
        #expect(watchProgram.syncID == phoneProgram.syncID)
        #expect(watchProgram.templateName == phoneProgram.templateName)
        #expect(watchProgram.programWeeks.count == phoneProgram.programWeeks.count)
        let phoneWorkout = try #require(phoneProgram.nextWorkout)
        let watchWorkout = try #require(watchProgram.nextWorkout)
        #expect(watchWorkout.syncID == phoneWorkout.syncID)
        #expect(watchWorkout.workoutExercises.map { $0.exercise?.exerciseName } == phoneWorkout.workoutExercises.map { $0.exercise?.exerciseName })
        #expect(watchWorkout.workoutExercises.map(\.workoutSets.count) == phoneWorkout.workoutExercises.map(\.workoutSets.count))

        // Sending again updates the same rows instead of making more.
        try devices.sendProgram()
        #expect(try devices.watchContext.fetchCount(FetchDescriptor<Program>()) == 1)
        #expect(try devices.watchContext.fetchCount(FetchDescriptor<WorkoutSet>()) == devices.phoneContext.fetchCount(FetchDescriptor<WorkoutSet>()))
    }

    @Test("A new watch waits for the iPhone, then knows when no program runs there, and remembers it heard")
    func watchKnowsWhenNothingRuns() throws {
        let devices = try TwoDevices()
        #expect(!devices.replica.heardFromIPhone)

        try devices.phoneProgram.stopAndCascade()
        try devices.phoneContext.save()
        try devices.sendChanges()

        #expect(devices.replica.heardFromIPhone)
        #expect(try devices.watchContext.fetch(FetchDescriptor<Program>()).active == nil)
        #expect(WatchReplica(defaults: devices.replicaDefaults).heardFromIPhone)
    }

    @Test("A workout started and logged on the watch reaches the iPhone, which shows it's in progress on the watch")
    func watchWorkoutReachesIPhone() throws {
        let devices = try TwoDevices()
        try devices.sendProgram()
        let watchProgram = try devices.watchProgram
        let workout = try #require(watchProgram.nextWorkout)
        let workoutExercise = workout.workoutExercises[0]
        let workoutSet = try #require(workoutExercise.workingSets.first)
        devices.onWatch { actions in
            actions.start(workout, in: watchProgram, at: t0)
            var entry = SetEntry(for: workoutSet, unit: .pounds)
            entry.weight = 135
            entry.reps = 8
            actions.log(entry, on: workoutSet, of: workoutExercise, at: t0.addingTimeInterval(60))
        }

        #expect(try devices.sendChanges())

        let phoneWorkout = try #require(try devices.phoneProgram.nextWorkout)
        #expect(phoneWorkout.syncID == workout.syncID)
        #expect(phoneWorkout.status == .active)
        #expect(phoneWorkout.startedOn == SyncDevice.watch)
        let phoneSet = try devices.onPhone(workoutSet)
        #expect(phoneSet.status == .complete)
        #expect(phoneSet.reps == 8)
        #expect(phoneSet.weightTenthsPounds == 1350)
        #expect(devices.replica.pending.isEmpty)
    }

    @Test("Logged on the watch, then on the iPhone: the watch's log stands and the iPhone shows it")
    func watchThenPhone() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        logOnWatch(devices, watchSet, of: watchExercise, reps: 8, at: t0)
        let phoneSet = try devices.onPhone(watchSet)
        logOnPhone(phoneSet, reps: 6, at: t0.addingTimeInterval(20))

        try devices.sendChanges()

        #expect(phoneSet.reps == 8)
        #expect(watchSet.reps == 8)
    }

    @Test("Logged on the iPhone, then on the watch: the iPhone's log stands and the watch takes it")
    func phoneThenWatch() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        let phoneSet = try devices.onPhone(watchSet)
        logOnPhone(phoneSet, reps: 6, at: t0)
        logOnWatch(devices, watchSet, of: watchExercise, reps: 8, at: t0.addingTimeInterval(20))

        try devices.sendChanges()

        #expect(phoneSet.reps == 6)
        // The iPhone answered with the right value, and the watch applied it.
        #expect(watchSet.reps == 6)
        #expect(watchSet.status == .complete)
    }

    @Test("Logged at the same moment on both: the iPhone's log stands")
    func simultaneousGoesToIPhone() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        logOnWatch(devices, watchSet, of: watchExercise, reps: 8, at: t0)
        let phoneSet = try devices.onPhone(watchSet)
        logOnPhone(phoneSet, reps: 6, at: t0.addingTimeInterval(1))

        try devices.sendChanges()

        #expect(phoneSet.reps == 6)
        #expect(watchSet.reps == 6)
    }

    @Test("Fixing a logged set on the iPhone wins over the watch's earlier log")
    func phoneCorrectionWins() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        logOnWatch(devices, watchSet, of: watchExercise, reps: 8, at: t0)
        let phoneSet = try devices.onPhone(watchSet)
        logOnPhone(phoneSet, reps: 6, at: t0.addingTimeInterval(60))
        // Reopened and logged again: a fix.
        phoneSet.start()
        logOnPhone(phoneSet, reps: 7, at: t0.addingTimeInterval(120))

        try devices.sendChanges()

        #expect(phoneSet.reps == 7)
        #expect(watchSet.reps == 7)
    }

    @Test("A log the watch made apart from the iPhone follows the latest-log rule when it arrives")
    func apartLogFollowsLatest() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        let phoneSet = try devices.onPhone(watchSet)
        logOnPhone(phoneSet, reps: 6, at: t0)
        logOnWatch(devices, watchSet, of: watchExercise, reps: 8, at: t0.addingTimeInterval(600), together: false)

        try devices.sendChanges()

        #expect(phoneSet.reps == 8)
        #expect(watchSet.reps == 8)
    }

    @Test("A refereed set keeps the winner after the tidy-up replays the receipts")
    func refereeAgreesWithReceipts() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        let phoneSet = try devices.onPhone(watchSet)
        logOnPhone(phoneSet, reps: 6, at: t0)
        logOnWatch(devices, watchSet, of: watchExercise, reps: 8, at: t0.addingTimeInterval(20))
        try devices.sendChanges()

        // The watch's receipt is the later log, but the iPhone's ruling was stamped after it.
        try SyncTidyUp.run(in: devices.phoneContext)
        try SyncTidyUp.run(in: devices.watchContext)

        #expect(phoneSet.reps == 6)
        #expect(watchSet.reps == 6)
    }

    @Test("The watch pushes everything pending before it takes the iPhone's program")
    func handshakeWaitsForPending() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        logOnWatch(devices, watchSet, of: watchExercise, reps: 8, at: t0)

        // The iPhone's program doesn't have the watch's set yet, so the watch keeps its own.
        #expect(try !devices.sendProgram())
        #expect(watchSet.status == .complete)
        #expect(watchSet.reps == 8)
        #expect(devices.replica.pending.count == 1)

        #expect(try devices.sendChanges())
        #expect(devices.replica.pending.isEmpty)
        #expect(try devices.onPhone(watchSet).reps == 8)
    }

    @Test("The iPhone applies each watch change once, however often it arrives")
    func changesApplyOnce() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        logOnWatch(devices, watchSet, of: watchExercise, reps: 8, at: t0)
        let resent = devices.replica.pending
        try devices.sendChanges()
        let phoneSet = try devices.onPhone(watchSet)
        // Fixed on the iPhone afterwards.
        phoneSet.start()
        logOnPhone(phoneSet, reps: 9, at: t0.addingTimeInterval(120))

        _ = try devices.referee.receive(resent, in: devices.phoneContext)

        #expect(phoneSet.reps == 9)
    }

    @Test("A change naming a program the iPhone doesn't have never lands on the running one")
    func unknownProgramIgnored() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        logOnWatch(devices, watchSet, of: watchExercise, reps: 8, at: t0)
        var changes = devices.replica.pending
        for index in changes.indices {
            changes[index].row.program = UUID()
            changes[index].row.set = UUID()
        }

        _ = try devices.referee.receive(changes, in: devices.phoneContext)

        #expect(try devices.onPhone(watchSet).status == .active)
    }

    @Test("Apart with iCloud Backup off, the watch keeps every change until the iPhone is back")
    func apartHoldsChanges() throws {
        let devices = try TwoDevices()
        try devices.sendProgram()
        let watchProgram = try devices.watchProgram
        let workout = try #require(watchProgram.nextWorkout)

        devices.onWatch(together: false) { $0.train(workout, in: watchProgram, at: t0) }
        let pending = devices.replica.pending.count
        #expect(pending > 3)
        // Kept in the watch's settings, so it survives the app quitting.
        #expect(WatchReplica(defaults: devices.replicaDefaults).pending.count == pending)

        try devices.sendChanges()

        let phoneWorkout = try #require(try devices.phoneProgram.programWeeks[0].workouts.first)
        #expect(phoneWorkout.status == .complete)
        #expect(phoneWorkout.completedWorkingSets == workout.completedWorkingSets)
        #expect(phoneWorkout.workoutExercises.allSatisfy { $0.feedback != nil || !$0.needsFeedback })
        #expect(try devices.phoneContext.fetchCount(FetchDescriptor<WorkoutLog>()) == 1)
    }

    @Test("A week the watch planned on its own merges into the iPhone's, not next to it")
    func watchPlannedWeekMerges() throws {
        let devices = try TwoDevices(weeks: 3)
        try devices.sendProgram()
        let watchProgram = try devices.watchProgram
        let weekOne = watchProgram.programWeeks[0]
        devices.onWatch(together: false) { actions in
            var day = 0
            while let workout = watchProgram.nextWorkout, workout.programWeekValue === weekOne {
                actions.train(workout, in: watchProgram, at: t0.addingTimeInterval(Double(day) * 3600))
                day += 1
            }
        }
        // The watch planned week 2 itself, then started it and logged a set.
        let watchWeekTwo = watchProgram.programWeeks[1]
        #expect(!watchWeekTwo.workouts.isEmpty)
        let dayOne = try #require(watchProgram.nextWorkout)
        let exercise = dayOne.workoutExercises[0]
        let set = try devices.onWatch(together: false) { actions in
            actions.start(dayOne, in: watchProgram, at: t0.addingTimeInterval(86_400))
            let set = try #require(exercise.nextSet)
            var entry = SetEntry(for: set, unit: .pounds)
            if entry.weightTenthsPounds == nil { entry.weight = 100 }
            actions.log(entry, on: set, of: exercise, at: t0.addingTimeInterval(86_460))
            return set
        }
        let loggedReps = set.reps

        try devices.sendChanges()

        // The iPhone planned its own week 2 and found the watch's day by its place in it.
        let phoneWeekTwo = try devices.phoneProgram.programWeeks[1]
        #expect(phoneWeekTwo.workouts.count == weekOne.workouts.count)
        let phoneDayOne = try #require(phoneWeekTwo.workouts.first)
        #expect(phoneDayOne.status == .active)
        #expect(phoneDayOne.workoutExercises[0].workoutSets.contains { $0.status == .complete && $0.reps == loggedReps })

        // The watch now holds the iPhone's week, once.
        let weekTwo = try devices.watchProgram.programWeeks[1]
        #expect(weekTwo.workouts.count == phoneWeekTwo.workouts.count)
        #expect(weekTwo.workouts.map(\.syncID) == phoneWeekTwo.workouts.map(\.syncID))
        #expect(weekTwo.workouts[0].workoutExercises[0].workoutSets.contains { $0.status == .complete && $0.reps == loggedReps })
    }

    @Test("Rows saved before sync IDs take the iPhone's IDs on the watch instead of being copied")
    func oldRowsAdoptIDs() throws {
        let devices = try TwoDevices()
        // Both devices hold the program from iCloud, saved by a version without sync IDs.
        try ICloud.bring(devices.phoneProgram, into: devices.watchContext, asSnapshotCopies: false)
        for context in [devices.phoneContext, devices.watchContext] {
            for program in try context.fetch(FetchDescriptor<Program>()) { program.syncIDValue = nil }
            for week in try context.fetch(FetchDescriptor<ProgramWeek>()) { week.syncIDValue = nil }
            for workout in try context.fetch(FetchDescriptor<Workout>()) { workout.syncIDValue = nil }
            for workoutExercise in try context.fetch(FetchDescriptor<WorkoutExercise>()) { workoutExercise.syncIDValue = nil }
            for workoutSet in try context.fetch(FetchDescriptor<WorkoutSet>()) { workoutSet.syncIDValue = nil }
            try context.save()
        }

        try devices.sendProgram()

        let watch = devices.watchContext
        #expect(try watch.fetchCount(FetchDescriptor<Program>()) == 1)
        #expect(try WorkoutSet.fromSnapshot(in: watch).isEmpty)
        #expect(try watch.fetchCount(FetchDescriptor<WorkoutSet>()) == devices.phoneContext.fetchCount(FetchDescriptor<WorkoutSet>()))
        let phoneIDs = Set(try devices.phoneContext.fetch(FetchDescriptor<WorkoutSet>()).compactMap(\.syncID))
        let watchIDs = Set(try watch.fetch(FetchDescriptor<WorkoutSet>()).compactMap(\.syncID))
        #expect(!phoneIDs.isEmpty)
        #expect(watchIDs == phoneIDs)
    }

    @Test("A program the iPhone stopped stops on the watch too, and the new one runs")
    func stoppedProgramFollowsIPhone() throws {
        let devices = try TwoDevices()
        try devices.sendProgram()
        let oldProgram = try devices.phoneProgram
        let template = try #require(oldProgram.templateProgram)
        let newProgram = Program(programLengthWeeks: 2, templateProgram: template)
        try devices.phoneContext.insertAndSave(newProgram)
        oldProgram.stop()
        oldProgram.stopAndCascade()
        newProgram.start()
        try devices.phoneContext.save()

        try devices.sendProgram()

        let programs = try devices.watchContext.fetch(FetchDescriptor<Program>())
        #expect(programs.count == 2)
        #expect(programs.active?.syncID == newProgram.syncID)
        #expect(programs.first { $0.syncID == oldProgram.syncID }?.status == .stopped)
    }

    @Test("Every log writes a receipt naming the device, including a watch log the iPhone applies")
    func receiptsNameTheDevice() throws {
        let (devices, watchSet, watchExercise) = try startedOnWatch()
        logOnWatch(devices, watchSet, of: watchExercise, reps: 8, at: t0)
        try devices.sendChanges()
        let phoneOther = try devices.onPhone(try #require(watchExercise.workingSets.last))
        logOnPhone(phoneOther, reps: 5, at: t0.addingTimeInterval(120))

        let watchReceipts = try devices.watchContext.fetch(FetchDescriptor<SetReceipt>())
        #expect(watchReceipts.map(\.device) == [SyncDevice.watch])
        let phoneReceipts = try devices.phoneContext.fetch(FetchDescriptor<SetReceipt>()).sorted { $0.log.completedAt < $1.log.completedAt }
        #expect(phoneReceipts.map(\.device) == [SyncDevice.watch, SyncDevice.iPhone])
        #expect(phoneReceipts[0].setID == watchSet.syncID)
        #expect(phoneReceipts[0].sessionID == watchExercise.workoutValue?.syncID)
    }

    @Test("Finishing a workout names it in the volume log")
    func workoutLogNamesSession() throws {
        let devices = try TwoDevices()
        let program = try devices.phoneProgram
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let workoutExercise = workout.workoutExercises[0]
        let workoutSet = try #require(workoutExercise.workingSets.first)
        logOnPhone(workoutSet, reps: 8, at: t0)
        program.finishWorkout(workout)

        let log = try #require(try devices.phoneContext.fetch(FetchDescriptor<WorkoutLog>()).first)
        #expect(log.sessionID == workout.syncID)
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
        let workoutExercise = workout.workoutExercises[0]
        return (devices, try #require(workoutExercise.workingSets.first), workoutExercise)
    }

    private func logOnWatch(_ devices: TwoDevices, _ workoutSet: WorkoutSet, of workoutExercise: WorkoutExercise, reps: Int, at date: Date, together: Bool = true) {
        var entry = SetEntry(for: workoutSet, unit: .pounds)
        entry.weight = 100
        entry.reps = reps
        devices.onWatch(together: together) { $0.log(entry, on: workoutSet, of: workoutExercise, at: date) }
    }

    private func logOnPhone(_ workoutSet: WorkoutSet, reps: Int, at date: Date) {
        workoutSet.reps = reps
        workoutSet.weightTenthsPounds = 1000
        workoutSet.workoutExerciseValue?.completeSet(workoutSet, at: date)
    }
}
