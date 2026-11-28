import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
struct ExerciseSearchTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try PowerJackSchema.makeModelContainer(inMemory: true)
        context = container.mainContext
        try ExerciseCatalog.seed(in: context)
    }

    private func exercises() throws -> [Exercise] { try context.fetch(FetchDescriptor<Exercise>()) }

    private func index(_ exercises: [Exercise]) -> ExerciseSearch.Index {
        ExerciseSearch.Index(exercises.map(ExerciseSearch.Document.init))
    }

    /// Ranked catalog IDs, or names for own exercises.
    private func ranked(_ query: String, in index: ExerciseSearch.Index, _ exercises: [Exercise],
                        familiarity: ExerciseFamiliarity = .none) -> [String] {
        let byKey = Dictionary(uniqueKeysWithValues: exercises.map { ($0.searchKey, $0.catalogID ?? $0.exerciseName) })
        return index.rank(ExerciseQuery(query), familiarity: familiarity).compactMap { byKey[$0.key] }
    }

    private func entries(_ include: (ExerciseCatalog.Entry) -> Bool) -> Set<String> {
        Set(ExerciseCatalog.entries.filter(include).map(\.id))
    }

    private func catalog(_ id: String) -> ExerciseCatalog.Entry {
        ExerciseCatalog.entries.first { $0.id == id }!
    }

    // MARK: - Acceptance table

    @Test("Seeded catalog acceptance queries")
    func acceptance() throws {
        let all = try exercises()
        let index = index(all)
        func shown(_ query: String) -> [String] { ranked(query, in: index, all) }

        let squats = entries { $0.profile.family == .squat || $0.profile.family == .splitSquatLunge }
        #expect(squats.count == 17)
        #expect(Set(shown("squats")).isSuperset(of: squats))

        let primary = entries { $0.primaryMuscle == .hamstrings }
        let hamstrings = entries { $0.primaryMuscle == .hamstrings || $0.secondaryMuscles.contains(.hamstrings) }
        #expect(hamstrings.count == 30)
        let hamstring = shown("hamstring")
        #expect(Set(hamstring).isSuperset(of: hamstrings))
        #expect(Set(hamstring.prefix(primary.count)) == primary)

        #expect(shown("rdl").first == "barbell-romanian-deadlift")
        #expect(shown("ohp").first == "barbell-overhead-press")
        #expect(shown("military press").first == "barbell-overhead-press")
        let dumbbellPresses = entries { $0.equipment == .dumbbell && $0.name.contains("Press") }
        #expect(Set(shown("db press").prefix(dumbbellPresses.count)) == dumbbellPresses)
        #expect(shown("pullups").first == "pull-up")
        #expect(shown("barbell shrug").contains("dumbbell-shrug"))
        #expect(Set(shown("hex bar").prefix(2)) == ["trap-bar-deadlift", "trap-bar-shrug"])
        #expect(shown("hex bar shrug").first == "trap-bar-shrug")
        #expect(shown("knee extension").prefix(3).contains("leg-extension"))
        #expect(shown("peanut butter").isEmpty)
    }

    // MARK: - Familiarity

    @Test("A lift logged in the last 3 sessions beats an equal match")
    func familiarLiftFirst() throws {
        let first = Exercise(exerciseName: "Landmine Press", exerciseEquipment: .barbell, primaryMuscleFocus: .shoulders, userCreated: true)
        let second = Exercise(exerciseName: "Landmine Press", exerciseEquipment: .barbell, primaryMuscleFocus: .shoulders, userCreated: true)
        first.assignSyncID()
        second.assignSyncID()
        context.insert(first)
        context.insert(second)
        try context.save()
        let all = try exercises()
        let index = index(all)
        let other = "catalog:barbell-bench-press"
        let familiarity = ExerciseFamiliarity(sessions: [[other], [second.searchKey], [second.searchKey], [second.searchKey]])
        for query in ["landmine press", "landmine"] {
            let keys = index.rank(ExerciseQuery(query), familiarity: familiarity).map(\.key).filter {
                [first.searchKey, second.searchKey].contains($0)
            }
            #expect(keys == [second.searchKey, first.searchKey], "\(query)")
        }
        // With no query, lifts the lifter trains are listed, most familiar first.
        #expect(index.rank(ExerciseQuery(""), familiarity: familiarity).map(\.key) == [second.searchKey, other])
    }

    // MARK: - Search behaviour kept from the chart search

    @Test("Bench ranks bench variants before other horizontal presses")
    func benchFamily() throws {
        let all = try exercises()
        let bench = try #require(all.first { $0.catalogID == "barbell-bench-press" })
        bench.exerciseName = "Competition Lift"
        let index = index(all)
        let presses = entries { $0.profile.pattern == .horizontalPress }
        let benches = entries { $0.name.contains("Bench Press") }
        for query in ["bench press", "benchpress"] {
            let result = ranked(query, in: index, all)
            // Every bench press, then other presses until the cutoff: with the Smith presses, the
            // floor press and incline push-up fall past it.
            #expect(benches.isSubset(of: Set(result)) && Set(result).isSubset(of: presses), "\(query)")
            #expect(try #require(result.firstIndex(of: "barbell-bench-press")) < (result.firstIndex(of: "push-up") ?? result.count))
        }
        // A half-typed word still finds every bench variant, and nothing but presses.
        let partial = ranked("BENCH pr", in: index, all)
        #expect(benches.isSubset(of: Set(partial)))
        #expect(Set(partial).isSubset(of: presses))
        #expect(try #require(partial.firstIndex(of: "barbell-bench-press")) < (partial.firstIndex(of: "push-up") ?? partial.count))
        #expect(ranked("  ", in: index, all).isEmpty)
        #expect(ranked("no such movement", in: index, all).isEmpty)
    }

    @Test("Joint action, style, muscle and custom names are searchable without a network")
    func metadata() throws {
        let custom = Exercise(exerciseName: "Landmine twist", exerciseEquipment: .barbell, primaryMuscleFocus: .obliques, userCreated: true)
        context.insert(custom)
        try context.save()
        let all = try exercises()
        let index = index(all)
        for query in ["resists trunk lateral flexion", "isometric"] {
            #expect(ranked(query, in: index, all) == ["side-plank"], "\(query)")
        }
        #expect(ranked("produces trunk lateral flexion", in: index, all).isEmpty)
        let triceps = ranked("triceps", in: index, all)
        let direct = entries { $0.primaryMuscle == .triceps }
        #expect(Set(triceps.prefix(direct.count)) == direct)
        #expect(ranked("landmine", in: index, all).first == "Landmine twist")
    }

    @Test("Natural-language region searches select the right muscles for built-in and custom lifts")
    func semanticSearch() throws {
        let custom = Exercise(exerciseName: "Friday variation", exerciseEquipment: .machine, primaryMuscleFocus: .quads, userCreated: true)
        context.insert(custom)
        try context.save()
        let all = try exercises()
        let index = index(all)
        let legs: Set<Muscle> = [.quads, .glutes, .hamstrings, .calves]
        func primaries(_ ids: [String]) -> [Muscle] {
            ids.map { id in ExerciseCatalog.entries.first { $0.id == id }?.primaryMuscle ?? .quads }
        }
        for query in ["legs", "leg day", "lower body", "training my lower limbs", "what did I do on leg day"] {
            let ids = ranked(query, in: index, all)
            #expect(Set(ids).isSuperset(of: ["smith-machine-squat", "seated-leg-curl", "standing-calf-raise", "glute-bridge"]), "\(query)")
            #expect(Set(ids).isDisjoint(with: ["barbell-bench-press", "hanging-leg-raise"]), "\(query)")
            #expect(ids.contains("Friday variation"), "\(query)")
            #expect(primaries(Array(ids.prefix(5))).allSatisfy(legs.contains), "\(query)")
        }
        #expect(primaries(Array(ranked("pecs", in: index, all).prefix(5))).allSatisfy { $0 == .chest })
        #expect(primaries(Array(ranked("core training", in: index, all).prefix(5))).allSatisfy { [.abs, .obliques].contains($0) })
        #expect(primaries(Array(ranked("arm day", in: index, all).prefix(5))).allSatisfy { [.biceps, .triceps].contains($0) })
        #expect(ranked("peanut butter", in: index, all).isEmpty)
        #expect(ranked("leg press", in: index, all) == ["leg-press"])
        #expect(Set(ranked("leg curls", in: index, all)) == ["seated-leg-curl", "lying-leg-curl", "sliding-leg-curl", "nordic-hamstring-curl"])
        // Equipment ranks first but no longer hides the rest.
        let presses = ranked("dumbbell bench press", in: index, all)
        let dumbbellBench = entries { $0.equipment == .dumbbell && $0.name.contains("Bench Press") }
        #expect(Set(presses.prefix(dumbbellBench.count)) == dumbbellBench)
        #expect(presses.contains("barbell-bench-press"))
        let dumbbellLegs = ranked("dumbbell leg exercises", in: index, all)
        #expect(!dumbbellLegs.isEmpty)
        #expect(dumbbellLegs.prefix(3).allSatisfy { catalog($0).equipment == .dumbbell && legs.contains(catalog($0).primaryMuscle) })
    }

    @Test("Arm searches rank direct biceps and triceps work before forearms, assistance and related movements")
    func combinedArmRanking() throws {
        let custom = Exercise(exerciseName: "Friday finisher", exerciseEquipment: .cable, primaryMuscleFocus: .triceps, userCreated: true)
        context.insert(custom)
        try context.save()
        let all = try exercises()
        let index = index(all)
        let direct = all.filter { [.biceps, .triceps].contains($0.primaryMuscleFocus) }.map { $0.catalogID ?? $0.exerciseName }
        for query in ["arms", "ARM", "arm day", "pulling with my arms"] {
            let result = ranked(query, in: index, all)
            let directRanks = try direct.map { id in try #require(result.firstIndex(of: id), "\(query) \(id)") }
            let wrist = try #require(result.firstIndex(of: "dumbbell-wrist-curl"), "\(query)")
            let row = try #require(result.firstIndex(of: "one-arm-dumbbell-row"), "\(query)")
            #expect(try #require(directRanks.max()) < wrist, "\(query)")
            #expect(wrist < row, "\(query)")
        }
        let pulling = ranked("pulling with my arms", in: index, all)
        let facePull = pulling.firstIndex(of: "cable-face-pull") ?? pulling.count
        #expect(try #require(pulling.firstIndex(of: "one-arm-dumbbell-row")) < facePull)
        #expect(ranked("one arm row", in: index, all).first == "one-arm-dumbbell-row")
        let dumbbells = ranked("dumbbell arms", in: index, all)
        #expect(dumbbells.contains("one-arm-dumbbell-row"))
        #expect(dumbbells.first.map { catalog($0).equipment } == .dumbbell)
    }

    @Test("Warm searches complete within an interactive latency budget")
    func latency() throws {
        let documents = try exercises().map(ExerciseSearch.Document.init)
        let url = try #require(Bundle.main.url(forResource: "ExerciseEmbeddings", withExtension: "bin"))
        let start = DispatchTime.now().uptimeNanoseconds
        let index = try ExerciseSearch.Index(documents, encoder: ExerciseTextEncoder(url: url))
        let buildMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let familiarity = ExerciseFamiliarity(sessions: documents.prefix(20).map { [$0.key] })
        let queries = ["le", "leg", "legs", "shoulder", "leg day", "my lower limbs", "upper body", "pecs", "bench press", "core", "arms", "pulling with my arms"]
        var times: [Double] = []
        for _ in 0..<12 {
            for query in queries {
                let start = DispatchTime.now().uptimeNanoseconds
                let result = index.rank(ExerciseQuery(query), familiarity: familiarity)
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                #expect(!result.isEmpty, "\(query)")
            }
        }
        times.sort()
        let p95 = times[times.count * 95 / 100]
        print("Exercise search: model load and catalog prep \(buildMS) ms, query median \(times[times.count / 2]) ms, p95 \(p95) ms across \(times.count) queries")
        #expect(p95 < 50)
    }
}

/// Query reading and familiarity need no store, so they skip the seeded catalog.
@MainActor
struct ExerciseQueryTests {
    @Test("Names and queries read joined, hyphenated, plural and shorthand forms alike", arguments: [
        ("Pull-Ups", ["pull", "up"]), ("pullups", ["pullup"]), ("pull ups", ["pull", "up"]),
        ("DB press", ["dumbbell", "press"]), ("ohp", ["overhead", "press"]), ("military press", ["overhead", "press"]),
        ("RDLs", ["romanian", "deadlift"]), ("hex bar", ["trap", "bar"]), ("pec deck", ["chest", "fly"]),
        ("skullcrushers", ["skull", "crusher"]), ("chins", ["chin", "up"]), ("EZ-Bar curls", ["ez", "bar", "curl"]),
        ("ez curl", ["ez", "bar", "curl"]), ("Crème squats", ["creme", "squat"]), ("LegPress", ["leg", "press"]),
        ("calves for my legs", ["calf", "leg"]),
    ])
    func words(text: String, words: [String]) {
        #expect(ExerciseQuery.words(text) == words)
    }

    @Test func equipmentAndMuscles() {
        let query = ExerciseQuery("db hamstring curls")
        #expect(query.equipment == [.dumbbell])
        #expect(query.muscles == [.hamstrings])
        #expect(query.nameWords == ["hamstring", "curl"])
        #expect(ExerciseQuery("pecs").muscles == [.chest])
        #expect(ExerciseQuery("triceps").muscles == [.triceps])
        #expect(ExerciseQuery("barbell").nameWords == ["barbell"])
        #expect(ExerciseQuery("  the ").isEmpty)
    }

    @Test("Familiarity counts sessions, fades older ones and stays within 0...1")
    func familiarityScores() {
        let familiarity = ExerciseFamiliarity(sessions: [["a"], ["a"], ["a", "b"], ["b"], ["b"]])
        #expect(familiarity.score("b") > familiarity.score("a"))
        #expect(familiarity.score("never") == 0)
        let always = ExerciseFamiliarity(sessions: Array(repeating: ["a"], count: 500))
        #expect(always.score("a") <= 1)
        #expect(always.score("a") > 0.99)
    }

    @Test("Time off without sessions leaves every score unchanged")
    func timeOffChangesNothing() {
        func imported(_ days: [String]) -> [ImportedSet] {
            days.enumerated().map { offset, day in
                let row = ImportedSet()
                row.trainingDay = day
                row.exerciseKey = offset.isMultiple(of: 2) ? "catalog:barbell-back-squat" : "catalog:barbell-bench-press"
                return row
            }
        }
        let steady = ExerciseFamiliarity.from(workouts: [], imported: imported(["2026-01-01", "2026-01-03", "2026-01-05"]))
        let gap = ExerciseFamiliarity.from(workouts: [], imported: imported(["2026-01-01", "2026-01-03", "2026-04-15"]))
        #expect(steady == gap)
        #expect(steady.score("catalog:barbell-back-squat") > steady.score("catalog:barbell-bench-press"))
    }

    @Test("Data search resolves calendar dates and saves any exercise terms", arguments: [
        (" Nov. ", WorkoutDateFilter.month(11, year: nil), ""),
        ("Nove", .month(11, year: nil), ""),
        ("novem", .month(11, year: nil), ""),
        ("JUNE", .month(6, year: nil), ""),
        ("2025", .year(2025), ""),
        ("bench press in June 2025", .month(6, year: 2025), "bench press"),
        ("arms 2025 Nov", .month(11, year: 2025), "arms"),
        ("November 9", .day(9, month: 11, year: nil), ""),
        ("Nove 9", .day(9, month: 11, year: nil), ""),
        ("bench press on Nov 9, 2025", .day(9, month: 11, year: 2025), "bench press"),
        ("May I see my arm work", nil, "May I see my arm work"),
        ("45 degree press", nil, "45 degree press"),
    ])
    func dateQueries(text: String, date: WorkoutDateFilter?, exercise: String) {
        let query = DataSearchQuery(text)
        #expect(query.dateFilter == date)
        #expect(query.exerciseText == exercise)
    }
}
