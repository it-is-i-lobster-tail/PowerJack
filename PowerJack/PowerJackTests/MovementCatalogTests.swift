import CoreData
import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct MovementCatalogTests {
    @Test("The shared store exposes additive exercise metadata and optional inverse relationships")
    func sharedCloudModel() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: PowerJackSchema.modelTypes))
        let exercise = try #require(model.entitiesByName["Exercise"])
        for key in ["movementPattern", "executionStyle"] {
            #expect(exercise.attributesByName[key]?.isOptional == true)
        }
        for entityName in ["Joint", "JointMovement", "ExerciseJointAction"] {
            let entity = try #require(model.entitiesByName[entityName])
            #expect(entity.uniquenessConstraints.isEmpty)
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.isOptional)
                #expect(relationship.inverseRelationship?.inverseRelationship === relationship)
            }
        }
    }

    @Test("Every shipped exercise has its primary actions in the stored vocabulary")
    func catalogCoverage() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(Set(exercises.compactMap(\.catalogID)).count == ExerciseCatalog.entries.count)
        try verifyProfiles(exercises)
        let bench = try #require(exercises.first { $0.catalogID == "barbell-bench-press" })
        #expect(bench.movementPattern == .horizontalPress && bench.executionStyle == .controlled)
        #expect(Set((bench.jointActions ?? []).compactMap { $0.movement?.key }) == ["shoulder.horizontalAdduction", "elbow.extension"])
        let plank = try #require(exercises.first { $0.catalogID == "side-plank" })
        #expect(plank.executionStyle == .isometric && plank.movementPattern == .resistLateralFlexion)
        #expect(plank.jointActions?.first?.role == .resists)
        #expect(plank.jointActions?.first?.movement?.key == "trunk.lateralFlexion")
        for (id, pattern, movements) in [
            ("cable-chest-fly", MovementPattern.chestFly, ["shoulder.horizontalAdduction"]),
            ("barbell-back-squat", .squat, ["knee.extension", "hip.extension"]),
            ("barbell-romanian-deadlift", .hipHinge, ["hip.extension"]),
            ("cable-woodchop", .trunkRotation, ["trunk.rotation"])
        ] {
            let lift = try #require(exercises.first { $0.catalogID == id })
            #expect(lift.movementPattern == pattern && lift.executionStyle == .controlled)
            #expect(Set((lift.jointActions ?? []).compactMap { $0.movement?.key }) == Set(movements))
            #expect((lift.jointActions ?? []).allSatisfy { $0.role == .produces })
        }
        let originalIDs = try context.fetch(FetchDescriptor<ExerciseJointAction>()).map(\.instanceID)
        try ExerciseCatalog.seed(in: context)
        #expect(Set(try context.fetch(FetchDescriptor<ExerciseJointAction>()).map(\.instanceID)) == Set(originalIDs))
        #expect(try !ExerciseCatalog.removeDuplicates(in: context))
    }

    private func verifyProfiles(_ exercises: [Exercise]) throws {
        for entry in ExerciseCatalog.entries {
            let exercise = try #require(exercises.first { $0.catalogID == entry.id })
            let actions = exercise.jointActions ?? []
            #expect(exercise.movementPattern == entry.profile.pattern && exercise.executionStyle == entry.profile.style)
            #expect(!actions.isEmpty && actions.count == entry.profile.movements.count)
            #expect(Set(actions.compactMap { $0.movement?.key }) == Set(entry.profile.movements))
            for action in actions {
                #expect(action.role == entry.profile.role && action.exercise === exercise)
                let movement = try #require(action.movement)
                let joint = try #require(movement.joint)
                #expect(movement.key.hasPrefix(joint.key + "."))
            }
        }
    }

    @Test("A late import merges vocabulary and repairs detached assignments")
    func lateImport() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        let bench = try #require(try context.fetch(FetchDescriptor<Exercise>()).first { $0.catalogID == "barbell-bench-press" })
        let oldAction = try #require(bench.jointActions?.first)
        let obsolete = ExerciseJointAction(key: "barbell-bench-press:resists:elbow.extension", role: .resists)
        context.insert(obsolete)
        obsolete.exercise = bench
        obsolete.movement = oldAction.movement
        let otherDevice = try PowerJackSchema.makeModelContainer(inMemory: true)
        try ExerciseCatalog.seed(in: otherDevice.mainContext)
        let source = try #require(try otherDevice.mainContext.fetch(FetchDescriptor<Exercise>()).first { $0.catalogID == bench.catalogID })
        let copy = try #require(ExerciseCatalog.entries.first { $0.id == source.catalogID }).makeExercise()
        context.insert(copy)
        // Import the independently seeded identities and their relationships.
        for remote in source.jointActions ?? [] {
            let fromMovement = try #require(remote.movement)
            let fromJoint = try #require(fromMovement.joint)
            let joint = Joint(key: fromJoint.key)
            joint.instanceID = fromJoint.instanceID
            let movement = JointMovement(key: fromMovement.key)
            movement.instanceID = fromMovement.instanceID
            let action = ExerciseJointAction(key: remote.key, role: remote.role)
            action.instanceID = remote.instanceID
            context.insert(joint)
            context.insert(movement)
            context.insert(action)
            movement.joint = joint
            action.movement = movement
            action.exercise = copy
        }
        oldAction.exercise = nil
        oldAction.movement = nil
        try context.save()

        #expect(try ExerciseCatalog.removeDuplicates(in: context))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Joint>()) == MovementCatalog.vocabulary.count)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == ExerciseCatalog.entries.count)
        #expect(try context.fetchCount(FetchDescriptor<JointMovement>()) == MovementCatalog.vocabulary.flatMap(\.movements).count)
        try verifyProfiles(try context.fetch(FetchDescriptor<Exercise>()))
        let total = try context.fetchCount(FetchDescriptor<ExerciseJointAction>())
        let vocabularySize = try context.fetchCount(FetchDescriptor<JointMovement>())
        context.delete(bench)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ExerciseJointAction>()) == total - 2)
        #expect(try context.fetchCount(FetchDescriptor<JointMovement>()) == vocabularySize)
    }

    @Test("A new custom Weighted Dips keeps its own identity on phone and Watch")
    func sameNameCustom() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let custom = Exercise(exerciseName: "Weighted Dips", exerciseEquipment: .machine, primaryMuscleFocus: .triceps, userCreated: true)
        custom.assignSyncID()
        context.insert(custom)
        try ExerciseCatalog.seed(in: context)
        #expect(custom.catalogID == nil && custom.userCreated && custom.movementPattern == nil)
        #expect((custom.jointActions ?? []).isEmpty)
        let watch = try PowerJackSchema.makeModelContainer(inMemory: true)
        let copy = Exercise(snapshot: try #require(custom.syncState))
        watch.mainContext.insert(copy)
        try ExerciseCatalog.seed(in: watch.mainContext)
        #expect(copy.catalogID == nil && copy.keepsCustomIdentity && copy.syncKey == custom.syncKey)
    }

    @Test("A watch receiving the existing snapshot format gets stored movement metadata")
    func watchSnapshot() throws {
        let devices = try TwoDevices()
        try devices.sendProgram()
        let watchExercises = try devices.watchContext.fetch(FetchDescriptor<Exercise>())
        #expect(!watchExercises.isEmpty)
        for exercise in watchExercises where exercise.catalogID != nil {
            #expect(exercise.movementPattern != nil && exercise.executionStyle != nil)
            #expect(exercise.jointActions?.isEmpty == false)
        }
    }

    @Test("An upgraded store reopens with metadata and preserves custom exercises and history")
    func upgradeAndReopen() throws {
        let fixture = try #require(UpgradeFixture.bundled.last)
        let url = URL.temporaryDirectory.appending(path: "movement-upgrade-\(UUID().uuidString).store")
        try FileManager.default.copyItem(at: fixture.store, to: url)
        let config = ModelConfiguration(schema: PowerJackSchema.schema, url: url, cloudKitDatabase: .none)
        let saved = try JSONDecoder().decode(UpgradeManifest.self, from: Data(contentsOf: fixture.manifest))
        do {
            let container = try ModelContainer(for: PowerJackSchema.schema, configurations: [config])
            try ExerciseCatalog.seed(in: container.mainContext)
        }
        let reopened = try ModelContainer(for: PowerJackSchema.schema, configurations: [config])
        let context = reopened.mainContext
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        try verifyProfiles(exercises)
        let custom = try #require(exercises.first { $0.userCreated })
        #expect(custom.executionStyle == nil && custom.movementPattern == nil)
        #expect(custom.jointActions?.isEmpty != false)
        #expect(try UpgradeManifest(context: context) == saved)
    }
}
