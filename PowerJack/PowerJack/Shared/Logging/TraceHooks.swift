//
//  TraceHooks.swift
//  PowerJack
//
//  Feeds `TraceLog` from the whole app: the app's lifecycle, every touch, every SwiftData save,
//  iCloud sync and settings changes. Each hook returns straight away while tracing is off.
//

import CoreData
import SwiftData
import SwiftUI
import UIKit

enum TraceHooks {
    private static var observers: [NSObjectProtocol] = []
    private static var lastSettings: [String: String] = [:]

    static func start() {
        guard observers.isEmpty else { return }
        observeLifecycle()
        observeTouches()
        observeSaves()
        observeICloud()
        observeSettings()
    }

    /// Runs `handle` on the main actor for each notification while tracing is on. `synchronously`
    /// handles it on the posting thread, before the poster carries on.
    private static func observe(
        _ name: Notification.Name,
        synchronously: Bool = false,
        _ handle: @escaping @MainActor @Sendable (Notification) -> Void
    ) {
        let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: synchronously ? nil : .main) { notification in
            guard TraceLog.shared.isEnabled else { return }
            // Only SwiftData's own background contexts post off the main thread. Their rows can't
            // be read from here, so they're only noted.
            guard Thread.isMainThread else {
                TraceLog.record(.data, "\(name.rawValue) in the background")
                return
            }
            MainActor.assumeIsolated { handle(notification) }
        }
        observers.append(observer)
    }

    // MARK: Lifecycle

    private static func observeLifecycle() {
        let events: [(Notification.Name, String)] = [
            (UIApplication.didBecomeActiveNotification, "Became active"),
            (UIApplication.willResignActiveNotification, "Will resign active"),
            (UIApplication.didEnterBackgroundNotification, "Entered the background"),
            (UIApplication.willEnterForegroundNotification, "Will enter the foreground"),
            (UIApplication.willTerminateNotification, "Will terminate"),
            (UIApplication.didReceiveMemoryWarningNotification, "Memory warning"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "iPhone locking"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "iPhone unlocked"),
        ]
        for (name, message) in events {
            observe(name) { _ in TraceLog.record(.lifecycle, message) }
        }
        // The app may not come back, so what's queued goes to disk now.
        observe(UIApplication.didEnterBackgroundNotification) { _ in
            Task { await TraceLog.shared.flush() }
        }
    }

    // MARK: Touches

    /// Every window gets a recognizer that only watches, so touches reach the app as before.
    private static func observeTouches() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? UIWindow,
                      !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchTracer })
                else { return }
                window.addGestureRecognizer(TouchTracer())
            }
        })
    }

    // MARK: Saves

    /// Every save on any context. The changes are read before the save, while they're still pending.
    private static func observeSaves() {
        observe(ModelContext.willSave, synchronously: true) { notification in
            guard let context = notification.object as? ModelContext else { return }
            recordPendingChanges(in: context)
        }
        observe(ModelContext.didSave) { _ in TraceLog.record(.data, "Saved") }
    }

    private static func recordPendingChanges(in context: ModelContext) {
        let inserted = context.insertedModelsArray
        let changed = context.changedModelsArray
        let deleted = context.deletedModelsArray
        guard !(inserted.isEmpty && changed.isEmpty && deleted.isEmpty) else {
            TraceLog.record(.data, "Saving with no changes")
            return
        }
        TraceLog.record(.data, "Saving: inserted \(counts(of: inserted)); changed \(counts(of: changed)); deleted \(counts(of: deleted))")
        // Deleted rows only show as counts: their values may already be gone.
        for model in inserted { TraceLog.record(.data, "+ \(describe(model))") }
        for model in changed { TraceLog.record(.data, "~ \(describe(model))") }
    }

    /// e.g. "2 WorkoutSet, 1 Workout", or "none".
    private static func counts(of models: [any PersistentModel]) -> String {
        guard !models.isEmpty else { return "none" }
        let names = models.map { String(describing: type(of: $0)) }
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        return counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
    }

    private static func describe(_ model: any PersistentModel) -> String {
        switch model {
        case let workoutSet as WorkoutSet: workoutSet.traceDescription
        case let workoutExercise as WorkoutExercise: workoutExercise.traceDescription
        case let workout as Workout: workout.traceDescription
        case let program as Program: program.traceDescription
        case let exercise as Exercise: exercise.traceName
        // Other rows, like templates, can hold names the lifter typed, so only their kind shows.
        default: String(describing: type(of: model))
        }
    }

    // MARK: iCloud

    private static func observeICloud() {
        observe(NSPersistentCloudKitContainer.eventChangedNotification) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let kind = switch event.type {
            case .setup: "setup"
            case .import: "download"
            case .export: "upload"
            @unknown default: "sync"
            }
            guard event.endDate != nil else {
                TraceLog.record(.iCloud, "\(kind) started")
                return
            }
            if let error = event.error {
                // Only domains and codes: an iCloud error's text can name the account.
                TraceLog.record(.iCloud, "\(kind) failed: \(TraceLog.describe(error))")
            } else {
                TraceLog.record(.iCloud, "\(kind) finished")
            }
        }
        observe(.NSPersistentStoreRemoteChange) { _ in TraceLog.record(.iCloud, "iCloud changed the store") }
    }

    // MARK: Settings

    /// Settings are a switch or a number each, so their values are safe to record.
    private static func observeSettings() {
        lastSettings = currentSettings()
        observe(UserDefaults.didChangeNotification) { _ in
            let settings = currentSettings()
            for key in Set(settings.keys).union(lastSettings.keys).sorted() where settings[key] != lastSettings[key] {
                TraceLog.record(.settings, "\(key) = \(settings[key] ?? "default")")
            }
            lastSettings = settings
        }
    }

    private static func currentSettings() -> [String: String] {
        SettingsSync().settings.mapValues { String(describing: $0) }
    }
}

/// Records where each touch lands without ever taking part in it: it never recognizes, cancels
/// or delays a touch. It records points only, never what's under them, which can be typed text.
private final class TouchTracer: UIGestureRecognizer {
    // A touch that moves further than this is a swipe or a drag.
    private static let tapDistance: CGFloat = 10

    private var startPoint: CGPoint?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard TraceLog.shared.isEnabled else {
            state = .failed
            return
        }
        if startPoint == nil { startPoint = touches.first?.location(in: view) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let startPoint, let end = touches.first?.location(in: view) {
            let distance = hypot(end.x - startPoint.x, end.y - startPoint.y)
            if distance <= Self.tapDistance {
                let target = Self.kind(of: view?.hitTest(end, with: nil)).map { " on a \($0)" } ?? ""
                TraceLog.record(.tap, "Tap at \(Self.text(end))\(target)")
            } else {
                TraceLog.record(.tap, "Swipe from \(Self.text(startPoint)) to \(Self.text(end))")
            }
        }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func reset() {
        startPoint = nil
    }

    /// The kind of UIKit view under a touch, like a text field or a list row. SwiftUI buttons have
    /// no view of their own, so their taps show only as points.
    private static func kind(of hitView: UIView?) -> String? {
        var view = hitView
        while let current = view {
            switch current {
            case is UITextField, is UITextView: return "text field"
            case is UISwitch: return "switch"
            case is UISlider: return "slider"
            case is UISegmentedControl: return "segmented control"
            case is UIButton: return "button"
            case is UICollectionViewCell, is UITableViewCell: return "list row"
            case is UINavigationBar: return "navigation bar"
            case is UIWindow: return nil
            default: view = current.superview
            }
        }
        return nil
    }

    private static func text(_ point: CGPoint) -> String {
        "(\(Int(point.x.rounded())), \(Int(point.y.rounded())))"
    }
}

extension View {
    /// Records when this screen opens and closes.
    func traceScreen(_ name: String) -> some View {
        onAppear { TraceLog.record(.screen, "Opened \(name)") }
            .onDisappear { TraceLog.record(.screen, "Closed \(name)") }
    }
}

extension ProgramRoute {
    var traceName: String {
        switch self {
        case .newProgram: "New Program"
        case .detail(let program): "Program Detail, \(program.traceDescription)"
        case .session(let program): "Workout, \(program.nextWorkout?.traceDescription ?? "no workout")"
        case .completedWorkout(_, let workout): "Completed Workout, \(workout.traceDescription)"
        case .editDays(let program): "Edit Days, \(program.traceDescription)"
        }
    }
}
