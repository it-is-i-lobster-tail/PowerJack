import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import PowerJack

@MainActor
struct WorkoutReminderRouteTests {
    @Test func tapPreservesTheDeliveredHighlightAndConsumesItOnce() throws {
        let id = UUID()
        let winner = WorkoutAchievement(kind: .sessionVolume, previous: 10_000, target: 12_000)
        let highlight = WorkoutReminders.Highlight(achievement: winner)
        let reminders = WorkoutReminders.shared
        reminders.open(workoutID: id, highlightData: try JSONEncoder().encode(highlight))
        let request = try #require(reminders.takePreviewRequest())
        #expect(request.workoutID == id)
        #expect(request.highlight == highlight)
        #expect(reminders.takePreviewRequest() == nil)

        // An explicitly ordinary reminder stays ordinary. An old notification can evaluate on open.
        let ordinary = WorkoutReminders.Highlight(achievement: nil)
        reminders.open(workoutID: id, highlightData: try JSONEncoder().encode(ordinary))
        #expect(reminders.takePreviewRequest()?.highlight == ordinary)
        reminders.open(workoutID: id, highlightData: nil)
        #expect(reminders.takePreviewRequest()?.highlight == nil)
    }

    @Test func sendNowUsesTheScheduledReminderContentUnderItsOwnIdentifier() throws {
        let store = PowerJackStore(inMemory: true)
        let context = store.container!.mainContext
        let now = Date.now
        let program = try WorkoutReminderDemo.seed(.extraSet, type: .hypertrophy, starter: false, context: context, now: now)
        let workout = try #require(program.nextWorkout)
        let history = try WorkoutPreviewHistory(programs: [program], in: context, now: now)
        let timing = WorkoutReminderTiming.Prediction(workout: now, send: now, nightBefore: false)

        let reminder = try #require(try WorkoutReminders.makeReminder(
            programs: [program], history: history, timing: timing, calendar: .current
        ))
        #expect(reminder.workoutID == workout.syncID)
        #expect(reminder.content.title == timing.title(calendar: .current))
        #expect(reminder.content.body == WorkoutReminderCopy.fallback)
        #expect(reminder.content.categoryIdentifier == WorkoutReminders.category)
        #expect(reminder.content.userInfo[WorkoutReminders.workoutIDKey] as? String == workout.syncID?.uuidString)
        #expect(reminder.content.userInfo["trainerCopyFacts"] as? String == reminder.facts.fingerprint)
        #expect(reminder.content.userInfo[WorkoutReminders.highlightKey] is Data)

        let request = WorkoutReminders.sendNowRequest(content: reminder.content)
        #expect(request.identifier == WorkoutReminders.sendNowRequestID)
        #expect(!["upcoming-workout-preview", "debug-workout-preview"].contains(request.identifier))
        #expect(request.content.title == reminder.content.title)
        #expect(request.content.userInfo[WorkoutReminders.workoutIDKey] as? String == workout.syncID?.uuidString)
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval <= 2)
        #expect(!trigger.repeats)
    }

    @Test func pausedWorkoutGetsAReminderForTheSetsLeft() throws {
        let store = PowerJackStore(inMemory: true)
        let context = store.container!.mainContext
        let now = Date.now
        let program = try WorkoutReminderDemo.seed(.extraSet, type: .hypertrophy, starter: false, context: context, now: now)
        let workout = try #require(program.nextWorkout)
        let history = try WorkoutPreviewHistory(programs: [program], in: context, now: now)
        let timing = WorkoutReminderTiming.Prediction(workout: now, send: now, nightBefore: false)
        func reminder() throws -> WorkoutReminders.Reminder? {
            try WorkoutReminders.makeReminder(programs: [program], history: history, timing: timing, calendar: .current)
        }

        workout.startAndCascade(at: now - 600)
        let first = try #require(workout.workoutExercises.first)
        let logged = try #require(first.workingSets.first)
        first.completeSet(logged, at: now - 300)
        // A workout in progress gets no reminder.
        #expect(try reminder() == nil)

        workout.pause(at: now - 200)
        let paused = try #require(try reminder())
        #expect(paused.workoutID == workout.syncID)
        #expect(paused.content.body == WorkoutReminderCopy.fallback)
        // The logged set is left out; only the sets still to do are listed.
        let left = first.workingSets.filter { !$0.isDone }.count
        #expect(left == first.workingSets.count - 1)
        let lift = try #require(paused.facts.exercises.first)
        #expect(lift.workingSetCount == left)
    }

    @Test func pausedWorkoutWithNoSetsLeftGetsNoReminder() throws {
        let store = PowerJackStore(inMemory: true)
        let context = store.container!.mainContext
        let now = Date.now
        let program = try WorkoutReminderDemo.seed(.extraSet, type: .hypertrophy, starter: false, context: context, now: now)
        let workout = try #require(program.nextWorkout)
        let history = try WorkoutPreviewHistory(programs: [program], in: context, now: now)
        let timing = WorkoutReminderTiming.Prediction(workout: now, send: now, nightBefore: false)

        workout.startAndCascade(at: now - 600)
        for entry in workout.workoutExercises {
            for set in entry.workingSets { set.skip() }
        }
        workout.pause(at: now - 200)
        #expect(program.nextWorkout === workout)
        #expect(workout.isPaused)
        #expect(try WorkoutReminders.makeReminder(
            programs: [program], history: history, timing: timing, calendar: .current
        ) == nil)
    }

    @Test func noReminderWithoutAnActiveProgram() throws {
        let store = PowerJackStore(inMemory: true)
        let history = try WorkoutPreviewHistory(programs: [], in: store.container!.mainContext, now: .now)
        let timing = WorkoutReminderTiming.Prediction(workout: .now, send: .now, nightBefore: false)
        #expect(try WorkoutReminders.makeReminder(programs: [], history: history, timing: timing, calendar: .current) == nil)
    }
}
