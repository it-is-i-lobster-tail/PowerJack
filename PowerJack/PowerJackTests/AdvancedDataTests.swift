import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct AdvancedDataTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try PowerJackSchema.makeModelContainer(inMemory: true)
        context = container.mainContext
        try ExerciseCatalog.seed(in: context)
    }

    private func own(_ name: String, _ equipment: Equipment, _ primary: Muscle) throws -> Exercise {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: equipment, primaryMuscleFocus: primary, userCreated: true)
        context.insert(exercise)
        try context.save()
        return exercise
    }

    private func builtIn(_ id: String) throws -> Exercise {
        try #require(try context.fetch(FetchDescriptor<Exercise>()).first { $0.catalogID == id })
    }

    @Test("Movement and joint type names read as plain words")
    func names() {
        #expect(JointAnatomy.name(ofMovement: "shoulder.horizontalAbduction") == "Horizontal abduction")
        #expect(JointAnatomy.name(ofMovement: "flexion") == "Flexion")
        #expect(JointAnatomy.name(ofMovement: "ballAndSocket") == "Ball and socket")
    }

    @Test("A held action shows on the movement whose muscles hold it")
    func involvement() {
        let squat = JointInvolvement.of(MovementCatalog.Profile.squat.actions)
        #expect(squat == ["knee.extension": .main, "hip.extension": .main, "trunk.flexion": .holds, "trunk.extension": .holds])
        let row = JointInvolvement.of(MovementCatalog.Profile.row.braced.actions)
        #expect(row == ["shoulder.extension": .main, "scapula.retraction": .main, "elbow.flexion": .assisting, "trunk.flexion": .holds])

        // Setting one movement keeps every other action exactly as it was.
        let changed = JointInvolvement.setting("elbow.flexion", to: .main, in: MovementCatalog.Profile.squat.actions)
        #expect(Set(changed) == Set(MovementCatalog.Profile.squat.actions + [.main("elbow.flexion")]))
        let cleared = JointInvolvement.setting("trunk.flexion", to: nil, in: MovementCatalog.Profile.squat.actions)
        #expect(cleared == [.main("knee.extension"), .main("hip.extension"), .assisting("trunk.flexion", .resists)])
        let held = JointInvolvement.setting("trunk.extension", to: .holds, in: [])
        #expect(held == [.main("trunk.flexion", .resists)])
    }

    @Test("Built-ins show the catalog's joints and can't change them")
    func builtInsAreReadOnly() throws {
        let bench = try builtIn("barbell-bench-press")
        var draft = ExerciseDraft(exercise: bench)
        #expect(draft.isBuiltIn)
        let actions = draft.jointActions
        #expect(actions == MovementCatalog.Profile.bench.actions)
        draft.setJoint("knee.extension", to: .main)
        #expect(draft.jointActions == actions)
        #expect(draft.customActions == nil)
    }

    @Test("Joints set by hand save with their weights and replace Moves Like")
    func ownJointsSave() throws {
        let row = try own("Landmine Row", .barbell, .back)
        var draft = ExerciseDraft(exercise: row)
        draft.choose(movesLike: ["catalog:barbell-row"])
        #expect(draft.apply(to: row))
        try context.save()
        #expect(MovesLike.keys(of: row) == ["catalog:barbell-row"])

        // Starts from the Moves Like lift's actions, then the lifter makes the elbow a main action.
        draft = ExerciseDraft(exercise: row)
        #expect(draft.jointActions == MovementCatalog.Profile.bentOverRow.actions)
        draft.setJoint("elbow.flexion", to: .main)
        draft.setJoint("trunk.extension", to: .holds)
        #expect(draft.movesLikeName == "Custom")
        #expect(draft.apply(to: row))
        try context.save()

        let saved = try #require(CustomJointActions.read(row))
        #expect(Set(saved) == [.main("shoulder.extension"), .main("scapula.retraction"), .main("elbow.flexion"),
                               .assisting("trunk.extension", .resists), .main("trunk.flexion", .resists)])
        #expect(MovesLike.keys(of: row).isEmpty)
        #expect(row.movementPattern == .horizontalPull)
        #expect((row.jointActions ?? []).allSatisfy { $0.key.hasPrefix("\(row.syncKey!):custom:") && $0.movement != nil })

        // Search reads the weights back.
        let document = ExerciseSearch.Document(row)
        #expect(document.structure.actions["elbow.flexion"] == 1)
        #expect(document.structure.actions["trunk.extension"] == 1)

        // Reopening keeps them, and an unchanged save leaves the rows alone.
        var reopened = ExerciseDraft(exercise: row)
        #expect(Set(reopened.jointActions) == Set(saved))
        #expect(reopened.movesLikeName == "Custom")
        let keys = Set((row.jointActions ?? []).map(\.key))
        #expect(reopened.apply(to: row))
        #expect(Set((row.jointActions ?? []).map(\.key)) == keys)

        // Picking a Moves Like lift again replaces them.
        reopened.choose(movesLike: ["catalog:barbell-row"])
        #expect(reopened.apply(to: row))
        try context.save()
        #expect(CustomJointActions.read(row) == nil)
        #expect(MovesLike.keys(of: row) == ["catalog:barbell-row"])
    }

    @Test("A new exercise saves the joints set before it was created")
    func newExerciseJoints() throws {
        var draft = ExerciseDraft(name: "Wrist Roller")
        draft.equipment = .cable
        draft.primaryMuscle = .forearms
        draft.setJoint("wrist.flexion", to: .main)
        draft.setJoint("wrist.extension", to: .assisting)
        let exercise = try #require(draft.makeExercise())
        context.insert(exercise)
        draft.applyMovement(to: exercise)
        try context.save()
        #expect(Set(try #require(CustomJointActions.read(exercise))) == [.main("wrist.flexion"), .assisting("wrist.extension")])
    }

    @Test("Catalog reconciliation leaves joints set by hand alone")
    func reconcileKeepsCustomRows() throws {
        let curl = try own("Zottman Curl", .dumbbell, .biceps)
        var draft = ExerciseDraft(exercise: curl)
        draft.setJoint("elbow.flexion", to: .main)
        draft.setJoint("forearm.supination", to: .assisting)
        #expect(draft.apply(to: curl))
        try context.save()

        try MovementCatalog.reconcile(try context.fetch(FetchDescriptor<Exercise>()), in: context)
        try context.save()
        #expect(Set(try #require(CustomJointActions.read(curl))) == [.main("elbow.flexion"), .assisting("forearm.supination")])
    }

    @Test("A new exercise gets its Moves Like pick and secondaries from the name alone, and saves")
    func autoPickWithoutOpeningAdvancedData() async throws {
        var draft = ExerciseDraft(name: "Cable Lateral Raise")
        draft.equipment = .cable
        draft.primaryMuscle = .shoulders
        #expect(draft.wantsMovesLikeProposal)
        let keys = await MovesLike.propose(name: draft.name, equipment: draft.equipment, primary: draft.primaryMuscle)
        #expect(keys == ["catalog:cable-lateral-raise"])
        draft.propose(movesLike: keys)
        #expect(draft.movesLikeName == "Cable Lateral Raise")
        #expect(draft.secondaryMuscles == MovesLike.secondaryMuscles(of: keys, primary: .shoulders))
        let exercise = try #require(draft.makeExercise())
        context.insert(exercise)
        draft.applyMovement(to: exercise)
        try context.save()
        #expect(MovesLike.keys(of: exercise) == keys)

        // A pick with prime movers besides the primary fills the empty secondaries.
        var bench = ExerciseDraft(name: "Paused Bench")
        bench.equipment = .barbell
        bench.primaryMuscle = .chest
        bench.propose(movesLike: await MovesLike.propose(name: bench.name, equipment: .barbell, primary: .chest))
        #expect(bench.movesLike == ["catalog:barbell-bench-press"])
        #expect(!bench.secondaryMuscles.isEmpty)
        #expect(bench.secondaryMuscles == MovesLike.secondaryMuscles(of: bench.movesLike, primary: .chest))
    }

    @Test("The Advanced Data row names the Moves Like picks, else the joints worked")
    func linkDetail() throws {
        var draft = ExerciseDraft(name: "Lean-away Raise")
        #expect(ExerciseAdvancedDataLink.detail(for: draft) == "No joints set")
        draft.choose(movesLike: ["catalog:dumbbell-lateral-raise"])
        #expect(ExerciseAdvancedDataLink.detail(for: draft) == "Moves like Dumbbell Lateral Raise")
        draft.choose(movesLike: ["catalog:dumbbell-lateral-raise", "catalog:barbell-row"])
        #expect(ExerciseAdvancedDataLink.detail(for: draft) == "Moves like Dumbbell Lateral Raise, Barbell Row")
        // Joints set by hand show the joints instead of "Moves like Custom".
        draft.setJoint("knee.extension", to: .main)
        #expect(draft.movesLikeName == "Custom")
        let detail = ExerciseAdvancedDataLink.detail(for: draft)
        #expect(detail == ExerciseJointsView.summary(of: draft) && detail.contains("Knee"))
    }

    @Test("Only the joints a lift works start open, and a new Moves Like pick opens its joints")
    func jointsStartExpanded() throws {
        let bench = ExerciseDraft(exercise: try builtIn("barbell-bench-press"))
        let anatomy = JointAnatomy.bundled
        let benchJoints = ExerciseJointsView.workedJoints(in: bench.jointActions)
        let expected = Set(JointInvolvement.of(MovementCatalog.Profile.bench.actions).keys.compactMap { $0.split(separator: ".").first.map(String.init) })
        #expect(benchJoints == expected)
        #expect(!benchJoints.isEmpty && benchJoints.count < anatomy.joints.count)

        var draft = ExerciseDraft(name: "Mystery Lift")
        #expect(ExerciseJointsView.workedJoints(in: draft.jointActions).isEmpty)
        draft.choose(movesLike: ["catalog:barbell-back-squat"])
        let squat = ExerciseJointsView.workedJoints(in: draft.jointActions)
        #expect(squat.contains("knee") && squat.contains("hip") && !squat.contains("elbow"))
        draft.choose(movesLike: ["catalog:barbell-back-squat", "catalog:barbell-curl"])
        #expect(ExerciseJointsView.workedJoints(in: draft.jointActions) == squat.union(["elbow"]))
    }
}
