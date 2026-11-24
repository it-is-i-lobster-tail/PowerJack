import Foundation
import SwiftData

enum MovementCatalog {
    static let vocabulary: [(joint: String, movements: [String])] = [
        ("shoulder", ["flexion", "extension", "abduction", "adduction", "horizontalAdduction", "horizontalAbduction", "internalRotation", "externalRotation"]),
        ("scapula", ["elevation", "depression", "protraction", "retraction", "upwardRotation", "downwardRotation"]),
        ("elbow", ["flexion", "extension"]),
        ("forearm", ["pronation", "supination"]),
        ("wrist", ["flexion", "extension", "radialDeviation", "ulnarDeviation"]),
        ("trunk", ["flexion", "extension", "lateralFlexion", "rotation"]),
        ("hip", ["flexion", "extension", "abduction", "adduction", "internalRotation", "externalRotation"]),
        ("knee", ["flexion", "extension"]),
        ("ankle", ["dorsiflexion", "plantarflexion"]),
    ]

    struct Profile {
        let pattern: MovementPattern
        let movements: [String]
        var style: ExecutionStyle = .controlled
        var role: JointActionRole = .produces

        static let bench = Self(pattern: .horizontalPress, movements: ["shoulder.horizontalAdduction", "elbow.extension"])
        static let fly = Self(pattern: .chestFly, movements: ["shoulder.horizontalAdduction"])
        static let pullUp = Self(pattern: .verticalPull, movements: ["shoulder.adduction", "elbow.flexion"])
        static let chinUp = Self(pattern: .verticalPull, movements: ["shoulder.extension", "elbow.flexion"])
        static let row = Self(pattern: .horizontalPull, movements: ["shoulder.extension", "elbow.flexion", "scapula.retraction"])
        static let deadlift = Self(pattern: .hipHinge, movements: ["hip.extension", "knee.extension"])
        static let overhead = Self(pattern: .overheadPress, movements: ["shoulder.abduction", "elbow.extension", "scapula.upwardRotation"])
        static let lateralRaise = Self(pattern: .lateralRaise, movements: ["shoulder.abduction"])
        static let reverseFly = Self(pattern: .reverseFly, movements: ["shoulder.horizontalAbduction"])
        static let facePull = Self(pattern: .facePull, movements: ["shoulder.horizontalAbduction", "shoulder.externalRotation", "scapula.retraction"])
        static let curl = Self(pattern: .elbowFlexion, movements: ["elbow.flexion"])
        static let triceps = Self(pattern: .elbowExtension, movements: ["elbow.extension"])
        static let squat = Self(pattern: .squat, movements: ["knee.extension", "hip.extension"])
        static let lunge = Self(pattern: .splitSquatLunge, movements: ["knee.extension", "hip.extension"])
        static let legPress = Self(pattern: .legPress, movements: ["knee.extension", "hip.extension"])
        static let legExtension = Self(pattern: .kneeExtension, movements: ["knee.extension"])
        static let hinge = Self(pattern: .hipHinge, movements: ["hip.extension"])
        static let legCurl = Self(pattern: .kneeFlexion, movements: ["knee.flexion"])
        static let bridge = Self(pattern: .hipThrustBridge, movements: ["hip.extension"])
        static let kickback = Self(pattern: .hipExtension, movements: ["hip.extension"])
        static let calf = Self(pattern: .calfRaise, movements: ["ankle.plantarflexion"])
        static let crunch = Self(pattern: .trunkFlexion, movements: ["trunk.flexion"])
        static let legRaise = Self(pattern: .hipFlexion, movements: ["hip.flexion"])
        static let chop = Self(pattern: .trunkRotation, movements: ["trunk.rotation"])
        static let sidePlank = Self(pattern: .resistLateralFlexion, movements: ["trunk.lateralFlexion"], style: .isometric, role: .resists)
        static let wristCurl = Self(pattern: .wristFlexion, movements: ["wrist.flexion"])
        static let reverseWristCurl = Self(pattern: .wristExtension, movements: ["wrist.extension"])
        static let hipAbduction = Self(pattern: .hipAbduction, movements: ["hip.abduction"])
        static let dip = Self(pattern: .dip, movements: ["shoulder.flexion", "elbow.extension"])
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

        for (key, names) in vocabulary {
            let joint = joints[key] ?? Joint(key: key)
            if joints[key] == nil {
                changed = true
                context.insert(joint)
                joints[key] = joint
            }
            for name in names {
                let movementKey = "\(key).\(name)"
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
            for movementKey in profile.movements {
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
