import Foundation

/// Why an import row starts out skipped. Each is a fact about the rows, never a weak match.
nonisolated enum ImportSkipReason: String, CaseIterable, Sendable {
    case cardio, timed, stretchOrPT, alreadyImported
    /// Skipped by the lifter, with no other reason.
    case chosen

    var label: String {
        switch self {
        case .cardio: "Skip (cardio)"
        case .timed: "Skip (timed, no reps)"
        case .stretchOrPT: "Skip (stretch or PT)"
        case .alreadyImported: "Skip (already imported)"
        case .chosen: "Skip"
        }
    }
}

/// The one starting suggestion an import row opens with.
enum ImportSuggestion {
    case skip(ImportSkipReason)
    case match(Exercise)
    case choices([Exercise])
    case none
}

/// Matches FitNotes exercise names to PowerJack lifts through the shared `ExerciseSearch`.
enum FitNotesMatcher {
    /// A top hit at least this strong, and this far ahead of the next, is suggested on its own.
    static let confidentScore = 0.8
    static let confidentMargin = 0.15
    /// Choices a row offers, and candidates the on-device model may pick among.
    static let choiceCount = 3
    static let modelCandidateCount = 5

    /// FitNotes names the search still reads as another lift.
    private static let aliases = Dictionary(uniqueKeysWithValues: [
        "machine bench press": "machine-chest-press",
        "flat machine press": "machine-chest-press",
        "lever chest press": "machine-chest-press",
        "leverage chest press": "machine-chest-press",
        "leverage machine chest press": "machine-chest-press",
        "chest press leverage machine": "machine-chest-press",
        "bar good morning": "barbell-good-morning",
        "good morning barbell": "barbell-good-morning",
        "shrug dumbbell": "dumbbell-shrug",
        "shrugs dumbbells": "dumbbell-shrug",
        "step back lunge": "reverse-lunge",
        "two hand kettlebell swing": "kettlebell-swing",
        "2 handed kettlebell swing": "kettlebell-swing",
        "preacher bench ez bar curl": "ez-bar-preacher-curl",
        "chest press machine": "machine-chest-press",
        "dumbbell shrugs": "dumbbell-shrug",
        "db shrug": "dumbbell-shrug",
        "db shrugs": "dumbbell-shrug",
        "good morning": "barbell-good-morning",
        "good mornings": "barbell-good-morning",
        "backward lunge": "reverse-lunge",
        "backward lunges": "reverse-lunge",
        "reverse lunges": "reverse-lunge",
        "kettlebell swings": "kettlebell-swing",
        "kb swing": "kettlebell-swing",
        "kb swings": "kettlebell-swing",
        "preacher curl ez bar": "ez-bar-preacher-curl",
        "ez bar preacher curls": "ez-bar-preacher-curl",
        "sit ups": "sit-up",
        "side lunges": "lateral-lunge",
        "mountain climbers": "mountain-climber",
        "hex bar deadlift": "trap-bar-deadlift",
        "burpies": "burpee",
        "arnold dumbbell press": "dumbbell-arnold-press",
        "arnold shoulder press": "dumbbell-arnold-press",
        "russian twista": "russian-twist",
        "dumbbell row": "one-arm-dumbbell-row",
        "barbell squat": "barbell-back-squat",
        "deadlift": "barbell-deadlift",
        "military bar press": "barbell-overhead-press",
        "cable overhead triceps extension": "cable-overhead-extension",
        "dumbbell overhead triceps extension": "dumbbell-triceps-extension",
        "flat barbell bench press": "barbell-bench-press",
        "flat dumbbell bench press": "dumbbell-bench-press",
        "leg extension machine": "leg-extension",
        "pull ups reverse grip": "chin-up",
        "pull ups forward grip": "pull-up",
        "close grip barbell bench press": "close-grip-bench-press",
        "narrow bar bell bench": "close-grip-bench-press"
    ].map { (ExerciseCatalog.matchingName($0.key), $0.value) })

    /// The FitNotes category as a muscle hint for search and for a new exercise.
    static func primaryMuscle(for name: String, category: String) -> Muscle? {
        let label = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let muscle = Muscle(rawValue: label) { return muscle }
        switch label {
        case "core", "abdominals": return .abs
        case "quadriceps": return .quads
        case "legs", "lower body":
            // FitNotes groups several PowerJack muscles under Legs.
            let words = Set(ExerciseQuery.words(name))
            if words.contains("calf") { return .calves }
            if !words.isDisjoint(with: ["romanian", "hamstring", "nordic"]) || words.isSuperset(of: ["leg", "curl"]) { return .hamstrings }
            if words.contains("glute") || words.isSuperset(of: ["hip", "thrust"]) { return .glutes }
            if !words.isDisjoint(with: ["squat", "lunge"]) || words.isSuperset(of: ["leg", "extension"]) { return .quads }
            return nil
        default: return nil
        }
    }

    /// The exercise with exactly this name, or the lift an audited alias names.
    static func direct(_ name: String, among exercises: [Exercise]) -> Exercise? {
        let key = ExerciseCatalog.matchingName(name)
        let exact = exercises.filter { ExerciseCatalog.matchingName($0.exerciseName) == key }
        if exact.count == 1 { return exact.first }
        guard let id = aliases[key] else { return nil }
        return exercises.first { $0.catalogID == id }
    }

    /// A reason the rows of one FitNotes name are not a lift to import, read from the rows alone.
    /// `builtIn` keeps names that match a built-in lift, such as Burpees filed under Cardio.
    static func skipReason(name: String, category: String, sets: [FitNotesSet], builtIn: Bool) -> ImportSkipReason? {
        let label = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = Set(ExerciseQuery.words(name))
        if label == "pt" || !words.isDisjoint(with: ["stretch", "stretching", "mobility", "pt"]) { return .stretchOrPT }
        if builtIn { return nil }
        let hasReps = sets.contains { ($0.reps ?? 0) > 0 }
        if label == "cardio" || (!hasReps && sets.contains { $0.distance != nil }) { return .cardio }
        if !hasReps && sets.contains(where: { $0.seconds != nil || ($0.weight ?? 0) > 0 }) { return .timed }
        return nil
    }

    /// Ranked lifts for a FitNotes name, best first, with the suggestion search alone supports.
    @MainActor
    static func search(_ name: String, category: String, among exercises: [Exercise],
                       index: ExerciseSearch.Index, familiarity: ExerciseFamiliarity) -> (suggestion: ImportSuggestion, ranked: [Exercise]) {
        let byKey = Dictionary(exercises.map { ($0.searchKey, $0) }, uniquingKeysWith: { first, _ in first })
        let hits = index.rank(ExerciseQuery(name), context: .importing(category: primaryMuscle(for: name, category: category)),
                              familiarity: familiarity)
        let ranked = hits.compactMap { byKey[$0.key] }
        if let direct = direct(name, among: exercises) {
            return (.match(direct), [direct] + ranked.filter { $0 != direct })
        }
        guard let top = hits.first, let first = ranked.first else { return (.none, []) }
        let next = hits.dropFirst().first?.score ?? 0
        if top.score >= confidentScore && top.score - next >= confidentMargin { return (.match(first), ranked) }
        return (.choices(Array(ranked.prefix(choiceCount))), ranked)
    }
}

extension FitNotesMatcher {
    /// The starting suggestion for every row of one FitNotes name, checked in order: rows already
    /// saved, an earlier match, an earlier skip, a skip reason, then search. `ranked` feeds the
    /// row's choices and the on-device model.
    @MainActor
    static func review(_ name: String, sets: [FitNotesSet], among exercises: [Exercise],
                       index: ExerciseSearch.Index, familiarity: ExerciseFamiliarity, imported: Set<String>,
                       rememberedMatch: Exercise?, rememberedSkip: ImportSkipReason?) -> (suggestion: ImportSuggestion, ranked: [Exercise]) {
        let category = sets.first?.category ?? ""
        let found = search(name, category: category, among: exercises, index: index, familiarity: familiarity)
        if !sets.isEmpty, sets.allSatisfy({ imported.contains($0.key) }) { return (.skip(.alreadyImported), found.ranked) }
        if let rememberedMatch { return (.match(rememberedMatch), found.ranked) }
        if let rememberedSkip { return (.skip(rememberedSkip), found.ranked) }
        let builtIn = direct(name, among: exercises)?.catalogID != nil
        if let reason = skipReason(name: name, category: category, sets: sets, builtIn: builtIn) {
            return (.skip(reason), found.ranked)
        }
        return found
    }
}

/// Names the lifter skipped in an earlier import, with the reason. Kept on this device only:
/// it is a convenience for the next import, not training data.
enum FitNotesSkips {
    private static let key = "fitNotes.skippedExercises"

    static func load(_ defaults: UserDefaults = .standard) -> [String: ImportSkipReason] {
        let stored = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return stored.compactMapValues(ImportSkipReason.init)
    }

    /// Adds this import's skips and forgets names it imported. Already imported rows need no memory.
    static func record(skipped: [String: ImportSkipReason], imported: some Sequence<String>,
                       in defaults: UserDefaults = .standard) {
        var stored = load(defaults)
        for name in imported { stored[name] = nil }
        for (name, reason) in skipped where reason != .alreadyImported { stored[name] = reason }
        defaults.set(stored.mapValues(\.rawValue), forKey: key)
    }
}
