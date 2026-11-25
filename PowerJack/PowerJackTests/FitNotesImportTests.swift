import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct FitNotesImportTests {
    @Test func suggestionsRequireAgreementOnEquipmentAndVariation() {
        let catalog = ExerciseCatalog.entries.map { $0.makeExercise() }
        for ambiguous in ["Ankle PT", "Air Squat", "Romanian Deadlift", "Slider Push-Up"] {
            #expect(FitNotesMatcher.ranked(ambiguous, among: catalog).isEmpty)
        }
        #expect(FitNotesMatcher.ranked("BB RDL", among: catalog).map(\.catalogID) == ["barbell-romanian-deadlift"])
    }

    @Test func reviewRowSuggestsAuditedAliasesAndKeepsCatalogGapsManual() {
        let catalog = ExerciseCatalog.entries.map { $0.makeExercise() }
        let choices = FitNotesMatcher.selectorChoices("Dumbbell Row", category: "Back", among: catalog, preferred: nil)
        #expect(choices.first?.catalogID == "one-arm-dumbbell-row")
        #expect(choices.count == 3)
        #expect(Set(choices.map(\.catalogID)).count == 3)
        for (name, id) in ["Dumbbell Row": "one-arm-dumbbell-row", "Deadlift": "barbell-deadlift",
                           "Barbell Squat": "barbell-back-squat", "Military Bar Press": "barbell-overhead-press",
                           "Cable Overhead Triceps Extension": "cable-overhead-extension",
                           "Dumbbell Overhead Triceps Extension": "dumbbell-triceps-extension"] {
            #expect(FitNotesMatcher.direct(name, among: catalog)?.catalogID == id)
        }
        for name in ["Nordic Curls", "Running (Outdoor)"] {
            #expect(FitNotesMatcher.direct(name, among: catalog) == nil)
            #expect(FitNotesMatcher.ranked(name, among: catalog).isEmpty)
            #expect(FitNotesMatcher.selectorChoices(name, category: "", among: catalog, preferred: nil).count == 3)
        }
    }

    @Test func recommendedAdditionsMatchTheOriginalExportNames() {
        let catalog = ExerciseCatalog.entries.map { $0.makeExercise() }
        let names = ["Sit Ups": "sit-up", "Side Lunges": "lateral-lunge", "Ab-Wheel Rollout": "ab-wheel-rollout",
                     "Single Leg Romanian Deadlift": "single-leg-romanian-deadlift", "Mountain Climbers": "mountain-climber",
                     "Split Squat": "split-squat", "Hex Bar Dead Lift": "trap-bar-deadlift", "Burpies": "burpee",
                     "Arnold Dumbbell Press": "dumbbell-arnold-press", "Arnold Shoulder Press": "dumbbell-arnold-press",
                     "Russian Twista": "russian-twist"]
        for (name, id) in names {
            #expect(FitNotesMatcher.direct(name, among: catalog)?.catalogID == id)
        }
    }

    @Test func newStrengthExercisesMatchTheirImportNames() {
        let catalog = ExerciseCatalog.entries.map { $0.makeExercise() }
        for (source, target) in ["Chest Press (Machine)": "machine-chest-press", "Dumbbell Shrugs": "dumbbell-shrug",
                                 "Good Morning": "barbell-good-morning", "Backward Lunges": "reverse-lunge",
                                 "Kettlebell Swings": "kettlebell-swing", "Preacher Curl (EZ-Bar)": "ez-bar-preacher-curl"] {
            #expect(FitNotesMatcher.direct(source, among: catalog)?.catalogID == target)
        }
        for source in ["Machine Preacher Curl", "Incline Machine Chest Press", "Barbell Shrug", "Reverse Nordic Curl"] {
            #expect(FitNotesMatcher.direct(source, among: catalog) == nil)
            #expect(FitNotesMatcher.ranked(source, among: catalog).isEmpty)
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
}
