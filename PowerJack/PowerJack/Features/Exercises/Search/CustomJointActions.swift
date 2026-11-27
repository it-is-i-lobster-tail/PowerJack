import Foundation
import SwiftData

/// Joint actions a lifter set by hand on one of their own exercises, in Advanced Data. They
/// replace the ones copied from a "Moves like" lift.
///
/// Rows are keyed `own:<uuid>:custom:<main|assisting>:<role>:<movement>`, so each action keeps
/// its weight without a new stored field. Catalog reconciliation, in this and earlier versions,
/// never touches an `own:` key.
enum CustomJointActions {
    private static let marker = "custom"

    /// The lifter's own actions on an exercise, or nil when it has none set by hand.
    static func read(_ exercise: Exercise) -> [JointAction]? {
        let rows = exercise.jointActions ?? []
        guard rows.contains(where: { isCustom($0.key) }) else { return nil }
        return rows.compactMap { action(from: $0.key) }
            .sorted { ($0.weight, $1.movement) > ($1.weight, $0.movement) }
    }

    static func isCustom(_ rowKey: String) -> Bool { action(from: rowKey) != nil }

    /// Replaces an own exercise's joint action rows with these. The movement pattern and style
    /// stay as they were, so the lift keeps its family in search.
    static func write(_ actions: [JointAction], to exercise: Exercise, in context: ModelContext) {
        guard exercise.catalogID == nil else { return }
        for action in exercise.jointActions ?? [] { context.delete(action) }
        exercise.jointActions = []
        exercise.assignSyncID()
        guard let owner = exercise.syncKey, !actions.isEmpty else { return }
        let movements = Dictionary(
            ((try? context.fetch(FetchDescriptor<JointMovement>())) ?? []).map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for action in actions {
            guard let movement = movements[action.movement] else { continue }
            let weight = action.weight >= 1 ? "main" : "assisting"
            let row = ExerciseJointAction(key: "\(owner):\(marker):\(weight):\(action.role.rawValue):\(action.movement)", role: action.role)
            context.insert(row)
            row.exercise = exercise
            row.movement = movement
        }
    }

    private static func action(from rowKey: String) -> JointAction? {
        let parts = rowKey.split(separator: ":").map(String.init)
        guard parts.count == 6, parts[0] == "own", parts[2] == marker,
              let role = JointActionRole(rawValue: parts[4]) else { return nil }
        switch parts[3] {
        case "main": return .main(parts[5], role)
        case "assisting": return .assisting(parts[5], role)
        default: return nil
        }
    }
}

/// How a lift uses one joint movement, as Advanced Data shows it. A held action is shown on the
/// movement whose muscles do the holding: bracing against trunk extension holds trunk flexion.
enum JointInvolvement: String, CaseIterable, Identifiable {
    case main, assisting, holds

    var id: Self { self }

    var name: String {
        switch self {
        case .main: "Main"
        case .assisting: "Assists"
        case .holds: "Holds"
        }
    }

    /// Each worked movement and how the actions use it. Moving a joint wins over holding it.
    static func of(_ actions: [JointAction], anatomy: JointAnatomy = .bundled) -> [String: Self] {
        var result: [String: Self] = [:]
        for action in actions {
            if action.role == .resists {
                let worked = anatomy.opposite(of: action.movement)
                if result[worked] == nil { result[worked] = .holds }
            } else if action.weight >= 1 {
                result[action.movement] = .main
            } else if result[action.movement] != .main {
                result[action.movement] = .assisting
            }
        }
        return result
    }

    /// `actions` with one worked movement set to `involvement`, or cleared for nil. Every other
    /// action stays exactly as it was.
    static func setting(_ movement: String, to involvement: Self?, in actions: [JointAction],
                        anatomy: JointAnatomy = .bundled) -> [JointAction] {
        var kept = actions.filter { action in
            let worked = action.role == .resists ? anatomy.opposite(of: action.movement) : action.movement
            return worked != movement
        }
        switch involvement {
        case .main: kept.append(.main(movement))
        case .assisting: kept.append(.assisting(movement))
        case .holds: kept.append(.main(anatomy.opposite(of: movement), .resists))
        case nil: break
        }
        return kept
    }
}
