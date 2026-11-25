// Opt-in longitudinal simulator benchmark. Each app instance receives only its own log and questions.
import CryptoKit
import Foundation
import FoundationModels
import Testing

@testable import PowerJack

#if DEBUG && targetEnvironment(simulator)
@MainActor struct WeeklySearchTrialTests {
    private struct LoggedSet: Decodable {
        let week, slot, number, reps, minutes, completed: Int
        let date, visit, exercise, muscle, setType: String
        let pounds: Double?
    }
    private struct Query: Decodable {
        let id, query: String
        let week: Int
    }
    private struct Input: Decodable {
        let lifter: String
        let trial: Int
        let log: [LoggedSet]
        let asOf: [String]
        let queries: [Query]
    }
    private func records(_ input: Input, calendar: Calendar) throws -> [[HistoryRecord]] {
        let program = UUID(), batch = UUID()
        let entries = Dictionary(grouping: ExerciseCatalog.entries, by: \.name)
        var batches = Array(repeating: [HistoryRecord](), count: 52)
        for (index, set) in input.log.enumerated() {
            let parts = set.date.split(separator: "-").compactMap { Int($0) }
            let start = try #require(calendar.date(from: .init(year: parts[0], month: parts[1], day: parts[2], hour: 12)))
            let entry = try #require(entries[set.exercise]?.first, "Unknown catalog lift: \(set.exercise)")
            var row = HistoryRow(programID: program)
            row.programName = "Trial lifter \(input.lifter)"
            row.programWeeks = 52
            row.programStatus = .inProgress
            row.week = set.week
            row.day = parts[1] * 100 + parts[2]
            row.workoutStarted = start
            row.workoutEnded = start.addingTimeInterval(Double(set.minutes * 60))
            row.workoutSeconds = Double(set.minutes * 60)
            row.workoutStatus = "Complete"
            row.exerciseNumber = set.slot
            row.exerciseKey = entry.id
            row.exerciseName = entry.name
            row.primaryMuscle = entry.primaryMuscle.rawValue
            row.equipment = entry.equipment.displayName
            row.exerciseSource = "Catalog"
            row.exerciseStatus = "Complete"
            row.setType = set.setType
            row.setNumber = set.number
            row.setStatus = set.completed == 1 ? "Complete" : "Skipped"
            row.reps = set.reps
            row.weightTenthsPounds = set.pounds.map { Int(($0 * 10).rounded()) }
            batches[set.week - 1].append(HistoryRecord(row, batchID: batch, savedAt: start, programStarted: nil, order: index))
        }
        return batches
    }
    // Keep all visible rows. Identical cards frequently occur for different searches in the same week.
    private func saveEvidence(_ card: GalleryCard, in directory: URL, known: inout Set<String>) throws -> String? {
        guard let source = card.source else { return nil }
        let c = source.presented(as: card.options.presentation, transpose: card.options.transpose)
        let evidence: [String: Any] = [
            "id": c.id.rawValue, "title": c.displayTitle, "scope": c.scope, "summary": c.summary,
            "reason": c.figure == nil ? c.emptyReason : "", "hasFigure": c.figure != nil, "related": card.related,
            "columns": c.plottedValues?.columns ?? [], "rows": c.plottedValues?.rows ?? [],
            "detailColumns": c.detail?.columns ?? [], "detailRows": c.detail?.rows ?? [],
            "example": c.readingExample ?? ""
        ]
        let data = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if known.insert(key).inserted {
            try data.write(to: directory.appendingPathComponent(key + ".json"), options: .atomic)
        }
        return key
    }
    @Test func runTrial() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["PJ_WEEKLY_TOKEN"] else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pj-weekly-" + token)
        let files = FileManager.default
        let cardsDir = root.appendingPathComponent("cards")
        try files.createDirectory(at: cardsDir, withIntermediateDirectories: true)
        print("PJ WEEKLY READY " + root.path)
        let file = root.appendingPathComponent("input.json")
        for _ in 0..<600 where !files.fileExists(atPath: file.path) { try await Task.sleep(for: .milliseconds(250)) }
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: file))
        let available = SystemLanguageModel.default.availability == .available
        print("PJ WEEKLY MODEL \(available)")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let batches = try records(input, calendar: calendar)
        let exercises = ExerciseCatalog.entries.map { $0.makeExercise() }
        let index = ExerciseChartSearch.Index(exercises.map(ExerciseChartSearch.Document.init))
        let saved = SavedStudyViews(data: Data())
        // Each full trial host has its own app sandbox. A process retry keeps its 90-day cache.
        let isolatedStore = Bundle.main.bundleIdentifier?.contains(".searchtrial") == true
        let journal = GallerySearchJournal(inMemory: !isolatedStore)
        _ = try #require(journal.context, "Search journal unavailable")
        let grouped = Dictionary(grouping: input.queries, by: \.week)
        var archive = [HistoryRecord](), known = Set<String>()
        let output = root.appendingPathComponent("results.jsonl")
        files.createFile(atPath: output.path, contents: nil)
        let stream = try FileHandle(forWritingTo: output)
        defer { try? stream.close() }
        let lastWeek = try #require(grouped.keys.max())
        for week in 1...lastWeek {
            archive += batches[week - 1]
            guard let questions = grouped[week] else { continue }
            let parts = input.asOf[week - 1].split(separator: "-").compactMap { Int($0) }
            let today = try #require(calendar.date(from: .init(year: parts[0], month: parts[1], day: parts[2], hour: 23, minute: 59)))
            let history = StudyHistory(programs: [], archive: archive, logs: [], unit: .pounds, today: today, calendar: calendar)
            for (offset, question) in questions.enumerated() {
                let q = question.query
                journal.record(q, at: today)
                let search = StudySearch(query: q, history: history, exercises: exercises, index: index)
                let parsed = LoggedStudyQuestion(q, history: history, knownNames: search.knownExerciseNames)
                let local = search.galleryCards(history: history, saved: saved, parsed: parsed)
                var cards = local, route = "local", calls = [String]()
                if StudySearch.needsToolReview(local, parsed: parsed, history: history) {
                    let context = StudySearchTools(search: search, history: history, exercises: exercises, saved: saved, parsed: parsed)
                    let cached = journal.cached(q)
                    let fresh = cached.map { today.timeIntervalSince($0.date) < GallerySearchJournal.lifetime } ?? false
                    var interpreted = false
                    let plan = await journal.resolve(q, now: today) { requested in
                        let generated = try await StudyQuestionInterpreter.interpret(requested, context: context)
                        interpreted = generated != nil
                        return generated
                    }
                    if fresh { route = "cache" }
                    else if interpreted { route = "model" }
                    else if plan != nil { route = "stale-cache" }
                    else { route = available ? "model-fallback" : "unavailable" }
                    calls = context.calls
                    if let plan {
                        cards = search.questionCards(plan, query: q, history: history, exercises: exercises, saved: saved, parsed: parsed)
                    }
                }
                let refs = try cards.prefix(4).map {
                    try #require(try saveEvidence($0, in: cardsDir, known: &known), "Displayed card missing source")
                }
                let row: [String: Any] = ["id": question.id, "week": week, "lifter": input.lifter,
                    "query": q, "refs": refs, "route": route, "toolCalls": calls, "modelAvailable": available,
                    "asOf": input.asOf[week - 1], "notice": parsed.missingHistoryNote(history) ?? ""]
                var data = try JSONSerialization.data(withJSONObject: row)
                data.append(10)
                try stream.write(contentsOf: data)
                if offset % 25 == 0 { print("PJ WEEKLY STEP \(input.lifter) \(week) \(offset + 1)") }
            }
            try stream.synchronize()
            print("PJ WEEKLY FINISHED WEEK \(week)")
        }
    }
}
#endif
