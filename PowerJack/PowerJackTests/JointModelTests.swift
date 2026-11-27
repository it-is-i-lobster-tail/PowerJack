import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct JointModelTests {
    private let anatomy = JointAnatomy.bundled

    // MARK: - Anatomy file

    @Test("Each joint does only what its type allows, and every movement names its muscles")
    func anatomyFile() {
        #expect(anatomy.joints.map(\.key) == ["shoulder", "scapula", "elbow", "forearm", "wrist", "trunk", "neck", "hip", "knee", "ankle"])
        for joint in anatomy.joints {
            #expect(!joint.movements.isEmpty && Set(joint.movements).isSubset(of: anatomy.movements(of: joint.type)), "\(joint.key)")
        }
        #expect(!anatomy.movements(of: .hinge).contains("abduction"))
        for key in anatomy.movementKeys {
            #expect(anatomy.muscles(for: key).contains(where: \.isPrime), "\(key)")
            #expect(anatomy.movementKeys.contains(anatomy.opposite(of: key)), "\(key)")
        }
        #expect(anatomy.opposite(of: "elbow.flexion") == "elbow.extension")
        #expect(anatomy.opposite(of: "trunk.rotation") == "trunk.rotation")
        let curl = anatomy.muscles(for: "elbow.flexion")
        #expect(Set(curl.filter(\.isPrime).map(\.name)) == ["biceps brachii", "brachialis"])
        #expect(curl.first { !$0.isPrime }?.group == .forearms)
    }

    @Test("Lifter words name joint movements", arguments: [
        ("rear delts", ["shoulder.horizontalAbduction"]), ("Side Delt raises", ["shoulder.abduction"]),
        ("lats", ["shoulder.adduction", "shoulder.extension"]), ("upper chest", ["shoulder.flexion", "shoulder.horizontalAdduction"]),
        ("lower back", ["trunk.extension"]), ("posterior chain", ["hip.extension", "knee.flexion"]), ("bench press", []),
    ])
    func terms(text: String, movements: [String]) {
        #expect(ExerciseQuery(text).movements == Set(movements))
    }

    @Test("Every lifter word is written the way queries are read, and names known movements")
    func termSpelling() throws {
        let data = try Data(contentsOf: try #require(Bundle.main.url(forResource: "MovementAnatomy", withExtension: "json")))
        let terms = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])["terms"] as? [String: [String]]
        for (term, movements) in try #require(terms) {
            #expect(ExerciseQuery.words(term).joined(separator: " ") == term)
            #expect(Set(movements).isSubset(of: anatomy.movementKeys), "\(term)")
        }
    }

    // MARK: - Catalog

    /// Listed muscles that no joint action explains. Forearms grip any held load, so they never need one.
    private static let unexplained: [String: Set<Muscle>] = [
        // The push-up part, which earlier versions never stored.
        "burpee": [.chest, .shoulders],
        // Shoulders steady the arms.
        "ab-wheel-rollout": [.shoulders], "mountain-climber": [.shoulders],
        "cable-overhead-extension": [.shoulders], "dumbbell-triceps-extension": [.shoulders], "barbell-skull-crusher": [.shoulders],
    ]

    @Test("Every built-in joint action is allowed by its joint's type and weighs 1 or 0.5")
    func catalogActions() {
        let allowed = Set(anatomy.movementKeys)
        for entry in ExerciseCatalog.entries {
            #expect(!entry.profile.actions.isEmpty, "\(entry.id)")
            for action in entry.profile.actions {
                #expect(allowed.contains(action.movement) && [0.5, 1].contains(action.weight), "\(entry.id) \(action.movement)")
            }
        }
    }

    @Test("Every built-in's muscles follow from its joint actions")
    func derivedMuscles() {
        for entry in ExerciseCatalog.entries {
            let muscles = ExerciseStructure(actions: entry.profile.actions, pattern: nil).muscles
            #expect(muscles[entry.primaryMuscle] == muscles.values.max(), "\(entry.id) \(muscles)")
            let explained = Set(entry.secondaryMuscles).subtracting([.forearms]).subtracting(Self.unexplained[entry.id] ?? [])
            #expect(explained.isSubset(of: muscles.keys), "\(entry.id) \(muscles)")
            #expect(Self.unexplained[entry.id]?.isDisjoint(with: muscles.keys) ?? true, "\(entry.id) no longer needs its exception")
        }
    }

    /// What earlier versions stored for each built-in: pattern, role, then movements.
    /// A device still on one of them rewrites any row that differs, so these never change.
    private static let stored: [String: String] = [
        "barbell-bench-press": "horizontalPress produces elbow.extension shoulder.horizontalAdduction",
        "incline-barbell-bench-press": "horizontalPress produces elbow.extension shoulder.horizontalAdduction",
        "dumbbell-bench-press": "horizontalPress produces elbow.extension shoulder.horizontalAdduction",
        "incline-dumbbell-bench-press": "horizontalPress produces elbow.extension shoulder.horizontalAdduction",
        "cable-chest-fly": "chestFly produces shoulder.horizontalAdduction",
        "push-up": "horizontalPress produces elbow.extension shoulder.horizontalAdduction",
        "pull-up": "verticalPull produces elbow.flexion shoulder.adduction",
        "chin-up": "verticalPull produces elbow.flexion shoulder.extension",
        "lat-pulldown": "verticalPull produces elbow.flexion shoulder.adduction",
        "seated-cable-row": "horizontalPull produces elbow.flexion scapula.retraction shoulder.extension",
        "barbell-row": "horizontalPull produces elbow.flexion scapula.retraction shoulder.extension",
        "one-arm-dumbbell-row": "horizontalPull produces elbow.flexion scapula.retraction shoulder.extension",
        "barbell-deadlift": "hipHinge produces hip.extension knee.extension",
        "barbell-overhead-press": "overheadPress produces elbow.extension scapula.upwardRotation shoulder.abduction",
        "dumbbell-shoulder-press": "overheadPress produces elbow.extension scapula.upwardRotation shoulder.abduction",
        "dumbbell-lateral-raise": "lateralRaise produces shoulder.abduction",
        "cable-lateral-raise": "lateralRaise produces shoulder.abduction",
        "dumbbell-reverse-fly": "reverseFly produces shoulder.horizontalAbduction",
        "cable-face-pull": "facePull produces scapula.retraction shoulder.externalRotation shoulder.horizontalAbduction",
        "barbell-curl": "elbowFlexion produces elbow.flexion",
        "dumbbell-curl": "elbowFlexion produces elbow.flexion",
        "dumbbell-hammer-curl": "elbowFlexion produces elbow.flexion",
        "cable-curl": "elbowFlexion produces elbow.flexion",
        "cable-triceps-pushdown": "elbowExtension produces elbow.extension",
        "cable-overhead-extension": "elbowExtension produces elbow.extension",
        "dumbbell-triceps-extension": "elbowExtension produces elbow.extension",
        "barbell-skull-crusher": "elbowExtension produces elbow.extension",
        "barbell-back-squat": "squat produces hip.extension knee.extension",
        "barbell-front-squat": "squat produces hip.extension knee.extension",
        "goblet-squat": "squat produces hip.extension knee.extension",
        "dumbbell-bulgarian-split-squat": "splitSquatLunge produces hip.extension knee.extension",
        "dumbbell-walking-lunge": "splitSquatLunge produces hip.extension knee.extension",
        "leg-press": "legPress produces hip.extension knee.extension",
        "leg-extension": "kneeExtension produces knee.extension",
        "barbell-romanian-deadlift": "hipHinge produces hip.extension",
        "dumbbell-romanian-deadlift": "hipHinge produces hip.extension",
        "seated-leg-curl": "kneeFlexion produces knee.flexion",
        "lying-leg-curl": "kneeFlexion produces knee.flexion",
        "barbell-hip-thrust": "hipThrustBridge produces hip.extension",
        "glute-bridge": "hipThrustBridge produces hip.extension",
        "cable-glute-kickback": "hipExtension produces hip.extension",
        "cable-pull-through": "hipHinge produces hip.extension",
        "standing-calf-raise": "calfRaise produces ankle.plantarflexion",
        "seated-calf-raise": "calfRaise produces ankle.plantarflexion",
        "dumbbell-calf-raise": "calfRaise produces ankle.plantarflexion",
        "crunch": "trunkFlexion produces trunk.flexion",
        "hanging-knee-raise": "hipFlexion produces hip.flexion",
        "cable-crunch": "trunkFlexion produces trunk.flexion",
        "cable-woodchop": "trunkRotation produces trunk.rotation",
        "side-plank": "resistLateralFlexion resists trunk.lateralFlexion",
        "dumbbell-wrist-curl": "wristFlexion produces wrist.flexion",
        "dumbbell-reverse-wrist-curl": "wristExtension produces wrist.extension",
        "dumbbell-goblet-squat": "squat produces hip.extension knee.extension",
        "sliding-leg-curl": "kneeFlexion produces knee.flexion",
        "smith-machine-squat": "squat produces hip.extension knee.extension",
        "smith-machine-hip-thrust": "hipThrustBridge produces hip.extension",
        "cable-hip-abduction": "hipAbduction produces hip.abduction",
        "hack-squat": "squat produces hip.extension knee.extension",
        "chest-supported-dumbbell-row": "horizontalPull produces elbow.flexion scapula.retraction shoulder.extension",
        "dip": "dip produces elbow.extension shoulder.flexion",
        "close-grip-bench-press": "horizontalPress produces elbow.extension shoulder.horizontalAdduction",
        "incline-dumbbell-curl": "elbowFlexion produces elbow.flexion",
        "hanging-leg-raise": "hipFlexion produces hip.flexion",
        "weighted-pull-up": "verticalPull produces elbow.flexion shoulder.adduction",
        "weighted-dip": "dip produces elbow.extension shoulder.flexion",
        "sit-up": "trunkFlexion produces trunk.flexion",
        "lateral-lunge": "splitSquatLunge produces hip.extension knee.extension",
        "ab-wheel-rollout": "resistExtension resists trunk.extension",
        "single-leg-romanian-deadlift": "hipHinge produces hip.extension",
        "mountain-climber": "hipFlexion produces hip.flexion",
        "split-squat": "splitSquatLunge produces hip.extension knee.extension",
        "trap-bar-deadlift": "hipHinge produces hip.extension knee.extension",
        "burpee": "squat produces elbow.extension hip.extension knee.extension",
        "dumbbell-arnold-press": "overheadPress produces elbow.extension scapula.upwardRotation shoulder.abduction",
        "machine-chest-press": "horizontalPress produces elbow.extension shoulder.horizontalAdduction",
        "dumbbell-shrug": "scapularElevation produces scapula.elevation",
        "barbell-good-morning": "hipHinge produces hip.extension",
        "reverse-lunge": "splitSquatLunge produces hip.extension knee.extension",
        "kettlebell-swing": "hipHinge produces hip.extension",
        "ez-bar-preacher-curl": "elbowFlexion produces elbow.flexion",
        "russian-twist": "trunkRotation produces trunk.rotation",
    ]

    @Test("Stored joint actions and patterns stay as earlier versions seeded them")
    func storedMetadataFrozen() throws {
        #expect(Set(Self.stored.keys) == Set(ExerciseCatalog.entries.map(\.id)))
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        try ExerciseCatalog.seed(in: container.mainContext)
        for exercise in try container.mainContext.fetch(FetchDescriptor<Exercise>()) {
            let id = try #require(exercise.catalogID)
            let actions = exercise.jointActions ?? []
            let roles = Set(actions.map(\.role.rawValue))
            let movements = actions.compactMap { $0.movement?.key }.sorted()
            let saved = ([exercise.movementPattern?.rawValue ?? "none"] + roles.sorted() + movements).joined(separator: " ")
            #expect(saved == Self.stored[id], "\(id)")
        }
    }

    // MARK: - Search

    private func seeded() throws -> (ModelContainer, [Exercise], ExerciseSearch.Index) {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        try ExerciseCatalog.seed(in: container.mainContext)
        let exercises = try container.mainContext.fetch(FetchDescriptor<Exercise>())
        return (container, exercises, ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init)))
    }

    private func ranked(_ query: String, _ context: ExerciseSearch.Context = .browse, in exercises: [Exercise],
                        _ index: ExerciseSearch.Index) -> [String] {
        let ids = Dictionary(uniqueKeysWithValues: exercises.map { ($0.searchKey, $0.catalogID ?? $0.exerciseName) })
        return index.rank(ExerciseQuery(query), context: context).compactMap { ids[$0.key] }
    }

    private func key(_ id: String, in exercises: [Exercise]) throws -> String {
        try #require(exercises.first { $0.catalogID == id }).searchKey
    }

    @Test("Change and Substitute rank neighbours by shared joint actions and muscles")
    func neighbours() throws {
        let (container, exercises, index) = try seeded()
        defer { _ = container }
        let change = ranked("", .replacing(source: try key("leg-press", in: exercises), sameEquipment: true), in: exercises, index)
        #expect(try #require(change.firstIndex(of: "hack-squat")) < #require(change.firstIndex(of: "leg-extension")))
        let substitute = ranked("", .replacing(source: try key("dumbbell-reverse-fly", in: exercises), sameEquipment: false), in: exercises, index)
        let facePull = try #require(substitute.firstIndex(of: "cable-face-pull"))
        #expect(facePull < substitute.firstIndex(of: "barbell-overhead-press") ?? substitute.count)
    }

    @Test("Joint words find the lifts that do them, and Burpee is no squat")
    func jointWords() throws {
        let (container, exercises, index) = try seeded()
        defer { _ = container }
        #expect(Set(ranked("rear delts", in: exercises, index).prefix(2)) == ["dumbbell-reverse-fly", "cable-face-pull"])
        #expect(Set(ranked("side delts", in: exercises, index).prefix(2)) == ["dumbbell-lateral-raise", "cable-lateral-raise"])
        #expect(!ranked("front squat", in: exercises, index).contains("burpee"))
        #expect(!ranked("squats", in: exercises, index).contains("burpee"))
    }
}
