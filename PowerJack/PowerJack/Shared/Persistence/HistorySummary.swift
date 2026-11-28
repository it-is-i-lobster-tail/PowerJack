import Foundation
import OSLog
import SwiftData
import UIKit

/// The pieces the Data tab and the exercise picker are built from, for the open store.
///
/// After a saved change only the workouts it touched are rebuilt: the store's own change log
/// (SwiftData history) says which rows changed, from this device or from iCloud. The pieces are
/// also kept in a file on this device, so a relaunch only catches up on what changed since.
/// Anything unexpected falls back to building everything again.
@MainActor
final class HistorySummary {
    static let shared = HistorySummary()

    /// Bump when the pieces or what they read change, so files from older versions are rebuilt.
    static let fileVersion = 2

    /// Where the file lives: on this device only, never in iCloud or a backup.
    static var directory: URL { URL.cachesDirectory.appending(path: "HistorySummary", directoryHint: .isDirectory) }

    private struct File: Codable {
        var version: Int
        var token: DefaultHistoryToken
        var parts: HistoryParts
    }

    private weak var context: ModelContext?
    private var parts = HistoryParts()
    /// The last change the pieces include.
    private var token: DefaultHistoryToken?
    /// The `HistoryChanges` count the pieces were last caught up to.
    private var checked: Int?
    private var unsaved = false
    private var kept: (revision: Int, familiarity: ExerciseFamiliarity)?

    /// Moves whenever the pieces change, so what's built from them knows to rebuild.
    private(set) var revision = 0
    /// How many times every piece was built from scratch.
    private(set) var fullBuilds = 0

    /// One per app; tests make their own to stand in for a relaunch.
    init() {
        // Written when the app leaves the screen rather than after every set.
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                self?.saveIfNeeded()
            }
        }
    }

    /// The pieces for `context`'s store, caught up on every saved change.
    func parts(in context: ModelContext, calendar: Calendar = .current) -> HistoryParts {
        HistoryChanges.shared.watch(context.container)
        // Read here, so a view built from the pieces redraws after the next saved change.
        let count = HistoryChanges.shared.count
        if self.context !== context || parts.calendar != HistoryParts.calendarStamp(calendar) {
            open(context, calendar: calendar)
        } else if checked != count {
            catchUp(in: context, calendar: calendar)
        }
        checked = count
        return parts
    }

    /// How much each lift belongs to recent training, for the exercise picker.
    func familiarity(in context: ModelContext) -> ExerciseFamiliarity {
        let parts = parts(in: context)
        if let kept, kept.revision == revision { return kept.familiarity }
        let familiarity = parts.familiarity
        kept = (revision, familiarity)
        return familiarity
    }

    /// Deletes the file and forgets the pieces. The next Data tab or picker builds them again.
    /// Training data is never touched.
    func clear() {
        do {
            if FileManager.default.fileExists(atPath: Self.directory.path) {
                try FileManager.default.removeItem(at: Self.directory)
            }
        } catch {
            Logger.persistence.error("Could not delete the local history cache: \(error.localizedDescription)")
        }
        context = nil
        parts = HistoryParts()
        token = nil
        checked = nil
        unsaved = false
        kept = nil
        revision += 1
        StudyHistory.forget()
        Logger.persistence.info("Cleared the local history cache")
    }

    /// Writes the file if the pieces changed since it was last written.
    func saveIfNeeded() {
        guard unsaved, let context, let token, !Self.isInMemory(context), let url = Self.fileURL(for: token) else { return }
        do {
            let data = try JSONEncoder().encode(File(version: Self.fileVersion, token: token, parts: parts))
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            unsaved = false
        } catch {
            Logger.persistence.error("Could not save the local history cache: \(error.localizedDescription)")
        }
    }

    // MARK: Opening

    private func open(_ context: ModelContext, calendar: Calendar) {
        saveIfNeeded()
        self.context = context
        kept = nil
        let latest = Self.latestToken(in: context)
        if let latest, !Self.isInMemory(context), let file = Self.readFile(for: latest),
           file.version == Self.fileVersion, file.token <= latest,
           file.parts.calendar == HistoryParts.calendarStamp(calendar) {
            parts = file.parts
            token = file.token
            unsaved = false
            revision += 1
            catchUp(in: context, calendar: calendar)
        } else {
            rebuild(in: context, calendar: calendar)
        }
    }

    private func rebuild(in context: ModelContext, calendar: Calendar) {
        // Taken first, so a change landing while the pieces are built is caught up on next time.
        token = Self.latestToken(in: context)
        parts = HistoryParts(context: context, calendar: calendar)
        fullBuilds += 1
        revision += 1
        unsaved = true
        saveIfNeeded()
    }

    /// The file for `context`'s store, whether or not it was written yet.
    func fileURL(in context: ModelContext) -> URL? {
        Self.latestToken(in: context).flatMap(Self.fileURL(for:))
    }

    private static func isInMemory(_ context: ModelContext) -> Bool {
        context.container.configurations.contains(where: \.isStoredInMemoryOnly)
    }

    private static func latestToken(in context: ModelContext) -> DefaultHistoryToken? {
        // Sorted by token: Release builds refuse `\.id` as an unsupported key path.
        var last = HistoryDescriptor<DefaultHistoryTransaction>(sortBy: [SortDescriptor(\.token, order: .reverse)])
        last.fetchLimit = 1
        return (try? context.fetchHistory(last))?.first?.token
    }

    /// One file per store, named after the store the change log belongs to.
    private static func fileURL(for token: DefaultHistoryToken) -> URL? {
        guard let stores = token.tokenValue?.keys.sorted(), !stores.isEmpty else { return nil }
        return directory.appending(path: "\(stores.joined(separator: "-")).json")
    }

    private static func readFile(for token: DefaultHistoryToken) -> File? {
        guard let url = fileURL(for: token), let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(File.self, from: data)
        } catch {
            Logger.persistence.error("The local history cache couldn't be read, building it again: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Catching up

    /// The rows the change log says changed, grouped by what they feed.
    private struct Changes {
        var workouts: Set<PersistentIdentifier> = []
        var deletedWorkouts: Set<PersistentIdentifier> = []
        var slots: Set<PersistentIdentifier> = []
        var sets: Set<PersistentIdentifier> = []
        var feedback: Set<PersistentIdentifier> = []
        var weeks: Set<PersistentIdentifier> = []
        var programs: Set<PersistentIdentifier> = []
        var deletedPrograms = false
        var exercises = false
        var archive = false
        var imported = false
        var logs = false
        var unknown: String?

        /// Rows that never feed the Data tab or the picker.
        static let ignored: Set<String> = [
            "\(TemplateProgram.self)", "\(TemplateWorkout.self)", "\(TemplateExercise.self)", "\(SetReceipt.self)",
            "\(StrengthLog.self)", "\(DeviceSchemaMark.self)",
        ]
        static let lifts: Set<String> = [
            "\(Exercise.self)", "\(CustomEquipment.self)", "\(Joint.self)", "\(JointMovement.self)", "\(ExerciseJointAction.self)",
        ]
        static let archive: Set<String> = ["\(HistoryRecord.self)", "\(HistoryProgram.self)", "\(HistoryExercise.self)"]

        mutating func add(_ id: PersistentIdentifier, deleted: Bool) {
            let entity = id.entityName
            // A deleted child also changes its parent's row, which the log records too.
            switch entity {
            case "\(Workout.self)": if deleted { deletedWorkouts.insert(id) } else { workouts.insert(id) }
            case "\(WorkoutExercise.self)": if !deleted { slots.insert(id) }
            case "\(WorkoutSet.self)": if !deleted { sets.insert(id) }
            case "\(ExerciseFeedback.self)": if !deleted { feedback.insert(id) }
            case "\(ProgramWeek.self)": if !deleted { weeks.insert(id) }
            case "\(Program.self)": if deleted { deletedPrograms = true } else { programs.insert(id) }
            case "\(WorkoutLog.self)": logs = true
            case "\(ImportedSet.self)": imported = true
            default:
                if Self.lifts.contains(entity) {
                    exercises = true
                } else if Self.archive.contains(entity) {
                    archive = true
                } else if !Self.ignored.contains(entity) {
                    unknown = entity
                }
            }
        }
    }

    private func catchUp(in context: ModelContext, calendar: Calendar) {
        guard let token else { return rebuild(in: context, calendar: calendar) }
        let transactions: [DefaultHistoryTransaction]
        do {
            transactions = try context.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>(
                predicate: #Predicate { $0.token > token }))
        } catch {
            Logger.persistence.error("Could not read the store's changes, building history again: \(error.localizedDescription)")
            return rebuild(in: context, calendar: calendar)
        }
        guard let newest = transactions.map(\.token).max() else { return }
        var changes = Changes()
        for transaction in transactions {
            for change in transaction.changes {
                switch change {
                case .insert(let insert): changes.add(insert.changedPersistentIdentifier, deleted: false)
                case .update(let update): changes.add(update.changedPersistentIdentifier, deleted: false)
                case .delete(let delete): changes.add(delete.changedPersistentIdentifier, deleted: true)
                @unknown default: changes.unknown = "a new kind of change"
                }
            }
        }
        if let unknown = changes.unknown {
            Logger.persistence.info("History changed in \(unknown, privacy: .public), building it again")
            return rebuild(in: context, calendar: calendar)
        }
        if apply(changes, in: context, calendar: calendar) {
            revision += 1
        }
        self.token = newest
        unsaved = true
    }

    /// Rebuilds the pieces `changes` touched. - Returns: Whether any piece changed.
    private func apply(_ changes: Changes, in context: ModelContext, calendar: Calendar) -> Bool {
        var dirty = changes.workouts
        dirty.formUnion(fetch(WorkoutExercise.self, changes.slots, in: context).compactMap { $0.workoutValue?.persistentModelID })
        dirty.formUnion(fetch(WorkoutSet.self, changes.sets, in: context).compactMap {
            $0.workoutExerciseValue?.workoutValue?.persistentModelID
        })
        dirty.formUnion(fetch(ExerciseFeedback.self, changes.feedback, in: context).compactMap {
            $0.workoutExerciseValue?.workoutValue?.persistentModelID
        })
        for week in fetch(ProgramWeek.self, changes.weeks, in: context) {
            let id = HistoryParts.rowID(week.persistentModelID)
            let print = HistoryParts.print(of: week)
            guard parts.weekPrints[id] != print else { continue }
            parts.weekPrints[id] = print
            dirty.formUnion(week.workouts.map(\.persistentModelID))
        }
        var archive = changes.archive || changes.deletedPrograms
        for program in fetch(Program.self, changes.programs, in: context) {
            let id = HistoryParts.rowID(program.persistentModelID)
            let print = HistoryParts.print(of: program)
            guard parts.programPrints[id] != print else { continue }
            parts.programPrints[id] = print
            dirty.formUnion(program.programWeeks.flatMap(\.workouts).map(\.persistentModelID))
            archive = true
        }
        var edited: Set<String> = []
        if changes.exercises {
            let current = Dictionary(all(Exercise.self, in: context).map {
                (HistoryParts.rowID($0.persistentModelID), HistoryParts.print(of: $0))
            }, uniquingKeysWith: { first, _ in first })
            var lifts: Set<Int> = []
            for (index, lift) in parts.exercises.enumerated() where current[lift.id] != lift.text {
                parts.exercises[index].text = current[lift.id] ?? ""
                lifts.insert(index)
            }
            if !lifts.isEmpty {
                edited = Set(parts.workouts.filter { !lifts.isDisjoint(with: $0.value.lifts) }.keys)
            }
        }

        let changed = !dirty.isEmpty || !edited.isEmpty || !changes.deletedWorkouts.isEmpty || archive
            || changes.exercises || changes.imported || changes.logs
        let rebuilt = Set(dirty.map(HistoryParts.rowID)).union(edited)
        for id in rebuilt.union(changes.deletedWorkouts.map(HistoryParts.rowID)) {
            parts.workouts[id] = nil
        }
        let found = fetch(Workout.self, dirty, in: context)
            + (edited.isEmpty ? [] : all(Workout.self, in: context).filter { edited.contains(HistoryParts.rowID($0.persistentModelID)) })
        for workout in found {
            guard let week = workout.programWeekValue, let program = week.programValue else { continue }
            parts.workouts[HistoryParts.rowID(workout.persistentModelID)] = parts.part(of: workout, in: week, of: program)
        }
        if changes.deletedPrograms {
            let programs = Set(all(Program.self, in: context).map { HistoryParts.rowID($0.persistentModelID) })
            parts.programPrints = parts.programPrints.filter { programs.contains($0.key) }
        }
        if archive {
            let live = Set(all(Program.self, in: context).compactMap(\.syncID))
            let rows = (try? HistoryArchive.archivedRows(excluding: live, in: context)) ?? []
            parts.archived = HistoryParts.archived(rows, live: live)
        }
        if changes.exercises || changes.imported {
            parts.setImported(all(ImportedSet.self, in: context), exercises: all(Exercise.self, in: context), calendar: calendar)
        }
        if changes.logs {
            parts.logs = HistoryParts.logs(all(WorkoutLog.self, in: context))
        }
        return changed
    }

    private func all<Model: PersistentModel>(_: Model.Type, in context: ModelContext) -> [Model] {
        (try? context.fetch(FetchDescriptor<Model>())) ?? []
    }

    private func fetch<Model: PersistentModel>(_: Model.Type, _ ids: Set<PersistentIdentifier>, in context: ModelContext) -> [Model] {
        guard !ids.isEmpty else { return [] }
        let list = Array(ids)
        return (try? context.fetch(FetchDescriptor<Model>(predicate: #Predicate { list.contains($0.persistentModelID) }))) ?? []
    }
}

extension HistoryParts {
    /// Every piece, fetched from the store. Saved rows of live programs and old rows that lean
    /// rows replace are never loaded.
    init(context: ModelContext, calendar: Calendar) {
        func all<Model: PersistentModel>(_: Model.Type) -> [Model] {
            (try? context.fetch(FetchDescriptor<Model>())) ?? []
        }
        let programs = all(Program.self)
        let archive = (try? HistoryArchive.archivedRows(excluding: Set(programs.compactMap(\.syncID)), in: context)) ?? []
        self.init(programs: programs, archive: archive, logs: all(WorkoutLog.self), imported: all(ImportedSet.self),
                  exercises: all(Exercise.self), calendar: calendar)
    }
}
