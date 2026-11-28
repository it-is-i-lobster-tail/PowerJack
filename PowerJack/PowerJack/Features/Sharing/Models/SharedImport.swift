//
//  SharedImport.swift
//  PowerJack
//
//  Brings a shared template or exercise into this phone's library.
//

import Foundation
import SwiftData

/// A shared file matched against the lifter's exercises, ready to save.
///
/// A shared exercise this phone already has (a built-in, or an own exercise with the same name,
/// equipment and settings) is used as is. One with the same name and equipment but other settings
/// asks once: use the lifter's own, or keep both by adding the shared one under a new name.
/// Nothing the lifter already has is ever changed.
struct SharedImport: Identifiable {
    let id = UUID()

    enum Choice: Hashable {
        case useMine
        case keepBoth
    }

    struct Item: Identifiable {
        /// Index into the file's exercises.
        let id: Int
        let shared: SharedExercise
        /// The lifter's exercise this one is, or shares a name with.
        let existing: Exercise?
        /// True when `existing` is the same exercise, so there's nothing to ask.
        let isSame: Bool
        /// True when `existing` has another name that reads as the same lift, such as
        /// "One Arm Row" for "One Arm Single Row".
        var isLookAlike = false
        /// The name it gets if the lifter keeps both.
        let keepBothName: String
        var choice = Choice.useMine

        var isNew: Bool { existing == nil }
        var asks: Bool { existing != nil && !isSame }
    }

    let file: SharedFile
    var items: [Item]

    init(file: SharedFile, in context: ModelContext) throws {
        let template = try file.template.map(Self.validated)
        let library = try context.fetch(FetchDescriptor<Exercise>()).filter { !$0.fromSnapshotValue }
        var taken = Set(library.map { Self.normalized($0.exerciseName) })
        var items: [Item] = []
        for (index, shared) in file.exercises.enumerated() {
            let exact = Self.existing(for: shared, in: library)
            let lookAlike = exact == nil ? Self.lookAlike(for: shared, in: library) : nil
            let existing = exact ?? lookAlike
            let isSame = existing.map { ($0.catalogID != nil && $0.catalogID == shared.catalogID) || Self.same(shared, as: $0) } ?? false
            // Only exercises the import may add need values this version can save.
            let name = isSame ? shared.name : try Self.draft(for: shared).name
            let keepBothName = Self.uniqueName(name, maxLength: maxExerciseNameLengthInput, taken: taken)
            if existing != nil && !isSame { taken.insert(Self.normalized(keepBothName)) }
            items.append(Item(id: index, shared: shared, existing: existing, isSame: isSame && lookAlike == nil,
                              isLookAlike: lookAlike != nil, keepBothName: keepBothName))
        }
        if let template, template.days.joined().contains(where: { !items.indices.contains($0.exercise) }) {
            throw SharedFileError.unreadable
        }
        self.file = file
        self.items = items
    }

    var template: SharedTemplate? { file.template }

    /// The exercises the import adds or asks about. The rest are already on this phone.
    var itemsToShow: [Item] { items.filter { $0.isNew || $0.asks } }

    /// True when importing would add nothing: a single exercise the lifter already has.
    var hasNothingToAdd: Bool { template == nil && itemsToShow.isEmpty }

    /// Saves the import and returns the new template, if the file held one.
    @discardableResult
    func save(in context: ModelContext) throws -> TemplateProgram? {
        var inserted: [any PersistentModel] = []
        do {
            var resolved: [Int: Exercise] = [:]
            for item in items {
                if let existing = item.existing, item.isSame || item.choice == .useMine {
                    resolved[item.id] = existing
                    continue
                }
                var draft = try Self.draft(for: item.shared)
                if item.existing != nil && !item.isLookAlike { draft.name = item.keepBothName }
                guard let exercise = draft.makeExercise() else { throw SharedFileError.unreadable }
                context.insert(exercise)
                inserted.append(exercise)
                draft.applyMovement(to: exercise)
                exercise.assignSyncID()
                resolved[item.id] = exercise
            }

            var templateProgram: TemplateProgram?
            if let shared = template {
                let made = try makeTemplate(shared, exercises: resolved, in: context)
                context.insert(made)
                inserted.append(made)
                templateProgram = made
            }
            try context.save()
            return templateProgram
        } catch {
            // Deleting a template or exercise deletes the rows it owns.
            for model in inserted { context.delete(model) }
            throw error
        }
    }

    private func makeTemplate(_ shared: SharedTemplate, exercises: [Int: Exercise], in context: ModelContext) throws -> TemplateProgram {
        let shared = try Self.validated(shared)
        let names = try context.fetch(FetchDescriptor<TemplateProgram>()).filter { !$0.hiddenValue }.map(\.templateName)
        let name = shared.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let templateProgram = TemplateProgram(
            templateName: Self.uniqueName(name.isEmpty ? TemplateProgramDraft.defaultName : name,
                                          maxLength: TemplateProgramDraft.maximumNameLength,
                                          taken: Set(names.map(Self.normalized))),
            workoutsPerWeek: shared.workoutsPerWeek,
            templateMuscleFocus: shared.muscleFocus.compactMap(Muscle.init(rawValue:)),
            templateType: TemplateType(rawValue: shared.type) ?? .hypertrophy
        )
        // Fresh superset IDs, so importing a template twice never links the two copies.
        var supersets: [UUID: UUID] = [:]
        for day in shared.days {
            let workout = templateProgram.addTemplateWorkout()
            for row in day {
                guard let exercise = exercises[row.exercise] else { continue }
                let supersetID = row.supersetID.map { old in
                    if let new = supersets[old] { return new }
                    let new = UUID()
                    supersets[old] = new
                    return new
                }
                workout.addTemplateExercise(exercise: exercise, supersetID: supersetID)
            }
        }
        return templateProgram
    }
}

//
// Matching
//
extension SharedImport {
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The built-in with the shared one's ID, else an exercise with its name and equipment,
    /// preferring one that's the same in every setting, then the lifter's own.
    private static func existing(for shared: SharedExercise, in library: [Exercise]) -> Exercise? {
        if let catalogID = shared.catalogID, let builtIn = library.first(where: { $0.catalogID == catalogID }) {
            return builtIn
        }
        let name = normalized(shared.name)
        let matches = library.filter {
            normalized($0.exerciseName) == name &&
            $0.equipment.rawValue == shared.equipment &&
            $0.customEquipmentName == shared.customEquipmentName
        }
        return matches.first { same(shared, as: $0) } ?? matches.first(where: \.userCreated) ?? matches.first
    }

    /// A lift the lifter already has under another name, held to a high bar so it only catches
    /// the same lift: same equipment and primary muscle, one name holding every word of the
    /// other, and at least 3 in 4 words shared. Words match the way search matches them
    /// (prefixes, one typo, plurals), and "single" reads as "one". Nil when two lifts tie.
    static func lookAlike(for shared: SharedExercise, in library: [Exercise]) -> Exercise? {
        let words = lookAlikeWords(shared.name)
        guard !words.isEmpty else { return nil }
        let scored = library.compactMap { exercise -> (exercise: Exercise, share: Double)? in
            guard exercise.equipment.rawValue == shared.equipment,
                  exercise.customEquipmentName == shared.customEquipmentName,
                  exercise.primaryMuscleFocus.rawValue == shared.primaryMuscle
            else { return nil }
            let theirs = lookAlikeWords(exercise.exerciseName)
            let forward = ExerciseSearch.share(of: words, in: theirs)
            let backward = ExerciseSearch.share(of: theirs, in: words)
            guard max(forward, backward) == 1, min(forward, backward) >= lookAlikeShare else { return nil }
            return (exercise, min(forward, backward))
        }
        // The lifter's own lift wins a tie with a built-in. Any other tie is too close to call.
        .sorted { $0.share != $1.share ? $0.share > $1.share : $0.exercise.userCreated && !$1.exercise.userCreated }
        guard let best = scored.first else { return nil }
        if let next = scored.dropFirst().first, next.share == best.share,
           next.exercise.userCreated == best.exercise.userCreated { return nil }
        return best.exercise
    }

    /// The least share of words two names must have in common to read as one lift.
    static let lookAlikeShare = 0.75

    private static func lookAlikeWords(_ name: String) -> [String] {
        let words = ExerciseQuery(name).nameWords.map { ["single", "unilateral"].contains($0) ? "one" : $0 }
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }

    /// Same name, equipment, muscles, rep range, fatigue, rest and movement.
    private static func same(_ shared: SharedExercise, as exercise: Exercise) -> Bool {
        let mine = SharedExercise(exercise)
        return normalized(mine.name) == normalized(shared.name) &&
            mine.equipment == shared.equipment &&
            mine.customEquipmentName == shared.customEquipmentName &&
            mine.primaryMuscle == shared.primaryMuscle &&
            Set(mine.secondaryMuscles) == Set(shared.secondaryMuscles) &&
            mine.minReps == shared.minReps &&
            mine.maxReps == shared.maxReps &&
            mine.fatigueLevel == shared.fatigueLevel &&
            mine.customRestTime == shared.customRestTime &&
            mine.movesLike == shared.movesLike
    }

    /// `name`, or `name 2`, `name 3`… when it's taken, shortened to fit `maxLength`.
    static func uniqueName(_ name: String, maxLength: Int, taken: Set<String>) -> String {
        guard taken.contains(normalized(name)) else { return name }
        var number = 2
        while true {
            let suffix = " \(number)"
            let base = String(name.prefix(maxLength - suffix.count)).trimmingCharacters(in: .whitespaces)
            let candidate = base + suffix
            if !taken.contains(normalized(candidate)) { return candidate }
            number += 1
        }
    }
}

//
// Reading the file's values
//
extension SharedImport {
    /// The shared exercise as a draft, its values kept inside this version's limits.
    /// Throws for a value this version doesn't know, such as new equipment.
    static func draft(for shared: SharedExercise) throws -> ExerciseDraft {
        guard let equipment = Equipment(rawValue: shared.equipment),
              let primary = Muscle(rawValue: shared.primaryMuscle),
              let fatigue = FatigueLevel(rawValue: shared.fatigueLevel)
        else { throw SharedFileError.newerVersion }

        var draft = ExerciseDraft(name: String(shared.name.prefix(maxExerciseNameLengthInput)))
        draft.equipment = equipment
        draft.customEquipmentName = shared.customEquipmentName
        draft.primaryMuscle = primary
        draft.fatigueLevel = fatigue
        // Before the muscles, since a pick fills secondaries that are still empty.
        if let key = shared.movesLike, MovesLike.entry(key) != nil {
            draft.choose(movesLike: key)
        }
        draft.secondaryMuscles = Array(shared.secondaryMuscles.compactMap(Muscle.init(rawValue:))
            .filter { $0 != primary }.prefix(maxSecondaryMuscles))
        let reps = ExerciseDraft.repLimits
        draft.minReps = min(max(shared.minReps, reps.lowerBound), reps.upperBound)
        draft.maxReps = min(max(shared.maxReps, draft.minReps), reps.upperBound)
        draft.customRestTime = shared.customRestTime.map {
            min(max($0, ExerciseDraft.restLimits.lowerBound), ExerciseDraft.restLimits.upperBound)
        }
        guard draft.canSave else { throw SharedFileError.unreadable }
        return draft
    }

    private static func validated(_ template: SharedTemplate) throws -> SharedTemplate {
        guard TemplateType(rawValue: template.type) != nil else { throw SharedFileError.newerVersion }
        var template = template
        template.name = String(template.name.prefix(TemplateProgramDraft.maximumNameLength))
        template.workoutsPerWeek = min(max(template.workoutsPerWeek, 0), TemplateProgramDraft.maximumWorkoutsPerWeek)
        template.muscleFocus = Array(template.muscleFocus.filter { Muscle(rawValue: $0) != nil }
            .prefix(TemplateProgramDraft.maximumFocusMuscles))
        template.days = Array(template.days.prefix(TemplateProgramDraft.maximumWorkoutsPerWeek))
        return template
    }
}
