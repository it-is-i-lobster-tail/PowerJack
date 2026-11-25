// Opt-in paired device benchmark. PJ_TOOL_QUESTIONS is a JSON array of held-out questions.
import Foundation
import FoundationModels
import SwiftData
import Testing

@testable import PowerJack

#if DEBUG && targetEnvironment(simulator)
  @MainActor struct ChartToolBenchmarkTests {
    @Test func capture() async throws {
      let env = ProcessInfo.processInfo.environment
      guard let data = env["PJ_TOOL_QUESTIONS"]?.data(using: .utf8) else { return }
      let inputs = try JSONDecoder().decode([String].self, from: data)
      let start = Int(env["PJ_TOOL_START"] ?? "1") ?? 1
      let end = Int(env["PJ_TOOL_END"] ?? String(inputs.count)) ?? inputs.count
      let arm = env["PJ_TOOL_ARM"] ?? "tools"
      let replay = try env["PJ_TOOL_REPLAY"].map {
        try JSONDecoder().decode([StudyQuestion?].self, from: Data($0.utf8))
      }
      if let replay {
        try #require(replay.count == inputs.count)
      } else {
        try #require(SystemLanguageModel.default.availability == .available)
      }
      let store = PowerJackStore(inMemory: true)
      let ctx = store.container.mainContext
      let date = try #require(
        Calendar.current.date(from: .init(year: 2026, month: 11, day: 25, hour: 10)))
      try SimulatorTrainingHistory.populate(in: ctx, now: date)
      let exercises = try ctx.fetch(FetchDescriptor<Exercise>())
      let programs = try ctx.fetch(FetchDescriptor<Program>())
      let archive = try HistoryArchive.records(in: ctx)
      let history = StudyHistory(
        programs: programs, archive: archive, logs: try ctx.fetch(FetchDescriptor<WorkoutLog>()),
        unit: .pounds, today: date)
      let index = ExerciseChartSearch.Index(exercises.map(ExerciseChartSearch.Document.init))
      let saved = SavedStudyViews(data: Data())
      let dir = FileManager.default.temporaryDirectory
      let csv = dir.appendingPathComponent("live-workouts.csv")
      try HistoryExport.csv(for: programs, saved: archive, unit: .pounds).write(
        to: csv, atomically: true, encoding: .utf8)
      print("LIVE LOG", csv.path)
      func evidence(_ cards: [GalleryCard]) -> [[String: Any]] {
        cards.prefix(4).compactMap { card in
          guard let source = card.source else { return nil }
          let c = source.presented(as: card.options.presentation, transpose: card.options.transpose)
          return [
            "id": c.id.rawValue, "related": card.related, "title": c.displayTitle, "scope": c.scope,
            "summary": c.summary, "example": c.readingExample ?? "",
            "reason": c.figure == nil ? c.emptyReason : "", "hasFigure": c.figure != nil,
            "columns": c.plottedValues?.columns ?? [], "rows": c.plottedValues?.rows ?? [],
            "detailColumns": c.detail?.columns ?? [], "detailRows": c.detail?.rows ?? [],
          ]
        }
      }
      print("LIVE DEVICE AVAILABILITY", SystemLanguageModel.default.availability)
      let folder = dir.appendingPathComponent("tool-audit-" + arm + "-" + String(start))
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      print("TOOL AUDIT DIR", folder.path)
      let selected = env["PJ_TOOL_IDS"].map { Set($0.split(separator: ",").compactMap { Int($0) }) }
      for id in start...end where selected?.contains(id) != false {
        let q = inputs[id - 1]
        let search = StudySearch(query: q, history: history, exercises: exercises, index: index)
        let parsed = LoggedStudyQuestion(q, history: history, knownNames: search.knownExerciseNames)
        let local = search.galleryCards(history: history, saved: saved, parsed: parsed)
        let routed = StudySearch.needsToolReview(local, parsed: parsed, history: history)
        let context = StudySearchTools(
          search: search, history: history, exercises: exercises, saved: saved, parsed: parsed)
        let began = Date()
        var plan: StudyQuestion?
        if let replay {
          plan = replay[id - 1]
        } else if routed {
          if arm == "tools" {
            plan = try await StudyQuestionInterpreter.interpret(q, context: context)
          } else if arm == "context" {
            plan = try await StudyQuestionInterpreter.interpret(q, available: true) { input in
              try await StudyQuestionInterpreter.generate(input, tools: [], discovery: context.prefetch())
            }
          } else {
            plan = try await StudyQuestionInterpreter.interpret(q)
          }
        }
        let results =
          plan.map {
            search.questionCards(
              $0, query: q, history: history, exercises: exercises, saved: saved, parsed: parsed)
          } ?? local
        var row: [String: Any] = [
          "id": id, "query": q, "routed": routed,
          "wasFocused": local.count == 1 && local.first?.source?.question != nil,
          "notice": parsed.missingHistoryNote(history) ?? "", "cards": evidence(results),
          "local": evidence(local),
          "prefetched": context.prefetched, "toolCalls": context.calls,
          "seconds": Date().timeIntervalSince(began),
        ]
        if let plan {
          row["plan"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan))
        }
        try JSONSerialization.data(withJSONObject: row, options: .sortedKeys)
          .write(
            to: folder.appendingPathComponent(String(format: "%03d.json", id)), options: .atomic)
        print("AUDIT STEP", arm, id, routed, context.calls, plan != nil)
      }
    }
  }
#endif
