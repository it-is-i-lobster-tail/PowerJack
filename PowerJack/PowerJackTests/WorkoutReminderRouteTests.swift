import Foundation
import Testing
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
}
