import Foundation
import SwiftData
import Testing
@testable import PowerJack

/// Templates and programs as 1.0.13 saved them, before template types existed.
/// Same entity names as the app's models, so the current schema opens this store as an upgrade.
enum PreTemplateTypesStore {
    @Model
    final class TemplateProgram {
        var catalogID: String? = nil
        var templateName: String = ""
        var workoutsPerWeek: Int = 0
        var templateMuscleFocusValue: [Muscle] = []
        var programsValue: [Program]? = []
        var createdAtValue: Date = Date.distantPast
        var hiddenValue: Bool = false

        init(catalogID: String, templateName: String) {
            self.catalogID = catalogID
            self.templateName = templateName
            self.workoutsPerWeek = 3
            self.createdAtValue = .now
        }
    }

    @Model
    final class Program {
        var programLengthWeeksValue: Int = 1
        var statusValue: Status = Status.planned
        @Relationship(deleteRule: .nullify, inverse: \TemplateProgram.programsValue)
        var templateProgramValue: TemplateProgram?
        var lockedValue: Bool = false
        var workoutsPerWeekValue: Int = 0
        var templateNameValue: String = ""
        var templateMuscleFocusValue: [Muscle] = []

        init(templateProgram: TemplateProgram) {
            self.templateProgramValue = templateProgram
            self.templateNameValue = templateProgram.templateName
            self.workoutsPerWeekValue = templateProgram.workoutsPerWeek
        }
    }
}

@MainActor
struct UpgradeFromOldStoreTests {
    @Test("Upgrading from before template types launches, and old rows read as Hypertrophy")
    func upgradeFromBeforeTemplateTypes() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "upgrade-\(UUID().uuidString).store")
        // A built-in template 1.0.13 seeded and that is now retired, so launching changes and saves it.
        let retiredID = try #require(TemplateCatalog.retiredIDs.sorted().first)

        do {
            let oldSchema = Schema([PreTemplateTypesStore.TemplateProgram.self, PreTemplateTypesStore.Program.self])
            let oldContainer = try ModelContainer(
                for: oldSchema,
                configurations: [ModelConfiguration(schema: oldSchema, url: url, cloudKitDatabase: .none)]
            )
            let template = PreTemplateTypesStore.TemplateProgram(catalogID: retiredID, templateName: "Old Template")
            oldContainer.mainContext.insert(template)
            oldContainer.mainContext.insert(PreTemplateTypesStore.Program(templateProgram: template))
            try oldContainer.mainContext.save()
        }

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
}
