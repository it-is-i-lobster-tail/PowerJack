import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct MovesLikeTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try PowerJackSchema.makeModelContainer(inMemory: true)
        context = container.mainContext
        try ExerciseCatalog.seed(in: context)
    }

    private func own(_ name: String, _ equipment: Equipment, _ primary: Muscle, secondary: [Muscle] = []) throws -> Exercise {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: equipment, primaryMuscleFocus: primary,
                                secondaryMuscles: secondary, userCreated: true)
        context.insert(exercise)
        try context.save()
        return exercise
    }

    private func pattern(_ key: String?) -> MovementPattern? { MovesLike.entry(key)?.profile.pattern }

    private func freshDefaults() throws -> UserDefaults {
        let suite = "MovesLikeTests-\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    @Test("A landmine row proposes Barbell Row, and Change from it offers rows first")
    func landmineRow() async throws {
        #expect(MovesLike.clearMatch(name: "Landmine Row", equipment: .barbell, primary: .back) == "catalog:barbell-row")
        #expect(await MovesLike.propose(name: "Landmine Row", equipment: .barbell, primary: .back) == ["catalog:barbell-row"])

        let row = try own("Landmine Row", .barbell, .back)
        var draft = ExerciseDraft(exercise: row)
        draft.propose(movesLike: ["catalog:barbell-row"])
        #expect(draft.apply(to: row))
        try context.save()
        #expect(row.movementPattern == .horizontalPull)
        #expect(Set((row.jointActions ?? []).compactMap { $0.movement?.key }) == ["shoulder.extension", "scapula.retraction", "elbow.flexion"])
        #expect((row.jointActions ?? []).allSatisfy { $0.key.hasPrefix("\(row.syncKey!):barbell-row:produces:") })

        let all = try context.fetch(FetchDescriptor<Exercise>())
        let index = ExerciseSearch.Index(all.map(ExerciseSearch.Document.init))
        let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.searchKey, $0) })
        let neighbours = index.rank(ExerciseQuery(""), context: .replacing(source: row.searchKey, sameEquipment: true))
            .compactMap { byKey[$0.key] }
        let rows = all.filter { $0.catalogID != nil && $0.movementPattern == .horizontalPull }
        #expect(Set(neighbours.prefix(rows.count).map(\.persistentModelID)) == Set(rows.map(\.persistentModelID)))
    }

    @Test("A name with no clear match stays Not set and keeps today's behaviour")
    func noClearMatch() async throws {
        #expect(MovesLike.clearMatch(name: "Friday finisher", equipment: .dumbbell, primary: .shoulders) == nil)
        #expect(MovesLike.candidates(name: "Friday finisher", equipment: .dumbbell, primary: .shoulders).isEmpty)
        #expect((await MovesLike.propose(name: "Friday finisher", equipment: .dumbbell, primary: .shoulders)).isEmpty)
        // Words shared with lifts that move differently are not clear.
        #expect(MovesLike.clearMatch(name: "Bench Dip", equipment: .bodyweight, primary: nil) == nil)
        let choices = MovesLike.candidates(name: "Bench Dip", equipment: .bodyweight, primary: nil).map(\.profile.pattern)
        #expect(choices.contains(.horizontalPress) && choices.contains(.dip))

        let finisher = try own("Friday finisher", .dumbbell, .shoulders, secondary: [.triceps])
        var draft = ExerciseDraft(exercise: finisher)
        #expect(draft.movesLike.isEmpty && draft.wantsMovesLikeProposal)
        draft.propose(movesLike: [])
        #expect(draft.apply(to: finisher))
        #expect(finisher.movementPattern == nil && (finisher.jointActions ?? []).isEmpty)
        let document = ExerciseSearch.Document(finisher)
        #expect(document.structure.actions.isEmpty)
        #expect(document.structure.muscles == [.shoulders: 1, .triceps: 0.5])
    }

    @Test("The primary muscle decides a word several movements share, except when filling in silently")
    func primaryMuscleSettlesCurls() {
        #expect(MovesLike.clearMatch(name: "Spider Curl", equipment: .dumbbell, primary: nil) == nil)
        #expect(pattern(MovesLike.clearMatch(name: "Spider Curl", equipment: .dumbbell, primary: .biceps)) == .elbowFlexion)
        #expect(pattern(MovesLike.clearMatch(name: "Nordic Curl", equipment: .bodyweight, primary: .hamstrings)) == .kneeFlexion)
        #expect(MovesLike.clearMatch(name: "Spider Curl", equipment: .dumbbell, primary: .biceps, strict: true) == nil)
        // A shared word on a lift for another muscle is no match: a sled push is not a push-up.
        #expect(MovesLike.clearMatch(name: "Sled Push", equipment: .bodyweight, primary: .quads) == nil)
        #expect(MovesLike.clearMatch(name: "Paused Bench", equipment: .barbell, primary: .chest, strict: true)
            == "catalog:barbell-bench-press")
    }

    @Test("Chosen muscles are never overwritten, and empty secondaries follow the joint actions")
    func muscles() throws {
        var empty = ExerciseDraft(name: "Landmine Row")
        empty.primaryMuscle = .back
        empty.propose(movesLike: ["catalog:barbell-row"])
        #expect(empty.primaryMuscle == .back)
        #expect(empty.secondaryMuscles == [.biceps, .abs], "prime movers only: no chest for a row")
        // A new proposal replaces muscles that were only proposed.
        empty.propose(movesLike: ["catalog:barbell-bench-press"])
        #expect(empty.secondaryMuscles == MovesLike.secondaryMuscles(of: ["catalog:barbell-bench-press"], primary: .back))

        var chosen = ExerciseDraft(name: "Landmine Row")
        chosen.primaryMuscle = .back
        chosen.secondaryMuscles = [.forearms]
        chosen.propose(movesLike: ["catalog:barbell-row"])
        #expect(chosen.movesLike == ["catalog:barbell-row"])
        #expect(chosen.secondaryMuscles == [.forearms])

        // No primary yet: it stays empty, and picking it later drops it from the proposed list.
        var later = ExerciseDraft(name: "Paused Bench")
        later.propose(movesLike: ["catalog:barbell-bench-press"])
        #expect(later.primaryMuscle == nil && later.secondaryMuscles.contains(.chest))
        later.primaryMuscle = .chest
        later.removePrimaryFromSecondary()
        #expect(!later.secondaryMuscles.contains(.chest))
        later.propose(movesLike: ["catalog:incline-barbell-bench-press"])
        #expect(!later.secondaryMuscles.isEmpty && !later.secondaryMuscles.contains(.chest))

        // The lifter's pick stops proposals, and None clears the movement but keeps the muscles.
        let muscles = later.secondaryMuscles
        later.choose(movesLike: [])
        later.propose(movesLike: ["catalog:barbell-bench-press"])
        #expect(later.movesLike.isEmpty && !later.wantsMovesLikeProposal)
        #expect(later.secondaryMuscles == muscles)
    }

    @Test("A new exercise saves its movement, reopens with it, and None clears it")
    func saveAndReopen() throws {
        var draft = ExerciseDraft(name: "Paused Bench")
        draft.equipment = .barbell
        draft.primaryMuscle = .chest
        draft.propose(movesLike: ["catalog:barbell-bench-press"])
        let exercise = try #require(draft.makeExercise())
        context.insert(exercise)
        draft.applyMovement(to: exercise)
        try context.save()
        #expect(exercise.movementPattern == .horizontalPress && exercise.executionStyle == .controlled)
        #expect((exercise.jointActions ?? []).count == 2)

        var reopened = ExerciseDraft(exercise: exercise)
        #expect(reopened.movesLike == ["catalog:barbell-bench-press"] && reopened.isMovesLikeChosen)
        #expect(ExerciseSearch.Document(exercise).structure == ExerciseSearch.Document(MovesLike.entry("catalog:barbell-bench-press")!).structure)
        let ids = Set((exercise.jointActions ?? []).map(\.instanceID))
        #expect(reopened.apply(to: exercise))
        #expect(Set((exercise.jointActions ?? []).map(\.instanceID)) == ids, "an unchanged movement is not rewritten")

        reopened.choose(movesLike: [])
        #expect(reopened.apply(to: exercise))
        try context.save()
        #expect(exercise.movementPattern == nil && exercise.executionStyle == nil)
        #expect((exercise.jointActions ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ExerciseJointAction>()).allSatisfy { $0.exercise != nil })
    }

    @Test("A lift picked on other equipment reopens with that lift's name")
    func pickedLiftKeepsItsName() throws {
        let row = try own("Landmine Row", .barbell, .back)
        var draft = ExerciseDraft(exercise: row)
        draft.choose(movesLike: ["catalog:seated-cable-row"])
        #expect(draft.apply(to: row))
        try context.save()
        // Barbell Row stores the same rows, on the exercise's own equipment, but the pick wins.
        #expect(ExerciseDraft(exercise: row).movesLike == ["catalog:seated-cable-row"])
    }

    @Test("Built-in exercises keep the catalog's movement")
    func builtInsUntouched() throws {
        let bench = try #require(try context.fetch(FetchDescriptor<Exercise>()).first { $0.catalogID == "barbell-bench-press" })
        var draft = ExerciseDraft(exercise: bench)
        #expect(!draft.wantsMovesLikeProposal && draft.movesLike.isEmpty)
        draft.choose(movesLike: ["catalog:barbell-row"])
        #expect(draft.apply(to: bench))
        #expect(bench.movementPattern == .horizontalPress)
    }

    @Test("Catalog reconciliation leaves own exercises' joint actions alone")
    func reconcileKeepsOwnRows() throws {
        let row = try own("Landmine Row", .barbell, .back)
        MovesLike.copy(["catalog:barbell-row"], to: row, in: context)
        try context.save()
        let ids = Set((row.jointActions ?? []).map(\.instanceID))
        #expect(ids.count == 3)
        try ExerciseCatalog.seed(in: context)
        #expect(!(try ExerciseCatalog.removeDuplicates(in: context)))
        #expect(Set((row.jointActions ?? []).map(\.instanceID)) == ids)
        #expect(row.movementPattern == .horizontalPull)
    }

    @Test("Joint words find an own exercise that moves like a built-in")
    func jointWords() throws {
        let fly = try own("Prone Y Raise", .dumbbell, .shoulders)
        MovesLike.copy(["catalog:dumbbell-reverse-fly"], to: fly, in: context)
        try context.save()
        let index = ExerciseSearch.Index([ExerciseSearch.Document(fly)], encoder: nil)
        let movements = ExerciseQuery("rear delts").movements
        #expect(!movements.isEmpty)
        #expect(index.keys(doing: movements, among: [fly.searchKey]) == [fly.searchKey])
    }

    @Test("The pass over earlier own exercises fills only clear matches, once")
    func fillExisting() throws {
        let paused = try own("Paused Bench", .barbell, .chest)
        let finisher = try own("Friday finisher", .dumbbell, .shoulders)
        let dip = try own("Bench Dip", .bodyweight, .triceps)
        let push = try own("Sled Push", .bodyweight, .quads)
        let curl = try own("Spider Curl", .dumbbell, .biceps)
        let defaults = try freshDefaults()

        #expect(try MovesLike.fillExisting(in: context, defaults: defaults) == ["Paused Bench"])
        #expect(paused.movementPattern == .horizontalPress && (paused.jointActions ?? []).count == 2)
        #expect(MovesLike.keys(of: paused) == ["catalog:barbell-bench-press"])
        for unset in [finisher, dip, push, curl] {
            #expect(unset.movementPattern == nil && (unset.jointActions ?? []).isEmpty, "\(unset.exerciseName)")
        }

        // Once per device.
        let rows = Set(try context.fetch(FetchDescriptor<ExerciseJointAction>()).map(\.instanceID))
        #expect(try MovesLike.fillExisting(in: context, defaults: defaults).isEmpty)
        // And idempotent even when it runs again: filled lifts are skipped.
        #expect(try MovesLike.fillExisting(in: context, defaults: try freshDefaults()).isEmpty)
        #expect(Set(try context.fetch(FetchDescriptor<ExerciseJointAction>()).map(\.instanceID)) == rows)
    }

    @Test("A single pick saved by an earlier version reads back as the first, with its old row keys")
    func singlePickReadsAsFirst() throws {
        let row = try own("Landmine Row", .barbell, .back)
        MovesLike.copy(["catalog:barbell-row"], to: row, in: context)
        try context.save()
        // One pick keeps the five-part keys earlier versions wrote and read.
        #expect((row.jointActions ?? []).allSatisfy { $0.key.split(separator: ":").count == 5 })
        #expect(MovesLike.keys(of: row) == ["catalog:barbell-row"])
        #expect(ExerciseDraft(exercise: row).movesLike == ["catalog:barbell-row"])
    }

    @Test("Up to three picks save and read back in order, and a fourth is dropped")
    func threePicksInOrder() throws {
        let picks = ["catalog:dumbbell-lateral-raise", "catalog:barbell-row", "catalog:barbell-curl"]
        let raise = try own("Lean-away Raise", .cable, .shoulders)
        var draft = ExerciseDraft(exercise: raise)
        draft.choose(movesLike: picks + ["catalog:barbell-bench-press"])
        #expect(draft.movesLike == picks)
        #expect(draft.apply(to: raise))
        try context.save()
        #expect(MovesLike.keys(of: raise) == picks)
        #expect(raise.movementPattern == MovesLike.entry(picks[0])?.profile.pattern)
        #expect(ExerciseDraft(exercise: raise).movesLikeName == "Dumbbell Lateral Raise, Barbell Row, Barbell Curl")

        // Reordered picks read back in their new order.
        var reordered = ExerciseDraft(exercise: raise)
        reordered.choose(movesLike: picks.reversed())
        #expect(reordered.apply(to: raise))
        try context.save()
        #expect(MovesLike.keys(of: raise) == picks.reversed())

        MovesLike.copy(picks + ["catalog:barbell-bench-press"], to: raise, in: context)
        #expect(MovesLike.keys(of: raise) == picks)
    }

    @Test("Several picks' joint actions merge, the strongest use of each movement winning")
    func mergedActions() {
        let merged = MovesLike.actions(of: ["catalog:barbell-row", "catalog:barbell-curl"])
        let byMovement = Dictionary(uniqueKeysWithValues: merged.map { ($0.movement, $0.weight) })
        // The row assists with the elbow; the curl's main elbow flexion wins.
        #expect(byMovement["elbow.flexion"] == 1)
        #expect(byMovement["shoulder.extension"] == 1 && byMovement["scapula.retraction"] == 1)
        #expect(merged.count == Set(merged.map(\.movement)).count)
        #expect(MovesLike.actions(of: ["catalog:barbell-curl"]) == MovementCatalog.Profile.curl.actions)
        #expect(MovesLike.secondaryMuscles(of: ["catalog:barbell-curl", "catalog:barbell-bench-press"], primary: .biceps)
            .contains(.triceps))
    }

    @Test("Search reads every pick")
    func searchUsesAllPicks() throws {
        let hybrid = try own("Curl to Press", .dumbbell, .biceps)
        MovesLike.copy(["catalog:dumbbell-curl", "catalog:barbell-bench-press"], to: hybrid, in: context)
        try context.save()
        let document = ExerciseSearch.Document(hybrid)
        let keys = ["catalog:dumbbell-curl", "catalog:barbell-bench-press"]
        #expect(document.structure == ExerciseStructure(actions: MovesLike.actions(of: keys),
                                                        pattern: MovesLike.entry(keys[0])?.profile.family?.rawValue))
        let movements = Set(document.actions.map { String($0.split(separator: " ")[1]) })
        #expect(movements.isSuperset(of: MovementCatalog.Profile.curl.storedMovements + MovementCatalog.Profile.bench.storedMovements))
        #expect(document.actions == document.actions.uniqued())
    }
}
