import Foundation
import Testing

@testable import PowerJack

@MainActor struct StudySearchToolTests {
  let history = StudyHistory(programs: [], archive: [], logs: [], unit: .pounds)
  let saved = SavedStudyViews(data: Data())

  private func context(_ text: String) -> StudySearchTools {
    let search = StudySearch(query: text, history: history, exercises: [], index: nil)
    let parsed = StudyQuestion(text, history: history, knownNames: search.knownExerciseNames)
    return StudySearchTools(
      search: search, history: history, exercises: [], saved: saved, parsed: parsed)
  }

  @Test func emptyCountAndUnobservedLoadStayDistinct() throws {
    let sets = context("How many working sets did I complete in October?")
    let loads = context("What was the highest weight I lifted in October?")
    #expect(try #require(sets.aggregate).result.plottedValues?.rows.first?[2] == "0")
    #expect(try #require(loads.aggregate).result.plottedValues?.rows.first?[2] == "—")
    #expect(sets.prefetch().contains("workingSets"))
    #expect(sets.prefetched && sets.calls.isEmpty)
  }

  @Test func inclusiveSetsUseCompletedWarmupsAndKeepAnAbsentLiftAtZero() throws {
    let date = Date(), program = UUID(), batch = UUID()
    var row = HistoryRow(programID: program)
    row.exerciseName = "Cable Curl"
    row.workoutStarted = date
    row.workoutStatus = "Complete"
    let records = [("Warmup", "Complete", 12), ("Working", "Complete", 7),
                   ("Warmup", "Skipped", 15)].enumerated().map { index, set in
      var r = row
      r.setType = set.0
      r.setStatus = set.1
      r.reps = set.2
      r.setNumber = index + 1
      return HistoryRecord(r, batchID: batch, savedAt: date, programStarted: nil, order: index)
    }
    let h = StudyHistory(programs: [], archive: records, logs: [], unit: .pounds, today: date)
    for (text, subject, expected) in [
      ("Count all my recorded sets for Cable Curl.", "Cable Curl", "2"),
      ("How many sets including warmups did I finish for Cable Curl?", "Cable Curl", "2"),
      ("Add up every repetition for Cable Curl.", "Cable Curl", "19"),
      ("Count all my recorded sets for Goblet Squat.", "Goblet Squat", "0")
    ] {
      let parsed = StudyQuestion(text, history: h, knownNames: [subject])
      let search = StudySearch(query: text, history: h, exercises: [], index: nil)
      let result = try #require(search.galleryCards(history: h, saved: saved, parsed: parsed).first?.source)
      #expect(result.plottedValues?.rows.first?[0] == subject)
      #expect(result.plottedValues?.rows.first?[2] == expected)
      #expect(result.scope.contains("Including warmups"))
    }
    #expect(!StudyQuestion("Count every rep excluding warmups.", history: h).includesWarmups)
    #expect(!StudyQuestion("Count every rep from working sets.", history: h).includesWarmups)
    #expect(StudyQuestion("Which set used 32.5 pounds?", history: h).text.contains("32.5"))
  }

  @Test func certifiedFiltersAndPairedZerosReachTheGalleryWithoutAModel() throws {
    for (query, label, subjects) in [
      ("Compare working sets of Cable Curl and Goblet Squat in May.", "Working sets", 2),
      ("Count my working sets of exactly 11 reps in May.", "exactly 11 reps", 1),
      ("How many workouts did I finish on Tuesdays in May?", "Tuesday", 1)
    ] {
      let tools = context(query)
      let cards = tools.search.galleryCards(history: history, saved: saved, parsed: tools.parsed)
      let first = try #require(cards.first)
      #expect(first.answersVerifiedScope)
      #expect(first.source?.displayTitle.contains(label) == true)
      #expect(first.source?.plottedValues?.rows.map { $0[2] } == Array(repeating: "0", count: subjects))
      #expect(!StudySearch.needsToolReview(cards, parsed: tools.parsed, history: history))
    }
    for q in ["How many workouts did I complete without Cable Curl?",
              "Show my working sets per month.", "How many reps did I do before surgery?"] {
      #expect(!StudyScopedChart.canAnswerDirectly(context(q).parsed))
    }
  }

  @Test func verifiedAggregatesSeparateNonemptyPopulationsAcrossDatesAndLifts() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    let program = UUID(), batch = UUID()
    let sessions = [(date(2025, 12, 30), 5, [11]), (date(2026, 1, 5), 10, [11, 5]),
                    (date(2026, 1, 6), 20, [4])]
    var entries = [HistoryRecord]()
    for (session, values) in sessions.enumerated() {
      for (index, reps) in values.2.enumerated() {
        var row = HistoryRow(programID: program)
        row.day = session + 1
        row.workoutStarted = values.0
        row.workoutEnded = values.0.addingTimeInterval(Double(values.1 * 60))
        row.workoutSeconds = Double(values.1 * 60)
        row.workoutStatus = "Complete"
        row.exerciseName = "Cable Curl"
        row.exerciseKey = "test-cable-curl"
        row.equipment = Equipment.cable.displayName
        row.setType = "Working"
        row.setStatus = "Complete"
        row.setNumber = index + 1
        row.reps = reps
        row.weightTenthsPounds = 100
        entries.append(HistoryRecord(row, batchID: batch, savedAt: values.0,
                                     programStarted: nil, order: entries.count))
      }
    }
    let h = StudyHistory(programs: [], archive: entries, logs: [], unit: .pounds,
                         today: date(2026, 1, 7), calendar: calendar)
    for (text, totals) in [
      ("Compare reps for Cable Curl and Goblet Squat in January.", ["20", "0"]),
      ("Count Cable Curl working sets of exactly 11 reps in January.", ["1"]),
      ("How many workouts did I finish on Tuesdays in January?", ["1"]),
      ("Across the full year, how many total minutes are recorded for completed workouts?", ["30"]),
      ("Calculate sets times reps times weight for Cable Curl in January.", ["200"])
    ] {
      let q = StudyQuestion(text, history: h, knownNames: ["Cable Curl", "Goblet Squat"])
      let search = StudySearch(query: text, history: h, exercises: [], index: nil)
      let first = try #require(search.galleryCards(history: h, saved: saved, parsed: q).first)
      #expect(first.answersVerifiedScope, "\(text)")
      let rows = try #require(first.source?.plottedValues?.rows)
      #expect(rows.map { $0[2] }.sorted() == totals.sorted(), "\(text)")
      if totals.count == 2 {
        #expect(Dictionary(uniqueKeysWithValues: rows.map { ($0[0], $0[2]) })
                == ["Cable Curl": "20", "Goblet Squat": "0"])
      }
    }
  }

  @Test func previewsRejectUnknownChartsAndInventedDates() {
    let tools = context("How much did I bench in October?")
    #expect(tools.options("unknown").contains("Unknown"))
    #expect(
      tools.preview(id: "unknown", lifts: [], filters: "", timeframe: "", grouping: .unspecified)
        .contains("No supported configuration"))
    #expect(
      tools.preview(
        id: ChartMeasure.estimatedStrengthTrend.rawValue, lifts: ["bench"],
        filters: "", timeframe: "August", grouping: .unspecified
      ).contains("No qualifying chart"))
  }

  @Test func catalogLanguageAcceptsOnlySupportedUnambiguousWholePhrases() throws {
    let data = Data(#"{"detail":"terminology","entries":[{"phrase":"weight moved","metric":"volumeLoad"},{"phrase":"large total","metric":"volumeLoad"},{"phrase":"large total","metric":"totalReps"}]}"#.utf8)
    let catalog = try #require(StudyCatalogLanguage.read(data))
    #expect(catalog.suggestions(for: "WEIGHT moved?") == [.volumeLoad])
    let tools = context("Show my weight moved in March.")
    #expect(tools.discovery(using: catalog).contains("Measures suggested by this phrasing: volumeLoad"))
    #expect(!tools.discovery(using: nil).contains("Measures suggested by this phrasing"))
    let scoped = StudyCatalogLanguage(detail: .filters, entries: catalog.entries)
    #expect(tools.discovery(using: scoped).contains(tools.parsed.periodLabel))
    #expect(catalog.suggestions(for: "bodyweight moved").isEmpty)
    #expect(catalog.suggestions(for: "large total").isEmpty)
    #expect(StudyCatalogLanguage.read(Data(#"{"detail":"filters","entries":[{"phrase":"weight moved","metric":"madeUp"}]}"#.utf8)) == nil)
    #expect(StudyCatalogLanguage.read(nil) == nil)
  }

  @Test func callLimitIsPerRequest() throws {
    let tools = context("Compare total working sets for June and September.")
    for _ in 0..<5 { try tools.record("findCharts") }
    #expect(throws: (any Error).self) { try tools.record("previewChart") }
    #expect(tools.calls.count == 5)
    #expect(context("How many working sets have I logged?").calls.isEmpty)
  }

  @Test func comparisonPreservesBothPeriodsAndRejectsWrongMetric() throws {
    let text = "Compare total working sets for June and September."
    let tools = context(text)
    let local = tools.search.galleryCards(history: history, saved: saved, parsed: tools.parsed)
    #expect(!StudySearch.needsToolReview(local, parsed: tools.parsed, history: history))
    var plan = StudyQueryPlan(exercises: [], filters: "", wholeTraining: true, charts: [])
    plan.configuredMetric = .workingSets
    let cards = tools.search.questionCards(
      plan, query: text, history: history, exercises: [], saved: saved)
    let scope = try #require(cards.first?.source?.scope)
    #expect(scope.contains("June") && scope.contains("September"))
    let rows = try #require(cards.first?.source?.plottedValues?.rows)
    #expect(rows.count == 2 && rows[0][1] != rows[1][1])
    #expect(rows.map { $0[2] } == ["0", "0"])
    plan.configuredMetric = .maximumLoad
    let rejected = tools.search.questionCards(
      plan, query: text, history: history, exercises: [], saved: saved)
    #expect(rejected.first?.source?.displayTitle != "Maximum load (lb)")
  }
}
