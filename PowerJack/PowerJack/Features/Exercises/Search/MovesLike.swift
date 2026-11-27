import Foundation
import SwiftData

/// The built-in lift one of the lifter's own exercises moves like. Its movement pattern, style
/// and joint actions are copied onto the own exercise, so Change, Substitute and joint words
/// such as "rear delts" treat it like that lift.
///
/// A built-in is named by its sync key, such as "catalog:barbell-row".
enum MovesLike {
    /// Built-ins only, read by name alone so the same name always finds the same lifts.
    static let index = ExerciseSearch.Index(ExerciseCatalog.entries.map { ExerciseSearch.Document($0) }, encoder: nil)

    private static let entries = Dictionary(uniqueKeysWithValues: ExerciseCatalog.entries.map { ("catalog:\($0.id)", $0) })

    static func entry(_ key: String?) -> ExerciseCatalog.Entry? { key.flatMap { entries[$0] } }

    /// At least this share of the name's words must be in a built-in's name.
    static let minimumName = 0.5

    // MARK: - Proposing

    /// A clear match, else the on-device model's pick among the closest built-ins, else none.
    static func propose(name: String, equipment: Equipment?, primary: Muscle?) async -> String? {
        if let key = clearMatch(name: name, equipment: equipment, primary: primary) { return key }
        let choices = candidates(name: name, equipment: equipment, primary: primary)
        return await ExerciseProfileModel.choose(name: name, equipment: equipment, primary: primary, among: choices)
            .map { "catalog:\($0.id)" }
    }

    /// The built-in to copy when the name leaves no doubt about how the lift moves: at least half
    /// its words are in the best built-in names, one of those works the primary muscle, and those
    /// that do all move the same way. "Paused Bench" finds the bench presses.
    /// - Parameter strict: Every one of the best names must move the same way, whatever it
    ///   works, as when filling in a lift nobody is looking at. "Spider Curl" then stays unset,
    ///   since leg curls share its words.
    static func clearMatch(name: String, equipment: Equipment?, primary: Muscle?, strict: Bool = false) -> String? {
        let hits = ranked(name: name, equipment: equipment, primary: primary)
        guard let best = hits.first, best.share >= minimumName else { return nil }
        let tied = hits.filter { $0.share == best.share }
        let focused = primary.map { primary in tied.filter { $0.entry.primaryMuscle == primary } } ?? tied
        guard !focused.isEmpty,
              Set((strict ? tied : focused).map(\.entry.profile.pattern)).count == 1 else { return nil }
        return "catalog:\(best.entry.id)"
    }

    /// Up to 5 built-ins sharing words with the name, one for each way of moving.
    static func candidates(name: String, equipment: Equipment?, primary: Muscle?) -> [ExerciseCatalog.Entry] {
        var patterns = Set<MovementPattern>()
        return ranked(name: name, equipment: equipment, primary: primary)
            .filter { patterns.insert($0.entry.profile.pattern).inserted }
            .prefix(5).map(\.entry)
    }

    /// Built-ins holding any of the name's words: most words first, then the primary muscle,
    /// then the same equipment, then catalog order.
    private static func ranked(name: String, equipment: Equipment?, primary: Muscle?) -> [(entry: ExerciseCatalog.Entry, share: Double)] {
        let words = ExerciseQuery(name).nameWords
        let hits = ExerciseCatalog.entries.enumerated().compactMap { order, entry -> (ExerciseCatalog.Entry, Double, Int)? in
            let share = ExerciseSearch.share(of: words, in: ExerciseQuery.words(entry.name))
            return share > 0 ? (entry, share, order) : nil
        }
        func rank(_ entry: ExerciseCatalog.Entry) -> Int {
            (entry.primaryMuscle == primary ? 0 : 2) + (entry.equipment == equipment ? 0 : 1)
        }
        return hits.sorted { left, right in
            if left.1 != right.1 { return left.1 > right.1 }
            if rank(left.0) != rank(right.0) { return rank(left.0) < rank(right.0) }
            return left.2 < right.2
        }
        .map { (entry: $0.0, share: $0.1) }
    }

    /// Secondary muscles that follow from a built-in's joint actions: the prime movers of each
    /// action, main actions first, without the primary. Synergists are left out, so a row
    /// suggests biceps but not chest.
    static func secondaryMuscles(of key: String?, primary: Muscle?) -> [Muscle] {
        guard let profile = entry(key)?.profile else { return [] }
        let anatomy = JointAnatomy.bundled
        var weights: [Muscle: Double] = [:]
        for action in profile.actions {
            let movement = action.role == .resists ? anatomy.opposite(of: action.movement) : action.movement
            for mover in anatomy.muscles(for: movement) where mover.isPrime && mover.group != primary {
                weights[mover.group] = max(weights[mover.group] ?? 0, action.weight)
            }
        }
        return weights
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
            .prefix(maxSecondaryMuscles).map(\.key)
    }

    // MARK: - Reading and writing an own exercise

    private struct Signature: Hashable {
        let pattern: MovementPattern
        let style: ExecutionStyle
        let actions: Set<String>
    }

    private static let signatures: [(key: String, signature: Signature, equipment: Equipment)] = ExerciseCatalog.entries.map { entry in
        let profile = entry.profile
        let actions = Set(profile.storedMovements.map { "\(profile.role.rawValue) \($0)" })
        return ("catalog:\(entry.id)", Signature(pattern: profile.pattern, style: profile.style, actions: actions), entry.equipment)
    }

    /// The built-in whose stored movement an own exercise carries, the one on the same equipment
    /// when several share it. Nil for a built-in or an own exercise with none.
    static func key(of exercise: Exercise) -> String? {
        guard exercise.catalogID == nil, let pattern = exercise.movementPattern else { return nil }
        let actions = Set((exercise.jointActions ?? []).compactMap { action in
            action.movement.map { "\(action.role.rawValue) \($0.key)" }
        })
        let signature = Signature(pattern: pattern, style: exercise.executionStyle ?? .controlled, actions: actions)
        let same = signatures.filter { $0.signature == signature }
        return (same.first { $0.equipment == exercise.equipment } ?? same.first)?.key
    }

    /// Copies a built-in's pattern, style and joint action rows onto an own exercise, or clears
    /// them for nil. Rows are keyed by the exercise's own sync key, which catalog reconciliation
    /// never touches. Stored rows carry no weight; search reads the built-in's weights back
    /// through `key(of:)`.
    static func copy(_ key: String?, to exercise: Exercise, in context: ModelContext) {
        guard exercise.catalogID == nil else { return }
        for action in exercise.jointActions ?? [] { context.delete(action) }
        exercise.jointActions = []
        let profile = entry(key)?.profile
        exercise.movementPattern = profile?.pattern
        exercise.executionStyle = profile?.style
        guard let profile else { return }
        exercise.assignSyncID()
        guard let owner = exercise.syncKey else { return }
        let wanted = Set(profile.storedMovements)
        let movements = Dictionary(
            ((try? context.fetch(FetchDescriptor<JointMovement>())) ?? []).filter { wanted.contains($0.key) }.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for movementKey in profile.storedMovements {
            guard let movement = movements[movementKey] else { continue }
            let action = ExerciseJointAction(key: "\(owner):\(profile.role.rawValue):\(movementKey)", role: profile.role)
            context.insert(action)
            action.exercise = exercise
            action.movement = movement
        }
    }

    // MARK: - Exercises saved before this version

    /// Bumped to run the pass again on every device.
    static let fillRevision = 1
    static let fillRevisionKey = "customExercises.movesLikeRevision"

    /// Once per device, the lifter's own exercises saved without a movement get the one of a
    /// clearly matching built-in. The rest stay unset until the lifter edits them, and a
    /// movement the lifter set, or cleared with None, is never changed.
    /// - Returns: The names of the exercises filled in, in case a note should list them.
    @discardableResult
    static func fillExisting(in context: ModelContext, defaults: UserDefaults = .standard) throws -> [String] {
        guard defaults.integer(forKey: fillRevisionKey) < fillRevision else { return [] }
        let unset = try context.fetch(FetchDescriptor<Exercise>()).filter { exercise in
            exercise.catalogID == nil && exercise.userCreated && !exercise.fromSnapshotValue
                && exercise.movementPattern == nil && (exercise.jointActions ?? []).isEmpty
        }
        var filled: [String] = []
        for exercise in unset {
            guard let key = clearMatch(name: exercise.exerciseName, equipment: exercise.equipment,
                                       primary: exercise.primaryMuscleFocus, strict: true) else { continue }
            copy(key, to: exercise, in: context)
            filled.append(exercise.exerciseName)
        }
        if !filled.isEmpty { try context.save() }
        defaults.set(fillRevision, forKey: fillRevisionKey)
        return filled
    }
}
