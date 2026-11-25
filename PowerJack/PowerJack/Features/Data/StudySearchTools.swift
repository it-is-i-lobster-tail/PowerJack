import Foundation
import FoundationModels

/// Optional catalog terminology learned offline. The bundle contains phrases and supported IDs only.
/// A suggestion can guide the model to a catalog entry. All displays still use the recorded log.
struct StudyCatalogLanguage: Decodable {
  enum ContextDetail: String, Decodable { case terminology, filters, evidence }
  struct Entry: Decodable {
    var phrase: String
    var metric: ScopedChartMetric
  }
  var detail: ContextDetail
  var entries: [Entry]

  static func read(_ data: Data?) -> Self? {
    guard let data, data.count <= 32_768, let language = try? JSONDecoder().decode(Self.self, from: data),
      language.entries.count <= 96,
      language.entries.allSatisfy({ entry in
        let words = entry.phrase.split(separator: " ")
        return (2...5).contains(words.count) && entry.phrase.count <= 72
          && entry.phrase.allSatisfy { $0 == " " || ($0.isASCII && $0.isLowercase && $0.isLetter) }
      }) else { return nil }
    return language
  }

  static let bundled: Self? = {
    let url = Bundle.main.url(forResource: "StudyCatalogLanguage", withExtension: "json")
    return read(url.flatMap { try? Data(contentsOf: $0) })
  }()

  func suggestions(for text: String) -> [ScopedChartMetric] {
    let query = " " + text.lowercased().split(whereSeparator: { !$0.isLetter }).joined(separator: " ") + " "
    let matches = entries.filter { query.contains(" " + $0.phrase + " ") }
    let grouped = Dictionary(grouping: matches, by: \.phrase)
    var seen = Set<ScopedChartMetric>()
    return matches.sorted { $0.phrase.count > $1.phrase.count }.compactMap { entry in
      guard grouped[entry.phrase]?.allSatisfy({ $0.metric == entry.metric }) == true,
            seen.insert(entry.metric).inserted else { return nil }
      return entry.metric
    }
  }
}

/// Each model request gets a read-only view of this search and its live log.
@MainActor
final class StudySearchTools {
  let search: StudySearch
  let history: StudyHistory
  let exercises: [Exercise]
  let saved: SavedStudyViews
  let parsed: StudyQuestion
  let aggregate: StudyScopedChart?
  private(set) var calls = [String]()
  private(set) var prefetched = false

  init(
    search: StudySearch, history: StudyHistory, exercises: [Exercise], saved: SavedStudyViews,
    parsed: StudyQuestion
  ) {
    self.search = search
    self.history = history
    self.exercises = exercises
    self.saved = saved
    self.parsed = parsed
    aggregate = StudyScopedChart(parsed, history: history)
  }

  var registered: [any Tool] {
    [FindCharts(context: self), GetFilterOptions(context: self), PreviewChart(context: self)]
  }

  func discovery(using language: StudyCatalogLanguage? = StudyCatalogLanguage.bundled) -> String {
    let words = Set(parsed.text.split(separator: " ").map { StudySearch.term(String($0)) })
    let ordered = ChartMeasure.allCases.sorted {
      let a = $0.study.searchVocabulary.intersection(words).count
      let b = $1.study.searchVocabulary.intersection(words).count
      return a == b ? $0.study.rawValue < $1.study.rawValue : a > b
    }
    let matches = ordered.prefix(4).map { "\($0.rawValue): \($0.study.searchMetadata.measure)" }
    let scoped =
      aggregate.map { a in
        "Verified scoped aggregate: configuredMetric=\(a.metric.rawValue); chart=\(ChartMeasure.allCases.first { c in c.study == a.metric.study }?.rawValue ?? "")."
      } ?? "No verified scalar aggregate. Use supported chart filters or retain the local evidence."
    var context = scoped + " Catalog suggestions: " + matches.joined(separator: "; ")
    if let language {
      let ids = language.suggestions(for: parsed.textWithoutLiftNames).prefix(3).map(\.rawValue)
      if !ids.isEmpty { context += " Measures suggested by this phrasing: " + ids.joined(separator: ", ") + "." }
      switch language.detail {
      case .terminology: break
      case .filters:
        let subjects = parsed.liftNames.isEmpty ? "all training or requested muscle" : parsed.liftNames.joined(separator: ", ")
        context += " Requested subjects: " + subjects + ". Parsed time scope: " + parsed.periodLabel
          + ". Use getFilterOptions before choosing a chart whose population is uncertain."
      case .evidence:
        if let aggregate, let table = aggregate.result.plottedValues {
          context += " Verified aggregate columns: " + table.columns.joined(separator: ", ")
            + ". Visible group count: " + String(table.rows.count) + ". Use previewChart for the labeled rows."
        } else {
          context += " A scalar is unverified. Check previewChart for the requested measure and all groups."
        }
      }
    }
    return context
  }

  func prefetch() -> String {
    prefetched = true
    return discovery()
  }

  private enum ToolError: Error { case budgetExceeded }
  func record(_ call: String) throws {
    try Task.checkCancellation()
    guard calls.count < 5 else { throw ToolError.budgetExceeded }
    calls.append(call)
  }

  func options(_ id: String) -> String {
    if let a = aggregate, a.metric.rawValue == id {
      return
        "\(a.metric.label(history.unit.symbol)); each requested subject and period has its own row. \(a.result.scope)"
    }
    guard let measure = ChartMeasure(rawValue: id) else {
      return "Unknown chart ID. Call findCharts."
    }
    let study = measure.study
    let params = study.parameters.map { p, _ in "\(p.rawValue) (\(p.label(for:study)))" }
    let groupings = ChartGrouping.allCases.filter { $0.supports(study) }.map(\.rawValue)
    let subjects = parsed.liftNames.map { name in
      let present = history.sessions.contains {
        parsed.matchesLift($0, named: name) && parsed.includes($0.date) && !$0.done.isEmpty
      }
      return name + (present ? " (logged)" : " (no matching sets)")
    }
    return
      "\(id); parameters: \(params.joined(separator:", ")); grouping: \(groupings.joined(separator:", ")); named lifts: \(subjects.joined(separator:", ")); period: \(parsed.periodLabel); coverage: \(study.searchMetadata.coverage)"
  }

  func preview(
    id: String, lifts: [String], filters: String, timeframe: String, grouping: ChartGrouping
  ) -> String {
    let result: StudyResult
    if let a = aggregate, a.metric.rawValue == id {
      result = a.result
    } else {
      guard let measure = ChartMeasure(rawValue: id) else {
        return "No supported configuration for this ID."
      }
      let plan = StudyQueryPlan(
        exercises: lifts, filters: filters, wholeTraining: false, charts: [measure],
        grouping: grouping, timeframe: timeframe)
      let cards = search.modelCards(
        plan, query: parsed.original, history: history, exercises: exercises, saved: saved)
      guard let source = cards.first(where: { !$0.related && $0.id.study == measure.study })?.source
      else {
        return
          "No qualifying chart for that exercise, grouping and period. Preserve the original constraints."
      }
      result = source
    }
    let table = result.plottedValues ?? result.detail
    let sample =
      table?.rows.prefix(3).map { $0.prefix(5).joined(separator: " | ") }.joined(separator: "; ")
      ?? ""
    return String(
      "\(result.displayTitle); \(result.scope); columns: \(table?.columns.joined(separator:", ") ?? "none"); rows: \(table?.rows.count ?? 0); sample: \(sample)"
        .prefix(700))
  }
}

private struct FindCharts: Tool {
  let context: StudySearchTools
  let name = "findCharts"
  let description = "List chart IDs and any verified scoped aggregate for the current question."
  @Generable struct Arguments {}
  nonisolated func call(arguments: Arguments) async throws -> String {
    try await context.record(name)
    return await context.discovery()
  }
}
private struct GetFilterOptions: Tool {
  let context: StudySearchTools
  let name = "getFilterOptions"
  let description =
    "Read supported filters, grouping and logged exercise availability for a chart ID."
  @Generable struct Arguments { var chartID: String }
  nonisolated func call(arguments: Arguments) async throws -> String {
    try await context.record(name)
    return await context.options(arguments.chartID)
  }
}
private struct PreviewChart: Tool {
  let context: StudySearchTools
  let name = "previewChart"
  let description =
    "Inspect a proposed chart or scoped aggregate against the actual log before selecting it."
  @Generable struct Arguments {
    var chartID: String
    @Guide(description: "Explicitly named lifts, or empty.") var exercises: [String]
    @Guide(description: "Filter terms from the question only.") var filters: String
    @Guide(description: "Original time phrase, or empty.") var timeframe: String
    var grouping: ChartGrouping
  }
  nonisolated func call(arguments: Arguments) async throws -> String {
    try await context.record(name)
    return await context.preview(
      id: arguments.chartID, lifts: arguments.exercises, filters: arguments.filters,
      timeframe: arguments.timeframe, grouping: arguments.grouping)
  }
}

extension StudyQuestionInterpreter {
  static func interpret(_ query: String, context: StudySearchTools) async throws -> StudyQueryPlan? {
    try await interpret(query, available: SystemLanguageModel.default.availability == .available) {
      input in
      try await generate(input, tools: context.registered, discovery: context.prefetch())
    }
  }
}
