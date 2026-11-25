import CoreData
import OSLog
import SwiftData
import UIKit
import UserNotifications

@MainActor
@Observable
final class WorkoutReminders {
    static let shared = WorkoutReminders()
    nonisolated static let category = "workout-preview"
    nonisolated static let previewAction = "preview-next-workout"
    nonisolated static let workoutIDKey = "workoutID"

    nonisolated static let highlightKey = "workoutPreviewHighlight"

    /// A delivered reminder owns its highlight, including an ordinary workout with none.
    struct Highlight: Codable, Hashable {
        let achievement: WorkoutAchievement?
    }

    struct PreviewRequest: Equatable {
        let workoutID: UUID
        let highlight: Highlight?
    }

    private let requestID: String
    private static let scheduledKey = "workoutReminders.scheduled"
    private static let sentKey = "workoutReminders.sent"

    private struct Scheduled: Codable {
        let workoutID: UUID
        let send: Date
    }

    private(set) var previewRequest: PreviewRequest?
    @ObservationIgnored private weak var store: PowerJackStore?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var needsRefresh = false
    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    #if DEBUG
    private var demo: WorkoutReminderDemo?
    #endif

    private init() {
        #if DEBUG
        if WorkoutReminderDemo.enabled {
            requestID = "debug-workout-preview"
            defaults = UserDefaults(suiteName: "PowerJack.WorkoutReminderDemo")!
            defaults.removeObject(forKey: Self.scheduledKey)
            defaults.removeObject(forKey: Self.sentKey)
            defaults.set(true, forKey: AppSettings.Key.workoutReminders)
            return
        }
        #endif
        requestID = "upcoming-workout-preview"
        defaults = .standard
    }

    func start(store: PowerJackStore) {
        #if DEBUG
        if WorkoutReminderDemo.enabled {
            Task {
                await requestAuthorization()
                do {
                    let fixture = try WorkoutReminderDemo(now: .now, calendar: .current, context: store.container.mainContext)
                    defaults.set(fixture.eveningMinute, forKey: AppSettings.Key.workoutReminderEveningMinute)
                    demo = fixture
                } catch {
                    print("Workout reminder demo setup failed: \(error)")
                    return
                }
                self.store = store
                refresh()
            }
            return
        }
        #endif
        self.store = store
        for name in [
            UIApplication.didBecomeActiveNotification,
            UIApplication.significantTimeChangeNotification,
            NSNotification.Name.NSSystemTimeZoneDidChange,
            ModelContext.didSave,
            .NSPersistentStoreRemoteChange
        ] {
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    self?.refresh()
                }
            }
        }
        refresh()
    }

    func registerCategory() {
        let preview = UNNotificationAction(
            identifier: Self.previewAction, title: "Preview what’s next", options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.category, actions: [preview], intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func open(workoutID: UUID, highlightData: Data?) {
        let highlight = highlightData.flatMap { try? JSONDecoder().decode(Highlight.self, from: $0) }
        previewRequest = PreviewRequest(workoutID: workoutID, highlight: highlight)
    }

    func takePreviewRequest() -> PreviewRequest? {
        defer { previewRequest = nil }
        return previewRequest
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Logger.ui.error("Could not request workout reminder permission: \(error.localizedDescription)")
        }
    }

    func refresh() {
        guard store != nil else { return }
        needsRefresh = true
        guard refreshTask == nil else { return }

        // Treat a burst of saves as one change, and serialize requests to the notification center.
        refreshTask = Task {
            while needsRefresh {
                try? await Task.sleep(for: .milliseconds(200))
                needsRefresh = false
                await reconcile()
            }
            refreshTask = nil
        }
    }

    private func reconcile() async {
        let authorization = await center.notificationSettings().authorizationStatus
        let pending = await center.pendingNotificationRequests().first { $0.identifier == self.requestID }
        guard !needsRefresh else { return }

        let now = Date.now
        let lastScheduled = defaults.data(forKey: Self.scheduledKey)
            .flatMap { try? JSONDecoder().decode(Scheduled.self, from: $0) }
        var sentIDs = defaults.stringArray(forKey: Self.sentKey) ?? []
        if let lastScheduled, lastScheduled.send <= now, pending == nil {
            let id = lastScheduled.workoutID.uuidString
            sentIDs.removeAll { $0 == id }
            sentIDs.append(id)
            defaults.set(Array(sentIDs.suffix(64)), forKey: Self.sentKey)
            defaults.removeObject(forKey: Self.scheduledKey)
        }

        guard defaults.bool(forKey: AppSettings.Key.workoutReminders),
              [.authorized, .provisional, .ephemeral].contains(authorization),
              let store, !store.isReplacingContainer else {
            cancel()
            return
        }

        let context = store.container.mainContext
        do {
            let programs = try context.fetch(FetchDescriptor<Program>())
            guard let program = programs.active,
                  let workout = program.nextWorkout, workout.status == .planned,
                  let id = workout.syncID, !sentIDs.contains(id.uuidString) else {
                cancel()
                return
            }
            let preview = WorkoutPreview(program: program, workout: workout)
            guard !preview.lifts.isEmpty else {
                cancel()
                return
            }

            let calendar = Calendar.current
            let history = try WorkoutPreviewHistory(programs: programs, in: context, now: now)
            let eveningMinute = defaults.object(forKey: AppSettings.Key.workoutReminderEveningMinute) as? Int
                ?? WorkoutReminderTiming.defaultEveningMinute
            guard let timing = WorkoutReminderTiming.next(
                starts: history.starts, now: now, calendar: calendar, eveningMinute: eveningMinute
            ) else {
                cancel()
                return
            }
            #if DEBUG
            if let demo, timing.send > demo.deadline { return }
            #endif
            let achievement = WorkoutAchievement.selected(
                preview: preview, program: program, workout: workout, history: history, at: timing.workout
            )
            let title = timing.title(calendar: calendar)
            let facts = WorkoutReminderCopy.Facts(
                preview: preview, program: program, workout: workout, timingTitle: title,
                achievement: achievement, history: history
            )
            let fingerprint = facts.fingerprint
            let matchesPending = pending.map { request in
                request.content.title == title &&
                    request.content.userInfo["trainerCopyFacts"] as? String == fingerprint &&
                    request.content.userInfo[Self.workoutIDKey] as? String == id.uuidString &&
                    (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() == timing.send
            } ?? false
            if matchesPending, pending?.content.body != WorkoutReminderCopy.fallback { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = WorkoutReminderCopy.fallback
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.userInfo = [
                Self.workoutIDKey: id.uuidString, "trainerCopyFacts": fingerprint,
                Self.highlightKey: try JSONEncoder().encode(Highlight(achievement: achievement))
            ]

            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: timing.send)
            components.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            guard Date.now < timing.send else {
                cancel()
                return
            }
            // Schedule first so suspension or slow generation still leaves a deliverable reminder.
            if !matchesPending {
                try await center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
                #if DEBUG
                if demo != nil { print("Workout reminder demo: scheduled for \(timing.send) with fallback.") }
                #endif
                let scheduled = try JSONEncoder().encode(Scheduled(workoutID: id, send: timing.send))
                defaults.set(scheduled, forKey: Self.scheduledKey)
            }
            guard let body = await WorkoutReminderCopy.generate(for: facts),
                  !needsRefresh, Date.now < timing.send else { return }
            content.body = body
            do {
                try await center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
                #if DEBUG
                if demo != nil { print("Workout reminder demo: AI body: \(body)") }
                #endif
            } catch {
                Logger.ui.error("Could not replace workout reminder fallback: \(error.localizedDescription)")
            }
        } catch {
            cancel()
            Logger.ui.error("Could not update the workout reminder: \(error.localizedDescription)")
        }
    }

    private func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        defaults.removeObject(forKey: Self.scheduledKey)
    }
}
