import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct TemplateCatalogTests {
    @Test("Catalog templates use known exercises and pass template validation")
    func catalogValidity() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        try ExerciseCatalog.seed(in: container.mainContext)
        let exercisesByID = Dictionary(
            uniqueKeysWithValues: try container.mainContext.fetch(FetchDescriptor<Exercise>()).compactMap { exercise in
                exercise.catalogID.map { ($0, exercise) }
            }
        )

        let entries = TemplateCatalog.entries
        #expect(Set(entries.map(\.id)).count == entries.count)
        for entry in entries {
            let template = try #require(entry.makeTemplate(exercisesByID: exercisesByID), "\(entry.id)")
            #expect(!template.draft, "\(entry.id)")
            #expect(!TemplateProgramDraft(templateProgram: template).isDraft, "\(entry.id)")
            #expect(template.templateWorkouts.count == template.workoutsPerWeek)
            #expect((1...TemplateProgramDraft.maximumFocusMuscles).contains(entry.muscleFocus.count), "\(entry.id)")
            // Names are kept whole and stay editable.
            #expect(TemplateProgramDraft(templateProgram: template).canSave, "\(entry.id)")
            #expect(template.templateName == entry.name, "\(entry.id)")
            #expect(template.templateType == entry.type, "\(entry.id)")
            // Workouts and exercises keep the catalog's order.
            let storedIDs = template.templateWorkouts.map { $0.templateExercises.compactMap(\.exercise?.catalogID) }
            #expect(storedIDs == entry.workouts, "\(entry.id)")
        }
    }

    @Test("The catalog ships ten templates: Build, Strengthen and PowerJack for 3, 4 and 5 days")
    func catalogContents() {
        let entries = TemplateCatalog.entries
        #expect(entries.map(\.name) == [
            "Full Body", "Upper Lower", "Physique", "Home Full Body",
            "Big Three", "Big Four", "Bigger Total",
            "Power Full Body", "Power Upper Lower", "Power & Pump",
        ])
        #expect(entries.map(\.workouts.count) == [3, 4, 5, 3, 3, 4, 5, 3, 4, 5])
        let types: [TemplateType] = Array(repeating: .hypertrophy, count: 4) + Array(repeating: .strength, count: 3)
            + Array(repeating: .powerJack, count: 3)
        #expect(entries.map(\.type) == types)
        #expect(entries.allSatisfy { $0.name.count <= TemplateProgramDraft.maximumNameLength })
        // Program lists show only the name, so no two templates share one.
        #expect(Set(entries.map(\.name)).count == entries.count)
        #expect(Set(entries.map(\.id)).isDisjoint(with: TemplateCatalog.retiredIDs))
    }

    @Test("Build templates train every muscle they work at least twice a week, within the per-session cap")
    func buildEnvelope() throws {
        let exercises = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ($0.id, $0) })
        for entry in TemplateCatalog.entries where entry.type == .hypertrophy {
            var sessions: [Muscle: Int] = [:]
            for workout in entry.workouts {
                // Credits at the 2 starting sets a slot: 1 per set for the primary muscle, 0.5 for each secondary.
                var credits: [Muscle: Double] = [:]
                for id in workout {
                    let exercise = try #require(exercises[id], "\(id)")
                    credits[exercise.primaryMuscle, default: 0] += 2
                    for muscle in exercise.secondaryMuscles { credits[muscle, default: 0] += 1 }
                }
                #expect(credits.values.allSatisfy { $0 <= BuildRules.maxCreditsPerSessionPerMuscle }, "\(entry.id)")
                for muscle in Set(workout.compactMap { exercises[$0]?.primaryMuscle }) {
                    sessions[muscle, default: 0] += 1
                }
            }
            for (muscle, count) in sessions {
                #expect(count >= 2, "\(entry.id) trains \(muscle) in \(count) session")
            }
        }
    }

    @Test("Strengthen templates rank the squat, bench and deadlift, and Big Four adds the press")
    func strengthPriorityLifts() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        try ExerciseCatalog.seed(in: container.mainContext)
        let exercisesByID = Dictionary(
            uniqueKeysWithValues: try container.mainContext.fetch(FetchDescriptor<Exercise>()).compactMap { exercise in
                exercise.catalogID.map { ($0, exercise) }
            }
        )
        let bigThree = ["barbell-back-squat", "barbell-bench-press", "barbell-deadlift"]
        for entry in TemplateCatalog.entries where entry.type == .strength {
            let workouts = entry.workouts.map { $0.compactMap { exercisesByID[$0] } }
            let expected = entry.id == "strength-big-four-4x" ? bigThree + ["barbell-overhead-press"] : bigThree
            #expect(StrengthLifts.priorityKeys(in: workouts) == expected, "\(entry.id)")
            // Each day opens with a priority lift.
            #expect(workouts.allSatisfy { expected.contains($0.first?.catalogID ?? "") }, "\(entry.id)")
        }
    }

    @Test("PowerJack templates make the squat, deadlift, bench and overhead press their main lifts")
    func powerJackMainLifts() {
        let exercises = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ($0.id, $0) })
        for entry in TemplateCatalog.entries where entry.type == .powerJack {
            let workouts = entry.workouts.map { workout in
                workout.compactMap { id in exercises[id].map { Self.powerJackExercise(id: id, entry: $0) } }
            }
            let roles = PowerJackRoles.assign(workouts)
            let mains = zip(workouts.joined(), roles.joined()).filter { $0.1.role == .main }.compactMap { $0.0.id as? String }
            let expected = Set(["barbell-back-squat", "barbell-deadlift", "barbell-bench-press", "barbell-overhead-press"])
            #expect(Set(mains) == expected, "\(entry.id)")
        }
    }

    @Test("Every built-in template starts a program with sets on every exercise and targets on all but Strengthen accessories")
    func catalogProgramsStart() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        try ExerciseCatalog.seed(in: container.mainContext)
        try TemplateCatalog.seed(in: container.mainContext)
        let templates = try container.mainContext.fetch(FetchDescriptor<TemplateProgram>())
        #expect(templates.count == TemplateCatalog.entries.count)
        for template in templates {
            let program = Program(programLengthWeeks: 8, templateProgram: template)
            container.mainContext.insert(program)
            let exercises = program.programWeeks[0].workouts.flatMap(\.workoutExercises)
            #expect(exercises.count == template.templateWorkouts.flatMap(\.templateExercises).count, "\(template.templateName)")
            for exercise in exercises {
                #expect(!exercise.workingSets.isEmpty, "\(template.templateName)")
                // Strengthen accessories keep a simple double progression with no reps-left target (rule 14.6).
                if exercise.strengthRole != .accessory {
                    #expect(exercise.rirTarget != nil, "\(template.templateName)")
                }
            }
        }
    }

    @Test("Seeding hides the retired templates but keeps them for programs and leaves user templates alone")
    func retiredTemplatesHide() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        let squat = try #require(try context.fetch(FetchDescriptor<Exercise>()).first { $0.catalogID == "barbell-back-squat" })

        let retired = TemplateProgram(templateName: "Old Built-in", workoutsPerWeek: 1, templateMuscleFocus: [.quads])
        retired.catalogID = "full-gym-strength-foundations-3x"
        retired.addTemplateWorkout().addTemplateExercise(exercise: squat)
        let usedRetired = TemplateProgram(templateName: "Old Built-in In Use", workoutsPerWeek: 1, templateMuscleFocus: [.quads])
        usedRetired.catalogID = "powerjack-upper-lower-4x"
        usedRetired.addTemplateWorkout().addTemplateExercise(exercise: squat)
        let mine = TemplateProgram(templateName: "Mine", workoutsPerWeek: 1, templateMuscleFocus: [.quads])
        mine.addTemplateWorkout().addTemplateExercise(exercise: squat)
        for template in [retired, usedRetired, mine] { context.insert(template) }
        let program = Program(programLengthWeeks: 4, templateProgram: usedRetired)
        context.insert(program)
        try context.save()

        try TemplateCatalog.seed(in: context)

        let stored = try ModelContext(container).fetch(FetchDescriptor<TemplateProgram>())
        let visible = stored.filter { !$0.hiddenValue }
        #expect(Set(visible.map(\.templateName)) == Set(TemplateCatalog.entries.map(\.name) + ["Mine"]))
        // Hidden, not deleted, so the program keeps its template and older app versions don't seed it again.
        #expect(stored.contains { $0.catalogID == "full-gym-strength-foundations-3x" && $0.hiddenValue })
        #expect(program.templateProgram === usedRetired)
        #expect(usedRetired.hiddenValue)
        #expect(program.templateName == "Old Built-in In Use")
    }

    @Test("Seeding saves every template once and keeps user edits")
    func seedAndRepeat() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)

        let seeded = try context.fetch(FetchDescriptor<TemplateProgram>())
        #expect(Set(seeded.map(\.templateName)) == Set(TemplateCatalog.entries.map(\.name)))
        let edited = try #require(seeded.first)
        edited.templateName = "My Split"
        try context.save()

        try TemplateCatalog.seed(in: context)

        // A new context proves that seeding explicitly saved the inserts.
        let stored = try ModelContext(container).fetch(FetchDescriptor<TemplateProgram>())
        #expect(stored.count == TemplateCatalog.entries.count)
        #expect(stored.contains { $0.templateName == "My Split" })
    }

    @Test("Seeding without the exercise catalog inserts nothing")
    func missingExercises() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        try TemplateCatalog.seed(in: container.mainContext)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TemplateProgram>()) == 0)
    }

    private static func powerJackExercise(id: String, entry: ExerciseCatalog.Entry) -> PowerJackExercise {
        let (pattern, multiJoint) = PowerJackExercise.traits(catalogID: id, primary: entry.primaryMuscle, fatigue: entry.fatigueLevel)
        return PowerJackExercise(
            id: id,
            pattern: pattern,
            multiJoint: multiJoint,
            repsOnly: entry.equipment == .bodyweight,
            isBarbell: entry.equipment == .barbell,
            fatigue: entry.fatigueLevel,
            primary: entry.primaryMuscle,
            secondaries: entry.secondaryMuscles
        )
    }
}
