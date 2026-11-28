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
                guard Self.counts(Self.changed(in: notification)) else { continue }
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

    /// The training store's rows. Other stores, like the Data tab's search history or the tips
    /// store, save their own rows and don't count.
    private static let training = Set(PowerJackSchema.schema.entities.map(\.name))

    /// Whether a save that changed these rows changes training data.
    static func counts(_ changed: [PersistentIdentifier]) -> Bool {
        changed.contains { training.contains($0.entityName) }
    }

    /// The rows a save inserted, updated or deleted. Read from the notification, not its context,
    /// since the context's store may be closed by the time the notification is handled.
    private static func changed(in notification: Notification) -> [PersistentIdentifier] {
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        return keys.flatMap { notification.userInfo?[$0.rawValue] as? [PersistentIdentifier] ?? [] }
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
