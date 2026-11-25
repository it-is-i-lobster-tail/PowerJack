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

/// Search history belongs to this device. The cache holds intent, never workout values.
@MainActor
final class GallerySearchJournal {
    static let shared = GallerySearchJournal()
    static let lifetime: TimeInterval = 90 * 24 * 60 * 60
    let context: ModelContext?
    private var inFlight: [String: Task<StudyQueryPlan?, Never>] = [:]

    init(inMemory: Bool = false) {
        let schema = Schema([GallerySearchPhrase.self, GallerySearchVisit.self])
        let config = ModelConfiguration("GallerySearch", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            context = ModelContext(container)
        } catch {
            TraceLog.recordNow(.data, "Search history store unavailable: " + TraceLog.describe(error))
            context = nil
        }
    }

    static func key(for input: String) -> String {
        input.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
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

    private func save() {
        do { try context?.save() }
        catch { context?.rollback(); TraceLog.recordNow(.data, "Search history save failed: " + TraceLog.describe(error)) }
    }

    func record(_ input: String, at now: Date = .now) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.key(for: text)
        guard !key.isEmpty else { return }
        let phrase = entry(text, key: key)
        phrase.text = text
        phrase.lastUsed = now
        context?.insert(GallerySearchVisit(text: text, date: now))
        save()
    }

    func suggestions(for input: String) -> [String] {
        let key = Self.key(for: input)
        let predicate: Predicate<GallerySearchPhrase> = key.isEmpty
            ? #Predicate { $0.lastUsed != nil }
            : #Predicate { $0.lastUsed != nil && $0.key.contains(key) }
        var query = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.lastUsed, order: .reverse), SortDescriptor(\.key)])
        query.fetchLimit = 3
        return (try? context?.fetch(query).map(\.text)) ?? []
    }

    private struct CachedInterpretation: Codable {
        let version: Int
        let plan: StudyQueryPlan
    }

    func cached(_ input: String) -> (plan: StudyQueryPlan, date: Date)? {
        guard let row = phrase(Self.key(for: input)), let date = row.interpretedAt, let data = row.planData else { return nil }
        if let saved = try? JSONDecoder().decode(CachedInterpretation.self, from: data), saved.version == 2 {
            return (saved.plan, date)
        }
        // Keep legacy intents usable while refreshing their capability context.
        guard let legacy = try? JSONDecoder().decode(StudyQueryPlan.self, from: data) else { return nil }
        return (legacy, .distantPast)
    }

    func resolve(_ input: String, now: Date = .now,
                 generate: @escaping @MainActor (String) async throws -> StudyQueryPlan? = StudyQuestionInterpreter.interpret) async -> StudyQueryPlan? {
        let key = Self.key(for: input)
        guard !key.isEmpty else { return nil }
        let previous = cached(input)
        if let previous, now.timeIntervalSince(previous.date) < Self.lifetime { return previous.plan }
        if let task = inFlight[key] { return await task.value }
        let task = Task { @MainActor in
            defer { inFlight[key] = nil }
            guard let plan = try? await generate(input), let data = try? JSONEncoder().encode(CachedInterpretation(version: 2, plan: plan)) else { return previous?.plan }
            let phrase = entry(input, key: key)
            phrase.planData = data
            phrase.interpretedAt = now
            save()
            return plan
        }
        inFlight[key] = task
        return await task.value
    }
}
