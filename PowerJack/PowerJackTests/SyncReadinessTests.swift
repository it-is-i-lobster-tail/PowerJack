import Foundation
import SwiftData
import Testing
@testable import PowerJack

/// Behavior the models need before CloudKit sync is turned on.
@MainActor
struct SyncReadinessTests {
    @Test("A duplicated catalog exercise merges into the oldest copy")
    func exerciseDuplicatesMerge() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let entry = ExerciseCatalog.entries[0]
        let original = try catalogExercises(in: context, id: entry.id)[0]

        // A second device seeds its own copy before the synced one arrives.
        let duplicate = entry.makeExercise()
        duplicate.createdAtValue = .now.addingTimeInterval(60)
        context.insert(duplicate)
        let template = TemplateProgram(templateName: "Mine", workoutsPerWeek: 1, templateMuscleFocus: [])
        let templateExercise = template.addTemplateWorkout().addTemplateExercise(exercise: duplicate)
        context.insert(template)
        try context.save()

        try ExerciseCatalog.seed(in: context)

        let survivors = try catalogExercises(in: context, id: entry.id)
        #expect(survivors.count == 1)
        #expect(survivors.first === original)
        #expect(templateExercise.exercise === original)
    }

    @Test("A duplicated built-in template merges into the oldest copy")
    func templateDuplicatesMerge() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let entry = TemplateCatalog.entries[0]
        let original = try catalogTemplates(in: context, id: entry.id)[0]

        let exercisesByID = Dictionary(
            try context.fetch(FetchDescriptor<Exercise>()).compactMap { exercise in exercise.catalogID.map { ($0, exercise) } },
            uniquingKeysWith: { first, _ in first }
        )
        let duplicate = try #require(entry.makeTemplate(exercisesByID: exercisesByID))
        duplicate.createdAtValue = .now.addingTimeInterval(60)
        context.insert(duplicate)
        let program = Program(programLengthWeeks: 1, templateProgram: duplicate)
        context.insert(program)
        try context.save()
        let workoutsBefore = try context.fetchCount(FetchDescriptor<TemplateWorkout>())

        try TemplateCatalog.seed(in: context)

        #expect(try catalogTemplates(in: context, id: entry.id).count == 1)
        #expect(program.templateProgram === original)
        // The duplicate's workouts went with it.
        #expect(try context.fetchCount(FetchDescriptor<TemplateWorkout>()) == workoutsBefore - entry.workouts.count)
    }

    @Test("Deleting a program deletes everything under it")
    func programDeleteCascades() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let template = try #require(try context.fetch(FetchDescriptor<TemplateProgram>()).first)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        context.insert(program)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSet>()) > 0)

        context.delete(program)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<ProgramWeek>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSet>()) == 0)
        // Shared rows survive.
        #expect(try context.fetchCount(FetchDescriptor<TemplateProgram>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) > 0)
    }

    @Test("Removing a set deletes its row instead of orphaning it")
    func removedSetIsDeleted() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let exercise = try #require(try context.fetch(FetchDescriptor<Exercise>()).first)
        let workoutExercise = WorkoutExercise(exercise: exercise, order: 0)
        context.insert(workoutExercise)
        _ = workoutExercise.addSet()
        _ = workoutExercise.addSet()
        try context.save()

        workoutExercise.removeLastSet()
        try context.save()

        #expect(workoutExercise.totalSets == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSet>()) == 1)
    }

    @Test("Children link back to their parents")
    func inversesAreSet() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let template = try #require(try context.fetch(FetchDescriptor<TemplateProgram>()).first)
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        context.insert(program)
        try context.save()

        let week = try #require(program.programWeeks.first)
        let workout = try #require(week.workouts.first)
        let workoutExercise = try #require(workout.workoutExercises.first)
        let workoutSet = try #require(workoutExercise.workoutSets.first)
        #expect(week.programValue === program)
        #expect(workout.programWeekValue === week)
        #expect(workoutExercise.workoutValue === workout)
        #expect(workoutSet.workoutExerciseValue === workoutExercise)
        #expect(template.programsValue?.contains { $0 === program } == true)
    }

    @Test("The schema opens with CloudKit, so every model follows CloudKit's rules")
    func schemaOpensWithCloudKit() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let configuration = ModelConfiguration(
            schema: PowerJackSchema.schema,
            url: url,
            cloudKitDatabase: .private(PowerJackSchema.cloudKitContainerID)
        )

        // SwiftData refuses CloudKit when a property lacks a default, a relationship
        // isn't optional, or an inverse is missing.
        _ = try ModelContainer(for: PowerJackSchema.schema, configurations: [configuration])
    }

    @Test("Previews and tests never sync with iCloud")
    func inMemoryStoreNeverSyncs() {
        let store = PowerJackStore(inMemory: true)
        #expect(!store.syncsWithICloud)
    }

    // Returns the container, not its context: the test must keep the container alive.
    private func seededContainer() throws -> ModelContainer {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        try ExerciseCatalog.seed(in: container.mainContext)
        try TemplateCatalog.seed(in: container.mainContext)
        return container
    }

    private func catalogExercises(in context: ModelContext, id: String) throws -> [Exercise] {
        try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == id }))
    }

    private func catalogTemplates(in context: ModelContext, id: String) throws -> [TemplateProgram] {
        try context.fetch(FetchDescriptor<TemplateProgram>(predicate: #Predicate { $0.catalogID == id }))
    }
}
