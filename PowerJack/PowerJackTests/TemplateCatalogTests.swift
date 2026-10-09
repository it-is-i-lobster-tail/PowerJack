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
            // Workouts and exercises keep the catalog's order.
            let storedIDs = template.templateWorkouts.map { $0.templateExercises.compactMap(\.exercise?.catalogID) }
            #expect(storedIDs == entry.workouts, "\(entry.id)")
        }
    }

    @Test("The catalog ships the eleven starter templates in order")
    func catalogContents() {
        let entries = TemplateCatalog.entries
        #expect(entries.map(\.id) == [
            "home-whole-body-essentials-2x",
            "small-gym-whole-body-essentials-2x",
            "full-gym-legs-core-focus-2x",
            "home-whole-body-muscle-builder-3x",
            "small-gym-whole-body-muscle-builder-3x",
            "full-gym-arms-focus-3x",
            "full-gym-chest-back-core-focus-3x",
            "full-gym-whole-body-muscle-builder-4x",
            "small-gym-glutes-shoulders-focus-4x",
            "full-gym-upper-body-specialization-5x",
            "full-gym-glute-specialization-5x",
        ])
        #expect(entries.map(\.workouts.count) == [2, 2, 2, 3, 3, 3, 3, 4, 4, 5, 5])
        #expect(entries.allSatisfy { $0.name.count <= TemplateProgramDraft.maximumNameLength })
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
}
