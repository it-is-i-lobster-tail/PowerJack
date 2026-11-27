import Foundation

/// How the body moves, bundled as `MovementAnatomy.json`. A joint has a type, the type allows a
/// fixed set of movements, and each joint movement, such as "elbow.flexion", names its muscles.
nonisolated struct JointAnatomy: Sendable {
    enum JointType: String, Decodable, Sendable {
        case hinge, pivot, condyloid, ballAndSocket, gliding, stackedGliding
    }

    struct Joint: Decodable, Sendable {
        let key: String
        let name: String
        let type: JointType
        /// The movements this joint does, each one its type allows.
        let movements: [String]

        var movementKeys: [String] { movements.map { "\(key).\($0)" } }
    }

    /// A named muscle doing a joint movement, rolled up to one of the app's muscle groups.
    struct Mover: Sendable {
        let name: String
        let group: Muscle
        /// A prime mover does the movement. A synergist helps.
        let isPrime: Bool
    }

    let joints: [Joint]
    private let types: [JointType: [String]]
    private let movers: [String: [Mover]]
    private let opposites: [String: String]
    private let terms: [String: Set<String>]

    static let bundled: Self = {
        guard let url = Bundle.main.url(forResource: "MovementAnatomy", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let anatomy = try? Self(json: data) else {
            preconditionFailure("MovementAnatomy.json is missing or unreadable")
        }
        return anatomy
    }()

    init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        joints = file.joints
        types = Dictionary(uniqueKeysWithValues: file.types.compactMap { name, movements in
            JointType(rawValue: name).map { ($0, movements) }
        })
        movers = file.movements.mapValues { muscles in
            muscles.prime.map { Mover(name: $0.key, group: $0.value, isPrime: true) }
                + muscles.synergist.map { Mover(name: $0.key, group: $0.value, isPrime: false) }
        }
        opposites = file.opposites.reduce(into: [:]) { result, pair in
            result[pair[0]] = pair[1]
            result[pair[1]] = pair[0]
        }
        terms = file.terms.mapValues(Set.init)
    }

    /// Every joint movement key, such as "elbow.flexion".
    var movementKeys: [String] { joints.flatMap(\.movementKeys) }

    /// The movements a joint of this type can do.
    func movements(of type: JointType) -> [String] { types[type] ?? [] }

    func muscles(for movementKey: String) -> [Mover] { movers[movementKey] ?? [] }

    /// A movement as a lifter reads it: "horizontalAbduction" or "shoulder.horizontalAbduction"
    /// reads "Horizontal abduction".
    static func name(ofMovement movement: String) -> String {
        let last = movement.split(separator: ".").last.map(String.init) ?? movement
        let words = last.reduce(into: "") { name, letter in
            name += letter.isUppercase ? " \(letter.lowercased())" : String(letter)
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// The movement working against this one at the same joint: extension for flexion.
    /// Lateral flexion and rotation oppose themselves, to the other side.
    func opposite(of movementKey: String) -> String {
        guard let dot = movementKey.firstIndex(of: ".") else { return movementKey }
        let movement = String(movementKey[movementKey.index(after: dot)...])
        return String(movementKey[...dot]) + (opposites[movement] ?? movement)
    }

    /// Joint movements a lifter means by a phrase, such as "rear delt". The phrase is read as
    /// `ExerciseQuery.words` reads it, joined by spaces.
    func movements(forTerm term: String) -> Set<String> { terms[term] ?? [] }

    private struct File: Decodable {
        struct Muscles: Decodable {
            let prime: [String: Muscle]
            let synergist: [String: Muscle]
        }

        let joints: [Joint]
        let types: [String: [String]]
        let opposites: [[String]]
        let movements: [String: Muscles]
        let terms: [String: [String]]
    }
}

/// One thing a lift does at a joint. A main action weighs 1 and an assisting one 0.5.
nonisolated struct JointAction: Hashable, Sendable {
    let movement: String
    let weight: Double
    /// A held action keeps the joint still against the movement, as a plank resists trunk extension.
    let role: JointActionRole

    static func main(_ movement: String, _ role: JointActionRole = .produces) -> Self {
        Self(movement: movement, weight: 1, role: role)
    }

    static func assisting(_ movement: String, _ role: JointActionRole = .produces) -> Self {
        Self(movement: movement, weight: 0.5, role: role)
    }
}
