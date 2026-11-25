import Foundation
import SwiftData

enum ExecutionStyle: String, Codable {
    case controlled, explosive, isometric
}

enum MovementPattern: String, Codable {
    case horizontalPress, overheadPress, dip, chestFly, verticalPull, horizontalPull
    case lateralRaise, reverseFly, facePull, elbowFlexion, elbowExtension
    case squat, splitSquatLunge, legPress, hipHinge, hipThrustBridge
    case kneeExtension, kneeFlexion, hipExtension, hipAbduction, calfRaise
    case trunkFlexion, hipFlexion, trunkRotation, resistLateralFlexion
    case wristFlexion, wristExtension
}

enum JointActionRole: String, Codable {
    case produces, resists
}

// The catalog key identifies a definition across installations. The instance ID
// gives every device the same survivor when iCloud imports independently seeded rows.
@Model
final class Joint {
    var key: String = ""
    var instanceID: UUID = UUID()
    @Relationship(inverse: \JointMovement.joint)
    var movements: [JointMovement]? = []

    init(key: String) { self.key = key }
}

@Model
final class JointMovement {
    var key: String = ""
    var instanceID: UUID = UUID()
    var joint: Joint?
    @Relationship(inverse: \ExerciseJointAction.movement)
    var assignments: [ExerciseJointAction]? = []

    init(key: String) { self.key = key }
}

@Model
final class ExerciseJointAction {
    // The full catalog key lets an import recover even when relationships arrive later.
    var key: String = ""
    var instanceID: UUID = UUID()
    var role: JointActionRole = JointActionRole.produces
    var exercise: Exercise?
    var movement: JointMovement?

    init(key: String, role: JointActionRole) {
        self.key = key
        self.role = role
    }
}
