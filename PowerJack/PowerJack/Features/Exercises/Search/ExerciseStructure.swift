import Foundation

/// What a lift does at the joints, and the muscles that follow from it. Change and Substitute
/// rank neighbours by it, and a query's joint words, such as "rear delts", compare against it.
nonisolated struct ExerciseStructure: Hashable, Codable, Sendable {
    /// The joint movement each action works, weighted 1 for a main action and 0.5 for an assisting
    /// one. A held action works the opposite movement without moving: bracing against trunk
    /// extension is trunk flexion work for the abs.
    let actions: [String: Double]
    let pattern: String?
    /// Prime movers get their action's weight and synergists half of it. A group keeps its highest.
    let muscles: [Muscle: Double]

    init(actions: [JointAction], pattern: String?, anatomy: JointAnatomy = .bundled) {
        var worked: [String: Double] = [:]
        for action in actions {
            let movement = action.role == .resists ? anatomy.opposite(of: action.movement) : action.movement
            worked[movement] = max(worked[movement] ?? 0, action.weight)
        }
        var muscles: [Muscle: Double] = [:]
        for (movement, weight) in worked {
            for mover in anatomy.muscles(for: movement) {
                muscles[mover.group] = max(muscles[mover.group] ?? 0, mover.isPrime ? weight : weight / 2)
            }
        }
        self.actions = worked
        self.pattern = pattern
        self.muscles = muscles
    }

    /// A lift with no known joint actions, such as one of the lifter's own, is described by
    /// the muscles it lists instead.
    init(primary: Muscle, secondary: [Muscle], pattern: String?) {
        actions = [:]
        self.pattern = pattern
        var muscles = Dictionary(secondary.map { ($0, 0.5) }) { first, _ in first }
        muscles[primary] = 1
        self.muscles = muscles
    }

    /// 0.7 × shared actions + 0.3 × shared muscles, each a weighted Jaccard, plus 0.1 for the same
    /// movement pattern, capped at 1. When either side has no actions, its muscles decide alone.
    func similarity(to other: Self) -> Double {
        let muscle = Self.overlap(muscles, other.muscles)
        let shared = actions.isEmpty || other.actions.isEmpty ? muscle : 0.7 * Self.overlap(actions, other.actions) + 0.3 * muscle
        let samePattern = pattern != nil && pattern == other.pattern
        return min(1, shared + (samePattern ? 0.1 : 0))
    }

    /// The sum of minimums over the sum of maximums.
    private static func overlap<Key: Hashable>(_ a: [Key: Double], _ b: [Key: Double]) -> Double {
        var smaller = 0.0, larger = 0.0
        for key in Set(a.keys).union(b.keys) {
            smaller += min(a[key] ?? 0, b[key] ?? 0)
            larger += max(a[key] ?? 0, b[key] ?? 0)
        }
        return larger > 0 ? smaller / larger : 0
    }
}
