import Foundation
import SwiftData

@Model
final class GallerySearchPhrase {
    @Attribute(.unique) var key: String
    var text: String
    var lastUsed: Date?
    var planData: Data?
    var interpretedAt: Date?

    init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

@Model
final class GallerySearchVisit {
    var text: String
    var date: Date

    init(text: String, date: Date) {
        self.text = text
        self.date = date
    }
}

/// Recent searches and saved model plans, kept on this device only. A plan holds chart choices, never workout values.
@MainActor
final class GallerySearchJournal {
    static let shared = GallerySearchJournal()
    /// Saved plans are reused for 90 days, then asked again.
    static let lifetime: TimeInterval = 90 * 24 * 60 * 60
    /// Bump when `ChartSearchPlan` changes shape, so older plans are asked again.
    private static let planVersion = 5
    /// Searches and phrases kept. Older ones rotate out, so the store stays small.
    static let keptRows = 200

    let context: ModelContext?
    private var inFlight: [String: Task<ChartSearchPlan?, Never>] = [:]

    init(inMemory: Bool = false) {
        let schema = Schema([GallerySearchPhrase.self, GallerySearchVisit.self])
        let config = ModelConfiguration("GallerySearch", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        do {
            context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        } catch {
            TraceLog.recordNow(.data, "Search history store unavailable: " + TraceLog.describe(error))
            context = nil
        }
    }

    static func key(for input: String) -> String {
        input.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func record(_ input: String, at now: Date = .now) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.key(for: text)
        guard !key.isEmpty else { return }
        let phrase = entry(text, key: key)
        phrase.text = text
        phrase.lastUsed = now
        context?.insert(GallerySearchVisit(text: text, date: now))
        trim()
        save()
    }

    /// Up to three recent searches containing the input, newest first.
    func suggestions(for input: String) -> [String] {
        let key = Self.key(for: input)
        let predicate: Predicate<GallerySearchPhrase> = key.isEmpty
            ? #Predicate { $0.lastUsed != nil }
            : #Predicate { $0.lastUsed != nil && $0.key.contains(key) }
        var query = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.lastUsed, order: .reverse), SortDescriptor(\.key)])
        query.fetchLimit = 3
        return (try? context?.fetch(query).map(\.text)) ?? []
    }

    /// A saved plan that is still fresh.
    func cachedPlan(_ input: String, now: Date = .now) -> ChartSearchPlan? {
        guard let saved = saved(input), now.timeIntervalSince(saved.date) < Self.lifetime else { return nil }
        return saved.plan
    }

    /// A fresh saved plan, or a new one from `generate`. Concurrent requests share one model call.
    /// If generating fails, an expired plan is better than none.
    func resolve(_ input: String, now: Date = .now,
                 generate: @escaping @MainActor () async throws -> ChartSearchPlan) async -> ChartSearchPlan? {
        let key = Self.key(for: input)
        guard !key.isEmpty else { return nil }
        let previous = saved(input)
        if let previous, now.timeIntervalSince(previous.date) < Self.lifetime { return previous.plan }
        if let task = inFlight[key] { return await task.value }
        let task = Task { @MainActor in
            defer { inFlight[key] = nil }
            guard let plan = try? await generate(),
                  let data = try? JSONEncoder().encode(SavedPlan(version: Self.planVersion, plan: plan))
            else { return previous?.plan }
            let phrase = entry(input, key: key)
            phrase.planData = data
            phrase.interpretedAt = now
            trim()
            save()
            return plan
        }
        inFlight[key] = task
        return await task.value
    }

    private struct SavedPlan: Codable {
        let version: Int
        let plan: ChartSearchPlan
    }

    private func saved(_ input: String) -> (plan: ChartSearchPlan, date: Date)? {
        guard let row = phrase(Self.key(for: input)), let date = row.interpretedAt, let data = row.planData,
              let saved = try? JSONDecoder().decode(SavedPlan.self, from: data), saved.version == Self.planVersion
        else { return nil }
        return (saved.plan, date)
    }

    private func phrase(_ key: String) -> GallerySearchPhrase? {
        var query = FetchDescriptor<GallerySearchPhrase>(predicate: #Predicate { $0.key == key })
        query.fetchLimit = 1
        return try? context?.fetch(query).first
    }

    private func entry(_ input: String, key: String) -> GallerySearchPhrase {
        if let existing = phrase(key) { return existing }
        let new = GallerySearchPhrase(key: key, text: input)
        context?.insert(new)
        return new
    }

    /// Deletes all but the newest `keptRows` visits and phrases. A phrase counts from when it was last searched
    /// or interpreted, whichever is later, so an old saved plan goes with it. Sorted here, so unsaved rows count.
    private func trim() {
        guard let context else { return }
        let visits = (try? context.fetch(FetchDescriptor<GallerySearchVisit>())) ?? []
        for visit in visits.sorted(by: { $0.date > $1.date }).dropFirst(Self.keptRows) {
            context.delete(visit)
        }
        func latest(_ phrase: GallerySearchPhrase) -> Date {
            max(phrase.lastUsed ?? .distantPast, phrase.interpretedAt ?? .distantPast)
        }
        let phrases = (try? context.fetch(FetchDescriptor<GallerySearchPhrase>())) ?? []
        for phrase in phrases.sorted(by: { latest($0) > latest($1) }).dropFirst(Self.keptRows) {
            context.delete(phrase)
        }
    }

    private func save() {
        do { try context?.save() } catch {
            context?.rollback()
            TraceLog.recordNow(.data, "Search history save failed: " + TraceLog.describe(error))
        }
    }
}
