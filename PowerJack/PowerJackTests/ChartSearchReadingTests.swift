import Foundation
import SwiftData
import Testing

@testable import PowerJack

/// How Data search reads what a lifter types: which lifts or muscles, which dates and weights,
/// which chart leads, and whether a number is asked for. Each row is one search.
@MainActor
struct ChartSearchReadingTests {
    /// What a search should read. Nil means "not checked".
    struct Reading: CustomTestStringConvertible, Sendable {
        enum Period: Sendable {
            case noPeriod
            /// First and last day, as "yyyy-mm-dd".
            case days(String, String)
            /// The calendar week, this one (0) or last (-1).
            case week(Int)
        }

        enum Answer: Sendable {
            case noAnswer, any
            /// The answer's summary contains each of these.
            case says([String])
        }

        let text: String
        var lifts: [String]?
        var unlogged: String?
        var muscles: [Muscle]?
        var period: Period?
        var pounds: Double?
        var top: TrainingStudy?
        var answer: Answer?
        var note: String?

        var testDescription: String { text }
    }

    static let sampleReadings: [Reading] = [
        // Typos, joined words and half-typed words.
        Reading(text: "burpies", lifts: [], unlogged: "Burpee"),
        Reading(text: "benhc progress", lifts: ["Barbell Bench Press"], top: .legMax),
        Reading(text: "stregth", top: .legMax),
        Reading(text: "bench prog", lifts: ["Barbell Bench Press"], top: .legMax),
        Reading(text: "pushups", lifts: ["Push Up"]),
        Reading(text: "pullups", lifts: [], unlogged: "Pull Up"),
        // Every word counts.
        Reading(text: "incline bench", lifts: [], unlogged: "Incline Bench Press"),
        Reading(text: "db row", lifts: [], unlogged: "Dumbbell Row"),
        Reading(text: "flat barbell bench press", lifts: ["Barbell Bench Press"]),
        Reading(text: "push", lifts: [], muscles: [.chest, .shoulders, .triceps]),
        Reading(text: "push day", lifts: [], muscles: [.chest, .shoulders, .triceps]),
        Reading(text: "pull day", lifts: [], muscles: [.back, .biceps]),
        Reading(text: "legs", lifts: [], muscles: StudyHistory.legs),
        Reading(text: "back day", lifts: [], muscles: [.back]),
        Reading(text: "push ups", lifts: ["Push Up"]),
        Reading(text: "rear delts", lifts: [], muscles: [.shoulders],
                note: "No logged lifts work the rear delt, so these charts show all shoulder work."),
        Reading(text: "squat records", lifts: ["Barbell Back Squat", "Goblet Squat"],
                answer: .says(["Barbell Back Squat: ", "Goblet Squat: "])),
        // Dates as people say them.
        Reading(text: "bench this week", lifts: ["Barbell Bench Press"], period: .week(0)),
        Reading(text: "how many sets did i do last week", period: .week(-1), answer: .any),
        Reading(text: "squat last 3 months", period: .days("2026-08-26", "2026-11-25")),
        Reading(text: "past 10 days", period: .days("2026-11-16", "2026-11-25")),
        Reading(text: "bench since september", period: .days("2026-09-01", "2026-11-25")),
        Reading(text: "squats between may and july", period: .days("2026-05-01", "2026-07-31")),
        Reading(text: "bench 2025 vs 2026", lifts: ["Barbell Bench Press"], period: .days("2025-01-01", "2026-12-31"),
                answer: .noAnswer),
        Reading(text: "how many sets of bench 2025 vs 2026", answer: .says(["2025: ", "2026: "])),
        Reading(text: "bench 225", lifts: ["Barbell Bench Press"], pounds: 225),
        Reading(text: "225 bench", lifts: ["Barbell Bench Press"], pounds: 225),
        Reading(text: "bench 5", lifts: ["Barbell Bench Press"], pounds: nil, answer: .noAnswer),
        Reading(text: "bench", period: .noPeriod),
        // Numbers only when asked.
        Reading(text: "is my bench going up", answer: .noAnswer),
        Reading(text: "best bench", answer: .says(["Barbell Bench Press: "])),
        Reading(text: "bench pb", top: .records, answer: .any),
        Reading(text: "when did i last squat", answer: .says(["days ago"])),
        Reading(text: "how often do i bench", answer: .says(["Barbell Bench Press: "])),
        // The chart that answers first.
        Reading(text: "squat vs deadlift", top: .relationship),
        Reading(text: "compare bench and squat", top: .relationship),
        Reading(text: "last workout", top: .sessionLedger),
        Reading(text: "bench 1rm", top: .legMax),
    ]

    /// Lifts logged in FitNotes under their own names.
    static let fitNotesReadings: [Reading] = [
        Reading(text: "shoulder 7s", lifts: ["Dumbbell Lateral Raise"]),
        Reading(text: "narrow bar bell bench", lifts: ["Close Grip Bench Press"]),
        Reading(text: "narrow bench", lifts: ["Close Grip Bench Press"]),
        Reading(text: "hex bar dead lift", lifts: ["Trap Bar Deadlift"]),
        Reading(text: "pull ups forward grip", lifts: ["Pull Up"]),
        Reading(text: "burpies", lifts: ["Burpee"]),
        Reading(text: "back fly", lifts: ["Dumbbell Reverse Fly"]),
        Reading(text: "fly", lifts: ["Cable Chest Fly", "Dumbbell Reverse Fly"]),
        Reading(text: "squat records", lifts: ["Barbell Back Squat", "Dumbbell Goblet Squat"],
                answer: .says(["Barbell Back Squat: 245", "Dumbbell Goblet Squat: 50"])),
        Reading(text: "front squat", lifts: ["Barbell Front Squat"]),
        // An own lift with joints set by hand counts for the joint words it works.
        Reading(text: "rear delts", lifts: ["Band Pull Apart", "Dumbbell Reverse Fly"], muscles: []),
    ]

    @Test("Searches on a year of sample training read as meant", arguments: sampleReadings)
    func sample(_ reading: Reading) {
        check(reading, in: ChartSearchSampleHistoryTests.history)
    }

    @Test("Searches for lifts logged under FitNotes names read as meant", arguments: fitNotesReadings)
    func fitNotes(_ reading: Reading) throws {
        check(reading, in: try Self.fitNotesHistory())
    }

    private func check(_ reading: Reading, in history: StudyHistory) {
        let query = ChartQuery(reading.text, history: history)
        let results = ChartSearch.results(for: query, history: history, saved: SavedStudyViews(data: Data()))
        let text = reading.text
        if let lifts = reading.lifts {
            #expect(Set(query.exerciseKeys.map(history.exerciseName)) == Set(lifts), "\(text): \(query.lifts)")
        }
        if let unlogged = reading.unlogged {
            #expect(query.unloggedLifts == [unlogged], "\(text)")
        }
        if let muscles = reading.muscles {
            #expect(Set(query.muscles) == Set(muscles), "\(text): \(query.muscleGroups.map(\.name))")
        }
        if let period = reading.period {
            #expect(Self.days(query.period, history) == Self.expected(period, history), "\(text): \(String(describing: query.period))")
        }
        if reading.lifts != nil || reading.pounds != nil {
            #expect(query.parameters[.load] == reading.pounds.map { history.unit.tenthsPounds(from: $0) }, "\(text)")
        }
        if let top = reading.top {
            #expect(results.cards.first?.id.study == top, "\(text): \(results.cards.prefix(3).map(\.id.study))")
        }
        switch reading.answer {
        case nil: break
        case .noAnswer: #expect(results.answer == nil, "\(text): \(results.answer?.result.summary ?? "")")
        case .any: #expect(results.answer != nil, "\(text)")
        case .says(let parts):
            let summary = results.answer?.result.summary ?? ""
            for part in parts { #expect(summary.contains(part), "\(text): \(summary)") }
        }
        if let note = reading.note {
            #expect(results.note == note, "\(text)")
        }
    }

    private static func days(_ period: StudyPeriod?, _ history: StudyHistory) -> String? {
        guard let interval = period?.interval(in: history.calendar) else { return nil }
        let style = Date.ISO8601FormatStyle(timeZone: history.calendar.timeZone).year().month().day()
        let last = history.calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return interval.start.formatted(style) + "..." + last.formatted(style)
    }

    private static func expected(_ period: Reading.Period, _ history: StudyHistory) -> String? {
        switch period {
        case .noPeriod: return nil
        case let .days(first, last): return first + "..." + last
        case .week(let offset):
            let date = history.calendar.date(byAdding: .day, value: 7 * offset, to: history.today)!
            let week = history.calendar.dateInterval(of: .weekOfYear, for: date)!
            return days(.range(start: week.start, end: week.end), history)
        }
    }

    // MARK: - Answers, suggestions and chips

    private var sample: StudyHistory { ChartSearchSampleHistoryTests.history }

    private func search(_ text: String, plan: ChartSearchPlan? = nil, in history: StudyHistory? = nil) -> ChartSearchResults {
        let history = history ?? sample
        return ChartSearch.results(for: ChartQuery(text, history: history), plan: plan, history: history,
                                   saved: SavedStudyViews(data: Data()))
    }

    @Test("Last week's count is the sets logged last week")
    func lastWeekCount() throws {
        let calendar = sample.calendar
        let week = calendar.dateInterval(of: .weekOfYear, for: calendar.date(byAdding: .day, value: -7, to: sample.today)!)!
        let expected = sample.sessions.filter { week.contains($0.date) && $0.date < week.end }.reduce(0) { $0 + $1.done.count }
        let answer = try #require(search("how many sets did i do last week").answer)
        guard case .table(let table) = answer.result.figure else {
            Issue.record("Expected a single value")
            return
        }
        #expect(expected > 0)
        #expect(table.rows.first?[2] == String(expected))
    }

    @Test("The model's number counts only when the words ask for one without naming it")
    func modelNeverInventsANumber() throws {
        let plan = ChartSearchPlan(charts: [], total: .maximumLoad)
        #expect(search("is my bench going up", plan: plan).answer == nil)
        #expect(search("did i skip sets", plan: plan).answer == nil)
        #expect(search("when did i last squat", plan: plan).answer?.result.displayTitle.hasPrefix("Last trained") == true)
        let sets = ChartSearchPlan(charts: [], total: .workingSets)
        #expect(search("how many push ups did i do", plan: sets).answer?.result.displayTitle.hasPrefix("Working sets") == true)
        #expect(search("how many push ups did i do").answer?.result.displayTitle.hasPrefix("Total reps") == true)
    }

    @Test("A search with no charts says why and offers a closer search")
    func noEmptyScreens() throws {
        let typo = search("benhcc")
        #expect(typo.cards.isEmpty)
        #expect(typo.suggestion == .init(name: "Barbell Bench Press", text: "barbell bench press"))
        let incline = search("incline bench")
        #expect(incline.note == "No logged sets for Incline Bench Press.")
        #expect(incline.suggestion?.name == "Barbell Bench Press")
        #expect(search("bench progress").suggestion == nil, "a search with charts needs no suggestion")
    }

    @Test("A family lift on a one-lift chart is one card, on the most trained lift")
    func oneCardPerLift() throws {
        let squat = try #require(sample.sessions.first { $0.name == "Barbell Back Squat" }?.key)
        let cards = search("squat").cards.filter { !$0.id.study.multipleExercises && $0.id.study != .relationship }
        #expect(!cards.isEmpty)
        #expect(Dictionary(grouping: cards, by: \.id.study).values.allSatisfy { $0.count == 1 })
        #expect(cards.allSatisfy { $0.options.exerciseKeys == [squat] })
    }

    @Test("Chips show what search read, and offer other lifts or removing each")
    func scopeChips() throws {
        let results = search("squat october 225")
        #expect(results.scope.map(\.label) == ["Squat", "October 2026", "225 lb"])
        let squat = try #require(results.scope.first)
        #expect(squat.alternatives.map(\.name).contains("Goblet Squat"))
        #expect(squat.alternatives.first { $0.name == "Goblet Squat" }?.text == "goblet squat october 225")
        #expect(squat.removed == "october 225")
        #expect(results.scope[1].removed == "squat 225")
        let goblet = search("goblet squat october 225")
        #expect(goblet.scope.first?.label == "Goblet Squat")
    }

    @Test("Two periods that follow each other compare on the rep change chart")
    func comparedPeriods() throws {
        let card = try #require(search("rep changes october vs november").cards.first { $0.id.study == .repChanges })
        #expect(card.options.period == .month(year: 2026, month: 11))
    }

    // MARK: - FitNotes-style history

    /// A small log imported from FitNotes, under FitNotes' own names, plus one own lift whose
    /// joints were set by hand. Three sets of 5 on each day.
    static func fitNotesHistory() throws -> StudyHistory {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        let own = Exercise(exerciseName: "Band Pull Apart", exerciseEquipment: .cable, primaryMuscleFocus: .shoulders,
                           userCreated: true)
        context.insert(own)
        CustomJointActions.write([.main("shoulder.horizontalAbduction"), .assisting("scapula.retraction")], to: own, in: context)
        try context.save()
        let ownKey = try #require(own.syncKey)
        let lifts: [(name: String, key: String, pounds: Double)] = [
            ("Flat Barbell Bench Press", "catalog:barbell-bench-press", 185),
            ("Narrow Bar Bell Bench", "catalog:close-grip-bench-press", 155),
            ("Flat Dumbbell Bench Press", "catalog:dumbbell-bench-press", 60),
            ("Shoulder 7s", "catalog:dumbbell-lateral-raise", 15),
            ("Pull Ups Forward Grip", "catalog:pull-up", 0),
            ("Hex Bar Dead Lift", "catalog:trap-bar-deadlift", 275),
            ("Burpies", "catalog:burpee", 0),
            ("Reverse Fly", "catalog:dumbbell-reverse-fly", 20),
            ("Chest Flys", "catalog:cable-chest-fly", 40),
            ("Barbell Squat", "catalog:barbell-back-squat", 245),
            ("Barbell Front Squat", "catalog:barbell-front-squat", 185),
            ("Dumbbell Squat", "catalog:dumbbell-goblet-squat", 50),
            ("Band Pull Apart", ownKey, 0),
        ]
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var rows: [ImportedSet] = []
        for (index, lift) in lifts.enumerated() {
            let name = exercises.first { $0.syncKey == lift.key }?.exerciseName ?? lift.name
            for (day, order) in [("2026-10-06", 0), ("2026-11-03", 1)] {
                for set in 0..<3 {
                    let row = ImportedSet()
                    row.sourceExercise = lift.name
                    row.exerciseName = name
                    row.exerciseKey = lift.key
                    row.trainingDay = day
                    row.reps = 5
                    row.weightTenthsPounds = lift.pounds > 0 ? Int(lift.pounds * 10) : nil
                    row.sourceOrder = (index * 2 + order) * 3 + set
                    rows.append(row)
                }
            }
        }
        return StudyHistory(programs: [], archive: [], logs: [], imported: rows, exercises: exercises, unit: .pounds,
                            today: ChartSearchFixture.today, calendar: ChartSearchFixture.calendar)
    }
}
