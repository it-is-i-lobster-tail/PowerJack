import CoreData
import Foundation
import SwiftData

/// Counts saved changes to the training data, from this device or from iCloud.
/// Screens that summarize all history rebuild when the count moves, not on every redraw.
@MainActor @Observable
final class HistoryChanges {
    static let shared = HistoryChanges()

    /// A burst of saves, like an iCloud import or a workout's watch messages, counts once.
    static let settle = Duration.milliseconds(300)

    private(set) var count = 0
    @ObservationIgnored private var pending: Task<Void, Never>?

    private init() {
        Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                // The Data tab's search history lives in its own store and isn't training data.
                guard Self.holdsTraining(notification.object as? ModelContext) else { continue }
                self?.changed()
            }
        }
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                self?.changed()
            }
        }
    }

    private static func holdsTraining(_ context: ModelContext?) -> Bool {
        context?.container.schema.entities.contains { $0.name == "\(Workout.self)" } ?? true
    }

    private func changed() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard (try? await Task.sleep(for: Self.settle)) != nil else { return }
            self?.count += 1
        }
    }
}

/// One summary of the training history, kept until the next saved change.
@MainActor
final class HistoryCache<Value> {
    private weak var context: ModelContext?
    private var stamp: AnyHashable?
    private var value: Value?

    /// The kept value, or a new one built when the data, the store or `key` changed since.
    func value(in context: ModelContext, key: AnyHashable = 0, build: () -> Value) -> Value {
        let stamp = AnyHashable([AnyHashable(HistoryChanges.shared.count), key])
        if let value, self.context === context, self.stamp == stamp { return value }
        let built = build()
        self.context = context
        self.stamp = stamp
        value = built
        return built
    }
}
