import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct DeletionTests {
    @Test("An unused template of the user's is deleted")
    func unusedTemplateIsDeleted() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let template = TemplateProgram(templateName: "Mine", workoutsPerWeek: 3, templateMuscleFocus: [])
        template.addTemplateWorkout()
        try context.insertAndSave(template)

        template.delete()
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<TemplateProgram>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TemplateWorkout>()) == 0)
    }

    @Test("A template a program was started from is hidden, and the program keeps its name")
    func usedTemplateIsHidden() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let template = TemplateProgram(templateName: "Mine", workoutsPerWeek: 3, templateMuscleFocus: [])
        let program = Program(programLengthWeeks: 4, templateProgram: template)
        context.insert(template)
        try context.insertAndSave(program)

        template.delete()
        try context.save()

        #expect(visibleTemplates(in: context).isEmpty)
        #expect(program.templateName == "Mine")
    }

    @Test("A deleted built-in template stays gone after the catalog seeds again")
    func deletedCatalogTemplateStaysGone() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)
        let template = try #require(visibleTemplates(in: context).first)
        let name = template.templateName

        template.delete()
        try context.save()
        try TemplateCatalog.seed(in: context)

        #expect(!visibleTemplates(in: context).contains { $0.templateName == name })
    }

    @Test("A program that isn't active is deleted with its weeks and workouts")
    func plannedProgramIsDeleted() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let template = TemplateProgram(templateName: "Mine", workoutsPerWeek: 1, templateMuscleFocus: [])
        template.addTemplateWorkout()
        context.insert(template)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try context.insertAndSave(program)

        program.delete()
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Program>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ProgramWeek>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 0)
    }

    @Test("The active program can't be deleted")
    func activeProgramIsKept() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let template = TemplateProgram(templateName: "Mine", workoutsPerWeek: 1, templateMuscleFocus: [])
        context.insert(template)
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        try #require(program.status == .active)

        program.delete()
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Program>()) == 1)
    }

    private func visibleTemplates(in context: ModelContext) -> [TemplateProgram] {
        (try? context.fetch(FetchDescriptor<TemplateProgram>(predicate: #Predicate { !$0.hiddenValue }))) ?? []
    }
}
