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
    /// The training stores' files. Other stores on the device, like the tips store, change often and don't count.
    @ObservationIgnored private var trainingStores: Set<URL> = []

    private init() {
        Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                // The Data tab's search history lives in its own store and isn't training data.
                guard Self.counts(notification.object as? ModelContext) else { continue }
                self?.changed()
            }
        }
        Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                guard let self, self.counts(notification.userInfo?[NSPersistentStoreURLKey] as? URL) else { continue }
                self.changed()
            }
        }
    }

    /// Whether a save from this context changes training data.
    static func counts(_ context: ModelContext?) -> Bool {
        context?.container.schema.entities.contains { $0.name == "\(Workout.self)" } ?? true
    }

    /// Remembers a training store, so its iCloud imports count.
    func watch(_ container: ModelContainer) {
        trainingStores.formUnion(container.configurations.map { $0.url.resolvingSymlinksInPath() })
    }

    /// Whether an iCloud import into the store at this file changes training data.
    func counts(_ store: URL?) -> Bool {
        store.map { trainingStores.contains($0.resolvingSymlinksInPath()) } ?? false
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
    /// The value last built, whatever has changed since.
    var latest: Value? { value }

    func value(in context: ModelContext, key: AnyHashable = 0, build: () -> Value) -> Value {
        HistoryChanges.shared.watch(context.container)
        let stamp = AnyHashable([AnyHashable(HistoryChanges.shared.count), key])
        if let value, self.context === context, self.stamp == stamp { return value }
        let built = build()
        self.context = context
        self.stamp = stamp
        value = built
        return built
    }
}
