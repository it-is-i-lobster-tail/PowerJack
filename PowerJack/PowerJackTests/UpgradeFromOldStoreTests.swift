import CoreData
import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct UpgradeFromOldStoreTests {
    @Test("Upgrading from before template types launches, and old rows read as Hypertrophy")
    func upgradeFromBeforeTemplateTypes() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "upgrade-\(UUID().uuidString).store")
        // A built-in template 1.0.13 seeded and that is now retired, so launching changes and saves it.
        let retiredID = try #require(TemplateCatalog.retiredIDs.sorted().first)
        try writeStoreFromBeforeTemplateTypes(at: url, templateCatalogID: retiredID)

        let schema = PowerJackSchema.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        let context = container.mainContext

        // What launch does. Before the fix, saving the retired template here crashed every launch.
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)

        let template = try #require(
            try context.fetch(FetchDescriptor<TemplateProgram>()).first { $0.catalogID == retiredID }
        )
        #expect(template.templateType == .hypertrophy)
        #expect(template.hiddenValue)

        let program = try #require(try context.fetch(FetchDescriptor<Program>()).first)
        #expect(program.templateType == .hypertrophy)
        #expect(program.templateProgram === template)
        #expect(program.templateName == "Old Template")
    }

    /// Saves a template and a program the way 1.0.13 did, before template types existed.
    /// Plain Core Data with the same entity names, so no second set of model classes shares the
    /// test process with the app's.
    private func writeStoreFromBeforeTemplateTypes(at url: URL, templateCatalogID: String) throws {
        let template = NSEntityDescription()
        template.name = "TemplateProgram"
        let program = NSEntityDescription()
        program.name = "Program"

        let programs = NSRelationshipDescription()
        programs.name = "programsValue"
        programs.destinationEntity = program
        programs.minCount = 0
        programs.maxCount = 0
        programs.deleteRule = .nullifyDeleteRule
        programs.isOptional = true
        let templateOfProgram = NSRelationshipDescription()
        templateOfProgram.name = "templateProgramValue"
        templateOfProgram.destinationEntity = template
        templateOfProgram.maxCount = 1
        templateOfProgram.deleteRule = .nullifyDeleteRule
        templateOfProgram.isOptional = true
        programs.inverseRelationship = templateOfProgram
        templateOfProgram.inverseRelationship = programs

        template.properties = [
            attribute("catalogID", .stringAttributeType),
            attribute("templateName", .stringAttributeType),
            attribute("workoutsPerWeek", .integer64AttributeType),
            attribute("createdAtValue", .dateAttributeType),
            attribute("hiddenValue", .booleanAttributeType),
            programs,
        ]
        program.properties = [
            attribute("programLengthWeeksValue", .integer64AttributeType),
            attribute("lockedValue", .booleanAttributeType),
            attribute("workoutsPerWeekValue", .integer64AttributeType),
            attribute("templateNameValue", .stringAttributeType),
            templateOfProgram,
        ]
        let model = NSManagedObjectModel()
        model.entities = [template, program]

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
        let context = NSManagedObjectContext(.mainQueue)
        context.persistentStoreCoordinator = coordinator

        let oldTemplate = NSManagedObject(entity: template, insertInto: context)
        oldTemplate.setValue(templateCatalogID, forKey: "catalogID")
        oldTemplate.setValue("Old Template", forKey: "templateName")
        oldTemplate.setValue(3, forKey: "workoutsPerWeek")
        oldTemplate.setValue(Date.now, forKey: "createdAtValue")
        oldTemplate.setValue(false, forKey: "hiddenValue")
        let oldProgram = NSManagedObject(entity: program, insertInto: context)
        oldProgram.setValue(4, forKey: "programLengthWeeksValue")
        oldProgram.setValue(false, forKey: "lockedValue")
        oldProgram.setValue(3, forKey: "workoutsPerWeekValue")
        oldProgram.setValue("Old Template", forKey: "templateNameValue")
        oldProgram.setValue(oldTemplate, forKey: "templateProgramValue")
        try context.save()
        try coordinator.remove(store)
    }

    private func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        return attribute
    }
}
