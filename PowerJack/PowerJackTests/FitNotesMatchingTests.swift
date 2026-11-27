import Foundation
import SwiftData
import Testing
@testable import PowerJack

/// Import suggestions on the real export's 85 names, with the model left out.
@MainActor
struct FitNotesMatchingTests {
    let container: ModelContainer
    let context: ModelContext
    let exercises: [Exercise]
    let index: ExerciseSearch.Index

    init() throws {
        container = try PowerJackSchema.makeModelContainer(inMemory: true)
        context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        exercises = try context.fetch(FetchDescriptor<Exercise>())
        index = ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
    }

    private func review(_ name: FitNotesNamesFixture.Name, imported: Set<String> = [],
                        rememberedMatch: Exercise? = nil, rememberedSkip: ImportSkipReason? = nil) -> ImportSuggestion {
        FitNotesMatcher.review(name.name, sets: name.sets, among: exercises, index: index, familiarity: .none,
                               imported: imported, rememberedMatch: rememberedMatch, rememberedSkip: rememberedSkip).suggestion
    }

    private func fixture(_ name: String) throws -> FitNotesNamesFixture.Name {
        try #require(FitNotesNamesFixture.names.first { $0.name == name })
    }

    /// The catalog ID a suggestion matches, or the first choice's.
    private func firstID(_ suggestion: ImportSuggestion) -> String? {
        switch suggestion {
        case .match(let exercise): exercise.catalogID
        case .choices(let choices): choices.first?.catalogID
        case .skip, .none: nil
        }
    }

    @Test func fixtureHoldsTheWholeExport() {
        #expect(FitNotesNamesFixture.names.count == 85)
    }

    @Test func namesMatchedBeforeStillMatchTheSameLift() throws {
        let expected = [
            "Ab-Wheel Rollout": "ab-wheel-rollout", "Arnold Dumbbell Press": "dumbbell-arnold-press",
            "Arnold Shoulder Press": "dumbbell-arnold-press", "Backward Lunges": "reverse-lunge",
            "Barbell Curl": "barbell-curl", "Barbell Front Squat": "barbell-front-squat", "Barbell Row": "barbell-row",
            "Barbell Squat": "barbell-back-squat", "Burpies": "burpee",
            "Cable Overhead Triceps Extension": "cable-overhead-extension",
            "Close Grip Barbell Bench Press": "close-grip-bench-press", "Crunch": "crunch", "Deadlift": "barbell-deadlift",
            "Dumbbell Calf Raise": "dumbbell-calf-raise", "Dumbbell Curl": "dumbbell-curl",
            "Dumbbell Overhead Triceps Extension": "dumbbell-triceps-extension", "Dumbbell Row": "one-arm-dumbbell-row",
            "Dumbbell Shrug": "dumbbell-shrug", "Flat Barbell Bench Press": "barbell-bench-press",
            "Flat Dumbbell Bench Press": "dumbbell-bench-press", "Good Morning": "barbell-good-morning",
            "Hex Bar Dead Lift": "trap-bar-deadlift", "Incline Barbell Bench Press": "incline-barbell-bench-press",
            "Incline Dumbbell Bench Press": "incline-dumbbell-bench-press", "Kettlebell Swings": "kettlebell-swing",
            "Lateral Dumbbell Raise": "dumbbell-lateral-raise", "Leg Extension Machine": "leg-extension",
            "Military Bar Press": "barbell-overhead-press", "Mountain Climbers": "mountain-climber",
            "Narrow Bar Bell Bench": "close-grip-bench-press", "Pull Up": "pull-up", "Pull Ups Forward Grip": "pull-up",
            "Pull Ups Reverse Grip": "chin-up", "Push Up": "push-up", "Russian Twista": "russian-twist",
            "Side Lunges": "lateral-lunge", "Single Leg Romanian Deadlift": "single-leg-romanian-deadlift",
            "Sit Ups": "sit-up", "Split Squat": "split-squat",
        ]
        for (name, id) in expected {
            let suggestion = review(try fixture(name))
            guard case .match(let exercise) = suggestion else {
                Issue.record("\(name) should match \(id), got \(suggestion)")
                continue
            }
            #expect(exercise.catalogID == id, "\(name)")
        }
    }

    @Test func namesTheOldMatcherMissedFindTheirLift() throws {
        let expected: [String: Set<String>] = [
            "Romanian Deadlift": ["barbell-romanian-deadlift", "dumbbell-romanian-deadlift"],
            "Walking Lunges": ["dumbbell-walking-lunge"],
            "Chest Flys": ["cable-chest-fly"],
            "Hanging Knee Raise (Sides Too)": ["hanging-knee-raise"],
            "Dumbbell Squat": ["dumbbell-goblet-squat", "goblet-squat"],
        ]
        for (name, ids) in expected {
            let first = firstID(review(try fixture(name)))
            #expect(first.map(ids.contains) == true, "\(name) suggested \(first ?? "nothing")")
        }
    }

    @Test func theModelLeavesFullNameTiesToTheLifter() throws {
        func asksModel(_ name: String) throws -> Bool {
            let row = try fixture(name)
            return FitNotesMatcher.review(row.name, sets: row.sets, among: exercises, index: index, familiarity: .none,
                                          imported: [], rememberedMatch: nil, rememberedSkip: nil).askModel
        }
        #expect(try !asksModel("Romanian Deadlift"))
        #expect(try !asksModel("Barbell Squat"))
        #expect(try !asksModel("Running (Outdoor)"))
        #expect(try asksModel("V Ups"))
    }

    @Test func nonLiftsShowAStatedSkipReason() throws {
        let expected: [String: ImportSkipReason] = [
            "Running (Outdoor)": .cardio, "Running (Treadmill)": .cardio, "Cycling": .cardio, "MTB": .cardio,
            "Run // MTB": .cardio, "Rowing Machine": .cardio, "Jumping Jacks": .cardio,
            "Stretch": .stretchOrPT, "Ankle PT": .stretchOrPT, "Back PT": .stretchOrPT,
            "Farmers Carry": .timed, "Push Up Elbows": .timed, "Ropes": .timed,
        ]
        for (name, reason) in expected {
            let suggestion = review(try fixture(name))
            guard case .skip(let shown) = suggestion else {
                Issue.record("\(name) should skip for \(reason), got \(suggestion)")
                continue
            }
            #expect(shown == reason, "\(name)")
        }
        // A built-in lift filed under Cardio is still a lift.
        #expect(firstID(review(try fixture("Burpies"))) == "burpee")
    }

    @Test func aWeakMatchIsNeverASkip() {
        let skipped = FitNotesNamesFixture.names.filter { name in
            guard case .skip = review(name) else { return false }
            return name.reps && name.category != "Cardio" && name.category != "PT"
        }
        #expect(skipped.isEmpty, "\(skipped.map(\.name))")
    }

    @Test func everyRowOpensWithASuggestion() {
        let open = FitNotesNamesFixture.names.filter { name in
            if case .none = review(name) { return true }
            return false
        }
        #expect(open.isEmpty, "\(open.map(\.name))")
    }

    @Test func aSecondImportArrivesConfirmedOrSkipped() throws {
        let rows = FitNotesNamesFixture.names
        let imported = Set(rows.flatMap(\.sets).map(\.key))
        for name in rows {
            guard case .skip(.alreadyImported) = review(name, imported: imported) else {
                Issue.record("\(name.name) should be already imported")
                continue
            }
        }
        // A name with new rows comes back on its earlier match, confirmed by the view.
        let bench = try #require(exercises.first { $0.catalogID == "barbell-bench-press" })
        let running = try fixture("Running (Outdoor)")
        guard case .match(let exercise) = review(running, rememberedMatch: bench) else {
            Issue.record("An earlier match should win over skip rules")
            return
        }
        #expect(exercise == bench)
        guard case .skip(.chosen) = review(try fixture("Shoulder 7s"), rememberedSkip: .chosen) else {
            Issue.record("An earlier skip should come back skipped")
            return
        }
    }

    @Test func rememberedSkipsStayOnTheDevice() throws {
        let defaults = try #require(UserDefaults(suiteName: "FitNotesMatchingTests"))
        defaults.removePersistentDomain(forName: "FitNotesMatchingTests")
        FitNotesSkips.record(skipped: ["Shoulder 7s": .chosen, "Cycling": .cardio, "Bench": .alreadyImported],
                             imported: [], in: defaults)
        #expect(FitNotesSkips.load(defaults) == ["Shoulder 7s": .chosen, "Cycling": .cardio])
        FitNotesSkips.record(skipped: [:], imported: ["Cycling"], in: defaults)
        #expect(FitNotesSkips.load(defaults) == ["Shoulder 7s": .chosen])
        defaults.removePersistentDomain(forName: "FitNotesMatchingTests")
    }
}
