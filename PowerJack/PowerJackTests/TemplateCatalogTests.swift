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
            #expect(TemplateProgramDraft(templateProgram: template).canSave, "\(entry.id)")
            #expect(template.templateWorkouts.count == template.workoutsPerWeek)
        }
    }

    @Test("Seeding saves every template once and keeps user edits")
    func seedAndRepeat() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)

        let seeded = try context.fetch(FetchDescriptor<TemplateProgram>())
        #expect(Set(seeded.map(\.templateName)) == ["Beach Body Builder", "Leg Blaster", "Dad Bod Try Hard", "Bro Split"])
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
