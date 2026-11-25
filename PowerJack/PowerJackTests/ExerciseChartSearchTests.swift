import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
struct ExerciseChartSearchTests {
    @Test("Bench focuses three muscles and ranks bench variants before other horizontal presses")
    func benchFamily() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let bench = try #require(exercises.first { $0.catalogID == "barbell-bench-press" })
        bench.exerciseName = "Competition Lift"
        let pushUp = try #require(exercises.first { $0.catalogID == "push-up" })

        let index = ExerciseChartSearch.Index(exercises.map(ExerciseChartSearch.Document.init))
        for query in ["bench press", "BENCH pr", "benchpress"] {
            let result = try #require(index.results(for: query))
            #expect(result.muscles == [.chest, .triceps, .shoulders])
            #expect(Set(exercises.filter { result.ranks[$0.persistentModelID] != nil }.compactMap(\.catalogID)) ==
                Set(ExerciseCatalog.entries.filter { $0.profile.pattern == .horizontalPress }.map(\.id)))
            #expect(try #require(result.ranks[bench.persistentModelID]) < #require(result.ranks[pushUp.persistentModelID]))
        }
        #expect(index.results(for: "  ") == nil)
        #expect(index.results(for: "no such movement")?.ranks.isEmpty == true)
    }

    @Test("Joint action, style, muscle and custom names are searchable without a network")
    func metadata() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        let custom = Exercise(exerciseName: "Landmine twist", exerciseEquipment: .barbell, primaryMuscleFocus: .obliques, userCreated: true)
        context.insert(custom)
        try context.save()
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let index = ExerciseChartSearch.Index(exercises.map(ExerciseChartSearch.Document.init))
        for query in ["resists trunk lateral flexion", "isometric"] {
            let result = try #require(index.results(for: query))
            #expect(exercises.filter { result.ranks[$0.persistentModelID] != nil }.map(\.catalogID) == ["side-plank"])
        }
        #expect(index.results(for: "produces trunk lateral flexion")?.ranks.isEmpty == true)
        #expect(index.results(for: "triceps")?.muscles == [.triceps])
        #expect(index.results(for: "landmine")?.ranks.keys.first == custom.persistentModelID)
    }

    @Test("Natural-language region searches select the right muscles for built-in and custom lifts")
    func semanticSearch() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        let custom = Exercise(exerciseName: "Friday variation", exerciseEquipment: .machine, primaryMuscleFocus: .quads, userCreated: true)
        context.insert(custom)
        try context.save()
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let index = ExerciseChartSearch.Index(exercises.map(ExerciseChartSearch.Document.init))
        let legs: Set<Muscle> = [.quads, .glutes, .hamstrings, .calves]
        for query in ["legs", "leg day", "lower body", "training my lower limbs", "what did I do on leg day"] {
            let result = try #require(index.results(for: query))
            #expect(result.muscles == legs, "\(query)")
            let ids = Set(exercises.filter { result.ranks[$0.persistentModelID] != nil }.compactMap(\.catalogID))
            #expect(ids.isSuperset(of: ["smith-machine-squat", "seated-leg-curl", "standing-calf-raise", "glute-bridge"]), "\(query)")
            #expect(ids.isDisjoint(with: ["barbell-bench-press", "hanging-leg-raise"]), "\(query)")
            #expect(result.ranks[custom.persistentModelID] != nil)
        }
        #expect(index.results(for: "pecs")?.muscles == [.chest])
        #expect(index.results(for: "core training")?.muscles == [.abs, .obliques])
        #expect(index.results(for: "arm day")?.muscles == [.biceps, .triceps, .forearms])
        #expect(index.results(for: "peanut butter")?.ranks.isEmpty == true)
        #expect(index.results(for: "leg press")?.ranks.count == 1)
        let curls = try #require(index.results(for: "leg curls"))
        #expect(Set(exercises.filter { curls.ranks[$0.persistentModelID] != nil }.compactMap(\.catalogID)) ==
            ["seated-leg-curl", "lying-leg-curl", "sliding-leg-curl"])
        let presses = try #require(index.results(for: "dumbbell bench press"))
        #expect(!presses.ranks.isEmpty)
        #expect(exercises.filter { presses.ranks[$0.persistentModelID] != nil }.allSatisfy { $0.equipment == .dumbbell })
        let dumbbellLegs = try #require(index.results(for: "dumbbell leg exercises"))
        #expect(dumbbellLegs.muscles == legs)
        #expect(!dumbbellLegs.ranks.isEmpty)
        #expect(exercises.filter { dumbbellLegs.ranks[$0.persistentModelID] != nil }.allSatisfy { $0.equipment == .dumbbell })
    }

    @Test("Arm searches rank direct biceps and triceps work before forearms, assistance and related movements")
    func combinedArmRanking() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        let custom = Exercise(exerciseName: "Friday finisher", exerciseEquipment: .cable, primaryMuscleFocus: .triceps, userCreated: true)
        context.insert(custom)
        try context.save()
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let index = ExerciseChartSearch.Index(exercises.map(ExerciseChartSearch.Document.init))
        let direct = exercises.filter { [.biceps, .triceps].contains($0.primaryMuscleFocus) }
        let row = try #require(exercises.first { $0.catalogID == "one-arm-dumbbell-row" })
        let wrist = try #require(exercises.first { $0.catalogID == "dumbbell-wrist-curl" })
        let facePull = try #require(exercises.first { $0.catalogID == "cable-face-pull" })
        for query in ["arms", "ARM", "arm day", "pulling with my arms"] {
            let result = try #require(index.results(for: query))
            #expect(result.muscles == [.biceps, .triceps, .forearms])
            let directRanks = try direct.map { try #require(result.ranks[$0.persistentModelID]) }
            let wristRank = try #require(result.ranks[wrist.persistentModelID])
            let rowRank = try #require(result.ranks[row.persistentModelID])
            #expect(try #require(directRanks.max()) < wristRank)
            #expect(wristRank < rowRank)
        }
        let pulling = try #require(index.results(for: "pulling with my arms"))
        #expect(try #require(pulling.ranks[row.persistentModelID]) < #require(pulling.ranks[facePull.persistentModelID]))
        let specific = try #require(index.results(for: "one arm row"))
        #expect(specific.ranks[row.persistentModelID] == specific.ranks.values.min())
        let dumbbells = try #require(index.results(for: "dumbbell arms"))
        #expect(dumbbells.ranks[row.persistentModelID] != nil)
        #expect(exercises.filter { dumbbells.ranks[$0.persistentModelID] != nil }.allSatisfy { $0.equipment == .dumbbell })
    }

    @Test("Warm searches complete within an interactive latency budget")
    func latency() throws {
        let container = try PowerJackSchema.makeModelContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        let documents = try context.fetch(FetchDescriptor<Exercise>()).map(ExerciseChartSearch.Document.init)
        let url = try #require(Bundle.main.url(forResource: "ExerciseEmbeddings", withExtension: "bin"))
        let start = DispatchTime.now().uptimeNanoseconds
        let index = try ExerciseChartSearch.Index(documents, encoder: ExerciseTextEncoder(url: url))
        let buildMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let queries = ["le", "leg", "legs", "shoulder", "leg day", "my lower limbs", "upper body", "pecs", "bench press", "core", "arms", "pulling with my arms"]
        var times: [Double] = []
        for _ in 0..<12 {
            for query in queries {
                let start = DispatchTime.now().uptimeNanoseconds
                let result = index.results(for: query)
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                #expect(result != nil)
            }
        }
        times.sort()
        let p95 = times[times.count * 95 / 100]
        print("Exercise search: model load and catalog prep \(buildMS) ms, query median \(times[times.count / 2]) ms, p95 \(p95) ms across \(times.count) queries")
        #expect(p95 < 50)
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
