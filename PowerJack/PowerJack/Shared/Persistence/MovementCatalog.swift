import Foundation
import SwiftData

enum MovementCatalog {
    struct Profile {
        /// Stored on the exercise, as earlier versions seeded it. See `storedMovements`.
        let pattern: MovementPattern
        /// What the lift does at each joint. Search and Advanced Data read these.
        private(set) var actions: [JointAction]
        let style: ExecutionStyle
        /// The role of the stored rows.
        let role: JointActionRole
        /// A full-body lift, which search keeps out of its stored pattern's family.
        let isFullBody: Bool
        /// A device on an earlier version rewrites joint action rows and patterns it doesn't
        /// expect, and iCloud would carry each rewrite back and forth. So the stored rows stay as
        /// earlier versions seeded them: the profile's first actions in its role. Actions added
        /// or reweighted later (`adding`, `actions(_:)`) are app data only.
        let storedMovements: [String]

        init(pattern: MovementPattern, actions: [JointAction], style: ExecutionStyle = .controlled,
             role: JointActionRole = .produces, isFullBody: Bool = false) {
            self.pattern = pattern
            self.actions = actions
            self.style = style
            self.role = role
            self.isFullBody = isFullBody
            storedMovements = actions.filter { $0.role == role }.map(\.movement)
        }

        /// The same lift with more joint work. The stored rows stay as they were.
        func adding(_ more: JointAction...) -> Self {
            var profile = self
            profile.actions += more
            return profile
        }

        /// The same lift doing these actions instead. The stored rows stay as they were.
        func actions(_ actions: JointAction...) -> Self {
            var profile = self
            profile.actions = actions
            return profile
        }

        /// The movement family search groups the lift with.
        var family: MovementPattern? { isFullBody ? nil : pattern }

        /// The trunk braced against extension, as abs hold it under a load overhead or out front.
        var braced: Self { adding(.assisting("trunk.extension", .resists)) }

        /// The back held straight against a load that pulls the trunk forward, as the spinal
        /// erectors hold it in a squat or a bent-over row.
        var backHeld: Self { adding(.assisting("trunk.flexion", .resists)) }

        static let shrug = Self(pattern: .scapularElevation, actions: [.main("scapula.elevation")])
        /// The lats pull the arms back in as the wheel returns.
        static let rollout = Self(pattern: .resistExtension, actions: [.main("trunk.extension", .resists)], role: .resists)
            .adding(.assisting("shoulder.extension"))
        static let swing = Self(pattern: .hipHinge, actions: [.main("hip.extension"), .assisting("trunk.flexion", .resists)], style: .explosive).braced
        /// The push-up in the middle works the chest.
        static let burpee = Self(pattern: .squat, actions: [.main("knee.extension"), .main("hip.extension"), .assisting("elbow.extension")],
                                 style: .explosive, isFullBody: true)
            .adding(.assisting("shoulder.horizontalAdduction"))
        static let bench = Self(pattern: .horizontalPress, actions: [.main("shoulder.horizontalAdduction"), .assisting("elbow.extension")])
        /// An incline press raises the arms forward as well as across.
        static let inclineBench = bench.adding(.assisting("shoulder.flexion"))
        /// Off the floor the shoulder blades are free to push forward at the top.
        static let pushUp = bench.adding(.assisting("scapula.protraction")).braced
        static let closeGripBench = Self(pattern: .horizontalPress, actions: [.main("elbow.extension"), .main("shoulder.horizontalAdduction")])
        static let fly = Self(pattern: .chestFly, actions: [.main("shoulder.horizontalAdduction")])
        static let inclineFly = fly.adding(.assisting("shoulder.flexion"))
        /// Pulling the body up draws the shoulder blades down.
        static let pullUp = Self(pattern: .verticalPull, actions: [.main("shoulder.adduction"), .assisting("elbow.flexion")])
            .adding(.assisting("scapula.depression"))
        static let chinUp = Self(pattern: .verticalPull, actions: [.main("shoulder.extension"), .main("elbow.flexion")])
            .adding(.assisting("scapula.depression")).braced
        static let row = Self(pattern: .horizontalPull, actions: [.main("shoulder.extension"), .main("scapula.retraction"), .assisting("elbow.flexion")])
        /// Bent over, the back holds against the load as well as the abs bracing.
        static let bentOverRow = row.backHeld.braced
        /// One arm pulling twists the trunk, which holds still against it.
        static let oneArmRow = row.adding(.assisting("trunk.rotation", .resists))
        /// Hanging under the bar, the body holds a plank: abs braced, glutes holding the hips straight.
        static let invertedRow = row.braced.adding(.assisting("hip.flexion", .resists))
        static let deadlift = Self(pattern: .hipHinge, actions: [.main("hip.extension"), .assisting("knee.extension"), .main("trunk.flexion", .resists)])
        static let trapBarDeadlift = Self(pattern: .hipHinge, actions: [.main("knee.extension"), .main("hip.extension"), .assisting("trunk.flexion", .resists)])
        /// A deadlift from a wide stance with the knees pushed out: the inner thighs help the hips stand up.
        static let sumoDeadlift = deadlift.adding(.assisting("hip.adduction"))
        static let overhead = Self(pattern: .overheadPress, actions: [
            .main("shoulder.abduction"), .assisting("elbow.extension"), .assisting("scapula.upwardRotation"),
        ])
        /// A bar pressed from the front of the shoulders raises the arms forward more than out to the side.
        static let frontPress = overhead.actions(
            .main("shoulder.flexion"), .assisting("shoulder.abduction"), .assisting("elbow.extension"), .assisting("scapula.upwardRotation")
        ).braced
        /// Starts with the palms in and the elbows in front, then turns the arms out as it presses.
        static let arnoldPress = overhead.adding(.assisting("shoulder.flexion"), .assisting("shoulder.externalRotation"))
        /// A load on one side overhead tips the trunk, which holds against bending sideways.
        static let singleArmPress = overhead.braced.adding(.assisting("trunk.lateralFlexion", .resists))
        /// Past the first part of the raise, the shoulder blade turns up with the arm.
        static let lateralRaise = Self(pattern: .lateralRaise, actions: [.main("shoulder.abduction")])
            .adding(.assisting("scapula.upwardRotation"))
        static let reverseFly = Self(pattern: .reverseFly, actions: [.main("shoulder.horizontalAbduction")])
            .adding(.assisting("scapula.retraction"))
        static let facePull = Self(pattern: .facePull, actions: [
            .main("shoulder.horizontalAbduction"), .assisting("shoulder.externalRotation"), .assisting("scapula.retraction"),
        ])
        static let curl = Self(pattern: .elbowFlexion, actions: [.main("elbow.flexion")])
        /// The palms turn up as the dumbbells rise.
        static let supinatingCurl = curl.adding(.assisting("forearm.supination"))
        static let triceps = Self(pattern: .elbowExtension, actions: [.main("elbow.extension")])
        static let squat = Self(pattern: .squat, actions: [.main("knee.extension"), .main("hip.extension")]).braced.backHeld
        /// The pad holds the back, so the trunk has little to do.
        static let hackSquat = Self(pattern: .squat, actions: [.main("knee.extension"), .main("hip.extension")])
        /// The working hip's glutes hold the pelvis level against adduction.
        static let lunge = Self(pattern: .splitSquatLunge, actions: [.main("knee.extension"), .main("hip.extension"), .assisting("hip.adduction", .resists)])
        /// Stepping out to the side and pushing back to the middle, the inner thigh pulls the leg in.
        static let lateralLunge = lunge.actions(.main("knee.extension"), .assisting("hip.extension"), .assisting("hip.adduction"))
        static let legPress = Self(pattern: .legPress, actions: [.main("knee.extension"), .main("hip.extension")])
        static let legExtension = Self(pattern: .kneeExtension, actions: [.main("knee.extension")])
        static let hinge = Self(pattern: .hipHinge, actions: [.main("hip.extension"), .assisting("trunk.flexion", .resists)])
        /// Standing on one leg, its glutes hold the pelvis level.
        static let singleLegHinge = hinge.adding(.assisting("hip.adduction", .resists))
        /// With the bar on the back, the spinal erectors hold as hard as the hips work.
        static let goodMorning = hinge.actions(.main("hip.extension"), .main("trunk.flexion", .resists)).braced
        static let legCurl = Self(pattern: .kneeFlexion, actions: [.main("knee.flexion")])
        /// The hips stay straight while the knees bend, as in a sliding or Nordic curl.
        static let hipsHeldLegCurl = legCurl.adding(.assisting("hip.flexion", .resists))
        static let bridge = Self(pattern: .hipThrustBridge, actions: [.main("hip.extension")])
        /// On one leg, its glutes also hold the pelvis level.
        static let singleLegBridge = bridge.adding(.assisting("hip.adduction", .resists))
        static let kickback = Self(pattern: .hipExtension, actions: [.main("hip.extension")])
        static let calf = Self(pattern: .calfRaise, actions: [.main("ankle.plantarflexion")])
        static let crunch = Self(pattern: .trunkFlexion, actions: [.main("trunk.flexion")])
        /// The hip flexors join in: lifting the trunk past the curl in a sit-up, or the legs in a reverse crunch.
        static let trunkAndHipFlexion = crunch.adding(.assisting("hip.flexion"))
        /// The abs curl the pelvis up as the legs rise.
        static let legRaise = Self(pattern: .hipFlexion, actions: [.main("hip.flexion")])
            .adding(.assisting("trunk.flexion"))
        static let mountainClimber = Self(pattern: .hipFlexion, actions: [.main("hip.flexion"), .assisting("trunk.extension", .resists)])
        static let chop = Self(pattern: .trunkRotation, actions: [.main("trunk.rotation")])
        /// Leaning back, the abs hold the trunk while it turns.
        static let twist = chop.braced
        /// The lower hip's glutes hold the pelvis up off the floor.
        static let sidePlank = Self(pattern: .resistLateralFlexion, actions: [.main("trunk.lateralFlexion", .resists)], style: .isometric, role: .resists)
            .adding(.assisting("hip.adduction", .resists))
        static let wristCurl = Self(pattern: .wristFlexion, actions: [.main("wrist.flexion")])
        static let reverseWristCurl = Self(pattern: .wristExtension, actions: [.main("wrist.extension")])
        static let hipAbduction = Self(pattern: .hipAbduction, actions: [.main("hip.abduction")])
        /// Holding the body up between the bars pushes the shoulder blades down.
        static let dip = Self(pattern: .dip, actions: [.main("shoulder.flexion"), .main("elbow.extension")])
            .adding(.assisting("scapula.depression"))
    }

    private static let profiles = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ($0.id, $0.profile) })

    // Resolve independently seeded copies before wiring relationships. Nullify inverses
    // on vocabulary records allow children to move to the surviving definition.
    private static func index<Row: PersistentModel>(
        _ rows: [Row], by key: KeyPath<Row, String>, instance: KeyPath<Row, UUID>,
        in context: ModelContext, changed: inout Bool, moveChildren: (Row, Row) -> Void
    ) -> [String: Row] {
        var result: [String: Row] = [:]
        for row in rows.sorted(by: { $0[keyPath: instance].uuidString < $1[keyPath: instance].uuidString }) {
            guard !row[keyPath: key].isEmpty else { continue }
            if let survivor = result[row[keyPath: key]] {
                moveChildren(row, survivor)
                context.delete(row)
                changed = true
            } else {
                result[row[keyPath: key]] = row
            }
        }
        return result
    }

    @discardableResult
    static func reconcile(_ exercises: [Exercise], in context: ModelContext) throws -> Bool {
        var changed = false
        var joints = index(try context.fetch(FetchDescriptor<Joint>()), by: \.key, instance: \.instanceID, in: context, changed: &changed) { duplicate, survivor in
            for movement in duplicate.movements ?? [] { movement.joint = survivor }
        }
        var movements = index(try context.fetch(FetchDescriptor<JointMovement>()), by: \.key, instance: \.instanceID, in: context, changed: &changed) { duplicate, survivor in
            for action in duplicate.assignments ?? [] { action.movement = survivor }
        }
        var actions = index(try context.fetch(FetchDescriptor<ExerciseJointAction>()), by: \.key, instance: \.instanceID, in: context, changed: &changed) { duplicate, survivor in
            if survivor.exercise == nil { survivor.exercise = duplicate.exercise }
            if survivor.movement == nil { survivor.movement = duplicate.movement }
        }

        for definition in JointAnatomy.bundled.joints {
            let key = definition.key
            let joint = joints[key] ?? Joint(key: key)
            if joints[key] == nil {
                changed = true
                context.insert(joint)
                joints[key] = joint
            }
            for movementKey in definition.movementKeys {
                let movement = movements[movementKey] ?? JointMovement(key: movementKey)
                if movements[movementKey] == nil {
                    changed = true
                    context.insert(movement)
                    movements[movementKey] = movement
                }
                if movement.joint !== joint {
                    movement.joint = joint
                    changed = true
                }
            }
        }

        var intended = Set<String>()
        var reconciledIDs = Set<String>()
        for exercise in exercises {
            guard let id = exercise.catalogID, let profile = profiles[id] else { continue }
            reconciledIDs.insert(id)
            if exercise.movementPattern != profile.pattern {
                exercise.movementPattern = profile.pattern
                changed = true
            }
            if exercise.executionStyle != profile.style {
                exercise.executionStyle = profile.style
                changed = true
            }
            for movementKey in profile.storedMovements {
                guard let movement = movements[movementKey] else { continue }
                let key = "\(id):\(profile.role.rawValue):\(movementKey)"
                intended.insert(key)
                let action = actions[key] ?? ExerciseJointAction(key: key, role: profile.role)
                if actions[key] == nil {
                    changed = true
                    context.insert(action)
                    actions[key] = action
                }
                if action.exercise !== exercise {
                    action.exercise = exercise
                    changed = true
                }
                if action.movement !== movement {
                    action.movement = movement
                    changed = true
                }
                if action.role != profile.role {
                    action.role = profile.role
                    changed = true
                }
            }
        }
        for (key, action) in actions where !intended.contains(key) {
            guard let separator = key.firstIndex(of: ":"),
                  reconciledIDs.contains(String(key[..<separator])) else { continue }
            context.delete(action)
            changed = true
        }
        return changed
    }
}
