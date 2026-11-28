import Foundation
import SwiftData

enum MovementCatalog {
    struct Profile {
        /// Stored on the exercise, as earlier versions seeded it. See `storedMovements`.
        let pattern: MovementPattern
        var actions: [JointAction]
        var style: ExecutionStyle = .controlled
        /// The role of the stored rows.
        var role: JointActionRole = .produces
        /// A full-body lift, which search keeps out of its stored pattern's family.
        var isFullBody = false

        /// A device on an earlier version rewrites joint action rows and patterns it doesn't
        /// expect, and iCloud would carry each rewrite back and forth. So the stored rows stay as
        /// earlier versions seeded them: the actions in the profile's role. Weights and held
        /// actions in the other role are app data only.
        var storedMovements: [String] { actions.filter { $0.role == role }.map(\.movement) }

        /// The movement family search groups the lift with.
        var family: MovementPattern? { isFullBody ? nil : pattern }

        /// The trunk braced against extension, as abs hold it under a load overhead or out front.
        var braced: Self {
            var profile = self
            profile.actions.append(.assisting("trunk.extension", .resists))
            return profile
        }

        static let shrug = Self(pattern: .scapularElevation, actions: [.main("scapula.elevation")])
        static let rollout = Self(pattern: .resistExtension, actions: [.main("trunk.extension", .resists)], role: .resists)
        static let swing = Self(pattern: .hipHinge, actions: [.main("hip.extension"), .assisting("trunk.flexion", .resists)], style: .explosive).braced
        static let burpee = Self(pattern: .squat, actions: [.main("knee.extension"), .main("hip.extension"), .assisting("elbow.extension")],
                                 style: .explosive, isFullBody: true)
        static let bench = Self(pattern: .horizontalPress, actions: [.main("shoulder.horizontalAdduction"), .assisting("elbow.extension")])
        static let closeGripBench = Self(pattern: .horizontalPress, actions: [.main("elbow.extension"), .main("shoulder.horizontalAdduction")])
        static let fly = Self(pattern: .chestFly, actions: [.main("shoulder.horizontalAdduction")])
        static let pullUp = Self(pattern: .verticalPull, actions: [.main("shoulder.adduction"), .assisting("elbow.flexion")])
        static let chinUp = Self(pattern: .verticalPull, actions: [.main("shoulder.extension"), .main("elbow.flexion")]).braced
        static let row = Self(pattern: .horizontalPull, actions: [.main("shoulder.extension"), .main("scapula.retraction"), .assisting("elbow.flexion")])
        static let deadlift = Self(pattern: .hipHinge, actions: [.main("hip.extension"), .assisting("knee.extension"), .main("trunk.flexion", .resists)])
        static let trapBarDeadlift = Self(pattern: .hipHinge, actions: [.main("knee.extension"), .main("hip.extension"), .assisting("trunk.flexion", .resists)])
        static let overhead = Self(pattern: .overheadPress, actions: [
            .main("shoulder.abduction"), .assisting("elbow.extension"), .assisting("scapula.upwardRotation"),
        ])
        static let lateralRaise = Self(pattern: .lateralRaise, actions: [.main("shoulder.abduction")])
        static let reverseFly = Self(pattern: .reverseFly, actions: [.main("shoulder.horizontalAbduction")])
        static let facePull = Self(pattern: .facePull, actions: [
            .main("shoulder.horizontalAbduction"), .assisting("shoulder.externalRotation"), .assisting("scapula.retraction"),
        ])
        static let curl = Self(pattern: .elbowFlexion, actions: [.main("elbow.flexion")])
        static let triceps = Self(pattern: .elbowExtension, actions: [.main("elbow.extension")])
        static let squat = Self(pattern: .squat, actions: [.main("knee.extension"), .main("hip.extension")]).braced
        /// The working hip's glutes hold the pelvis level against adduction.
        static let lunge = Self(pattern: .splitSquatLunge, actions: [.main("knee.extension"), .main("hip.extension"), .assisting("hip.adduction", .resists)])
        static let legPress = Self(pattern: .legPress, actions: [.main("knee.extension"), .main("hip.extension")])
        static let legExtension = Self(pattern: .kneeExtension, actions: [.main("knee.extension")])
        static let hinge = Self(pattern: .hipHinge, actions: [.main("hip.extension"), .assisting("trunk.flexion", .resists)])
        static let legCurl = Self(pattern: .kneeFlexion, actions: [.main("knee.flexion")])
        static let bridge = Self(pattern: .hipThrustBridge, actions: [.main("hip.extension")])
        static let kickback = Self(pattern: .hipExtension, actions: [.main("hip.extension")])
        static let calf = Self(pattern: .calfRaise, actions: [.main("ankle.plantarflexion")])
        static let crunch = Self(pattern: .trunkFlexion, actions: [.main("trunk.flexion")])
        static let legRaise = Self(pattern: .hipFlexion, actions: [.main("hip.flexion")])
        static let mountainClimber = Self(pattern: .hipFlexion, actions: [.main("hip.flexion"), .assisting("trunk.extension", .resists)])
        static let chop = Self(pattern: .trunkRotation, actions: [.main("trunk.rotation")])
        static let sidePlank = Self(pattern: .resistLateralFlexion, actions: [.main("trunk.lateralFlexion", .resists)], style: .isometric, role: .resists)
        static let wristCurl = Self(pattern: .wristFlexion, actions: [.main("wrist.flexion")])
        static let reverseWristCurl = Self(pattern: .wristExtension, actions: [.main("wrist.extension")])
        static let hipAbduction = Self(pattern: .hipAbduction, actions: [.main("hip.abduction")])
        static let dip = Self(pattern: .dip, actions: [.main("shoulder.flexion"), .main("elbow.extension")])
        // Added with the belt squat, landmine and back extension lifts. Older versions never seeded
        // these, so nothing stored has to stay as it was.
        static let straightArmPulldown = Self(pattern: .verticalPull, actions: [.main("shoulder.extension")])
        static let pullover = Self(pattern: .verticalPull, actions: [.main("shoulder.extension"), .assisting("shoulder.horizontalAdduction")])
        static let frontRaise = Self(pattern: .lateralRaise, actions: [.main("shoulder.flexion")])
        static let landminePress = Self(pattern: .overheadPress, actions: [
            .main("shoulder.flexion"), .assisting("elbow.extension"), .assisting("scapula.upwardRotation"),
        ])
        static let pushPress = Self(pattern: .overheadPress, actions: overhead.actions + [.assisting("knee.extension"), .assisting("hip.extension")],
                                    style: .explosive).braced
        /// The belt holds the load at the hips, so the trunk carries none of it.
        static let beltSquat = Self(pattern: .squat, actions: [.main("knee.extension"), .main("hip.extension")])
        static let hipAdduction = Self(pattern: .hipAbduction, actions: [.main("hip.adduction")])
        static let backExtension = Self(pattern: .hipHinge, actions: [.main("hip.extension"), .assisting("trunk.extension")])
        static let gluteHamRaise = Self(pattern: .kneeFlexion, actions: [.main("knee.flexion"), .assisting("hip.extension")])
        static let pallofPress = Self(pattern: .trunkRotation, actions: [.main("trunk.rotation", .resists)], role: .resists)
        static let deadBug = Self(pattern: .resistExtension, actions: [.main("trunk.extension", .resists), .assisting("hip.flexion")], role: .resists)
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
