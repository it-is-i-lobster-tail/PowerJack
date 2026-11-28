import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct FitNotesImportTests {
    /// The lift a FitNotes name opens matched to, through an alias or the shared search,
    /// with the category the real export files it under.
    private func matched(_ name: String, among catalog: [Exercise]) -> String? {
        let index = ExerciseSearch.Index(catalog.map(ExerciseSearch.Document.init))
        let category = FitNotesNamesFixture.names.first { $0.name == name }?.category ?? ""
        guard case .match(let exercise) = FitNotesMatcher.search(name, category: category, among: catalog, index: index,
                                                                 familiarity: .none).suggestion else { return nil }
        return exercise.catalogID
    }

    @Test func exportNamesMatchTheirLift() {
        let catalog = ExerciseCatalog.entries.map { $0.makeExercise() }
        let names = ["Dumbbell Row": "one-arm-dumbbell-row", "Deadlift": "barbell-deadlift",
                     "Barbell Squat": "barbell-back-squat", "Military Bar Press": "barbell-overhead-press",
                     "Cable Overhead Triceps Extension": "cable-overhead-extension",
                     "Dumbbell Overhead Triceps Extension": "dumbbell-triceps-extension",
                     "Sit Ups": "sit-up", "Side Lunges": "lateral-lunge", "Ab-Wheel Rollout": "ab-wheel-rollout",
                     "Single Leg Romanian Deadlift": "single-leg-romanian-deadlift", "Mountain Climbers": "mountain-climber",
                     "Split Squat": "split-squat", "Hex Bar Dead Lift": "trap-bar-deadlift", "Burpies": "burpee",
                     "Arnold Dumbbell Press": "dumbbell-arnold-press", "Arnold Shoulder Press": "dumbbell-arnold-press",
                     "Russian Twista": "russian-twist", "Chest Press (Machine)": "machine-chest-press",
                     "Dumbbell Shrugs": "dumbbell-shrug", "Good Morning": "barbell-good-morning",
                     "Backward Lunges": "reverse-lunge", "Kettlebell Swings": "kettlebell-swing",
                     "Preacher Curl (EZ-Bar)": "ez-bar-preacher-curl", "Nordic Curls": "nordic-hamstring-curl",
                     "Barbell Shrug": "barbell-shrug"]
        for (name, id) in names {
            #expect(matched(name, among: catalog) == id, "\(name)")
        }
    }

    @Test func liftsMissingFromTheCatalogAreNeverMatched() {
        let catalog = ExerciseCatalog.entries.map { $0.makeExercise() }
        for name in ["Running (Outdoor)", "Machine Preacher Curl", "Incline Machine Chest Press", "Reverse Nordic Curl"] {
            #expect(matched(name, among: catalog) == nil, "\(name)")
        }
    }

    @Test func newExercisePrefillsTheFitNotesMuscle() {
        #expect(FitNotesMatcher.primaryMuscle(for: "Dumbbell Squat", category: "Legs") == .quads)
        #expect(FitNotesMatcher.primaryMuscle(for: "Leg Curl", category: "Legs") == .hamstrings)
        #expect(FitNotesMatcher.primaryMuscle(for: "Dumbbell Squat", category: " Glutes ") == .glutes)
        #expect(FitNotesMatcher.primaryMuscle(for: "Back PT", category: "PT") == nil)
    }

    @Test func customEquipmentSurvivesExerciseEditsAndSnapshots() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let equipment = CustomEquipment(name: "Cambered Bar", base: .barbell)
        try context.insertAndSave(equipment)
        var draft = ExerciseDraft(name: "Good Morning")
        draft.equipment = equipment.base
        draft.customEquipmentName = equipment.name
        draft.primaryMuscle = .back
        let exercise = try #require(draft.makeExercise())
        try context.insertAndSave(exercise)
        exercise.assignSyncID()
        let snapshot = try #require(exercise.syncState)
        let copy = Exercise(snapshot: snapshot)
        #expect(copy.equipment == .barbell)
        #expect(copy.equipmentDisplayName == equipment.name)
        #expect(ExerciseDraft(exercise: copy).customEquipmentName == equipment.name)
        draft.customEquipmentName = nil
        #expect(draft.apply(to: exercise))
        #expect(exercise.equipmentDisplayName == Equipment.barbell.displayName)
    }

    @Test func repeatedSetsAndCommentsSurviveOverlappingImports() throws {
        let header = FitNotesImport.columns.joined(separator: ",")
        let set = "2025-03-12,Flat Barbell Bench Press,Chest,10,kg,8,,,,"
        let timed = "2025-03-12,Running,Cardio,,,,2,mi,0:15:02,"
        let document = [header, set, set, set + "\"Slow, controlled\"", timed].joined(separator: "\r\n")
        let rows = try FitNotesImport.parse(Data(document.utf8))
        #expect(Set(rows.map(\.key)).count == 4)
        #expect(Set(rows.map(\.name)).count == 2)
        #expect(rows.last?.seconds == 902)
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let bench = ExerciseCatalog.entries[0].makeExercise()
        let run = Exercise(exerciseName: "Running", exerciseEquipment: .bodyweight, primaryMuscleFocus: .quads, userCreated: true)
        context.insert(bench)
        context.insert(run)
        let matches = ["Flat Barbell Bench Press": bench, "Running": run]
        #expect(try FitNotesImport.save(rows, matches: matches, in: context) == 4)
        #expect(try FitNotesImport.save(rows, matches: matches, in: context) == 0)
        let saved = try context.fetch(FetchDescriptor<ImportedSet>())
        #expect(saved.count == 4)
        #expect(saved.first { $0.comment == "Slow, controlled" }?.weightTenthsPounds == 220)
        #expect(saved.first { $0.durationSeconds == 902 }?.distanceUnit == "mi")
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 0)
    }

    @Test func importedSetsFeedTheDataCharts() throws {
        let header = FitNotesImport.columns.joined(separator: ",")
        let document = [header,
                        "2025-03-12,Barbell Squat,Legs,225,lbs,5,,,,",
                        "2025-03-12,Barbell Squat,Legs,225,lbs,5,,,,",
                        "2025-03-12,Running,Cardio,,,,2,mi,0:15:02,",
                        "2025-03-19,Barbell Squat,Legs,235,lbs,5,,,,"].joined(separator: "\n")
        let rows = try FitNotesImport.parse(Data(document.utf8))
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let squat = try #require(ExerciseCatalog.entries.first { $0.id == "barbell-back-squat" }).makeExercise()
        let run = Exercise(exerciseName: "Running", exerciseEquipment: .bodyweight, primaryMuscleFocus: .quads, userCreated: true)
        context.insert(squat)
        context.insert(run)
        _ = try FitNotesImport.save(rows, matches: ["Barbell Squat": squat, "Running": run], in: context)

        let calendar = Calendar(identifier: .gregorian)
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25)))
        let history = StudyHistory(
            programs: [], archive: [], logs: [], imported: try context.fetch(FetchDescriptor<ImportedSet>()),
            exercises: [squat, run], unit: .pounds, today: today, calendar: calendar)
        // The run has no reps, so only the two squat days become sessions.
        #expect(history.sessions.map(\.key) == [StudyHistory.squat, StudyHistory.squat])
        #expect(history.sessions.map { $0.done.count } == [2, 1])
        #expect(history.sessions.first?.sets.first?.load == 2250)
        #expect(history.firstDate == calendar.date(from: DateComponents(year: 2025, month: 3, day: 12, hour: 12)))
        #expect(history.credits.filter { $0.muscle == .quads }.map(\.sets).reduce(0, +) == 3)

        var options = StudyOptions()
        options.period = .year(2025)
        for study in [TrainingStudy.legWork, .records, .legMax] {
            #expect(history.result(for: study, options: options).figure != nil, "\(study.caption) should show imported sets")
        }
    }
}
