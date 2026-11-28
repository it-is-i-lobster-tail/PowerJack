//
//  PlanBuilderGridTests.swift
//  PowerJackTests
//
//  Build for Me's code-only builder across every type, day count, equipment preset and session
//  length, and its repair of junk plans. No model and no SwiftData.
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct PlanBuilderGridTests {
    struct Preset {
        let name: String
        let equipment: Set<Equipment>
        let setups: Set<ExerciseFilters.Setup>
        /// Whether a thin result is expected to be possible.
        var canBeThin = false
    }

    static let presets: [Preset] = [
        Preset(name: "full gym", equipment: TemplateRequest.allEquipment, setups: TemplateRequest.allSetups),
        Preset(name: "home dumbbells and bench", equipment: [.dumbbell, .bodyweight], setups: [.bench]),
        Preset(name: "bodyweight only", equipment: [.bodyweight], setups: [], canBeThin: true),
        Preset(name: "machines only", equipment: [.machine], setups: [], canBeThin: true),
        Preset(name: "barbell and bench", equipment: [.barbell], setups: [.bench], canBeThin: true),
        Preset(name: "cables and dumbbells", equipment: [.cable, .dumbbell], setups: [.bench]),
        Preset(name: "kettlebell and bodyweight", equipment: [.kettlebell, .bodyweight], setups: [.pullUpBar], canBeThin: true),
        Preset(name: "no bench or pull-up bar", equipment: TemplateRequest.allEquipment, setups: []),
    ]

    /// None, the most common big four, arms, and the four smallest.
    static let focusSets: [[Muscle]] = [
        [],
        [.chest, .back, .quads, .shoulders],
        [.biceps, .triceps],
        [.calves, .abs, .forearms, .obliques],
    ]

    static func requests() -> [TemplateRequest] {
        var requests: [TemplateRequest] = []
        var index = 0
        for type in TemplateType.allCases {
            for days in 2...6 {
                for preset in presets {
                    for minutes in TemplateRequest.sessionLengths {
                        for focus in focusSets {
                            index += 1
                            requests.append(TemplateRequest(
                                type: type, workoutsPerWeek: days, focus: focus, equipment: preset.equipment,
                                setups: preset.setups, sessionMinutes: minutes,
                                lean: TemplateRequest.Lean.allCases[index % 3], supersets: index % 2 == 0
                            ))
                        }
                    }
                }
            }
        }
        return requests
    }

    static func label(_ request: TemplateRequest) -> String {
        let preset = presets.first { $0.equipment == request.equipment && $0.setups == request.setups }?.name ?? "?"
        return "\(request.type) \(request.workoutsPerWeek)x \(preset) \(request.sessionMinutes)min focus \(request.focus.map(\.rawValue)) \(request.lean) supersets \(request.supersets)"
    }

    @Test("Every code-only template passes every rule, or says there isn't enough equipment")
    func grid() {
        var failures: [String] = []
        for request in Self.requests() {
            let builder = PlanBuilder(request: request, exercises: BuilderExercise.catalog)
            switch builder.build() {
            case .plan(let plan):
                let violations = builder.rules.violations(plan)
                if !violations.isEmpty {
                    failures.append("\(Self.label(request)): \(violations.map(\.description).joined(separator: "; "))")
                }
            case .notEnoughEquipment:
                let preset = Self.presets.first { $0.equipment == request.equipment && $0.setups == request.setups }
                if preset?.canBeThin != true { failures.append("\(Self.label(request)): not enough equipment") }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) failures, first: \(failures.prefix(15).joined(separator: "\n"))")
    }

    @Test("Strength and PowerJack can't be built from bodyweight alone")
    func bodyweightHasNoMainLift() {
        for type in [TemplateType.strength, .powerJack] {
            let request = TemplateRequest(type: type, equipment: [.bodyweight], setups: [])
            #expect(PlanBuilder(request: request, exercises: BuilderExercise.catalog).build() == .notEnoughEquipment)
        }
    }

    @Test("A gym with only two exercises isn't enough")
    func tooFewExercises() {
        let request = TemplateRequest(equipment: [.legPress], setups: [])
        let exercises = BuilderExercise.catalog.filter { $0.equipment == .legPress } + [BuilderExercise.catalog[0]]
        #expect(PlanBuilder(request: request, exercises: exercises).build() == .notEnoughEquipment)
    }

    @Test("Repair turns thousands of junk plans into plans that pass every rule")
    func junkPlans() {
        var generator = SeededGenerator(seed: 1)
        let ids = BuilderExercise.catalog.map(\.id) + ["not-an-exercise", "", "barbell-bench-press "]
        var failures: [String] = []
        // Every fifth request of the grid, six junk plans each.
        let builders = Self.requests().enumerated().filter { $0.offset % 5 == 0 }
            .map { PlanBuilder(request: $0.element, exercises: BuilderExercise.catalog) }
            .filter { $0.build() != .notEnoughEquipment }
        for seed in 0..<(builders.count * 6) {
            let builder = builders[seed / 6]
            let request = builder.request
            let junk = Self.junkPlan(kind: seed % 6, ids: ids, request: request, using: &generator)
            let repaired = builder.repair(junk)
            let violations = builder.rules.violations(repaired)
            if !violations.isEmpty {
                failures.append("seed \(seed) kind \(seed % 6) \(Self.label(request)): \(violations.map(\.description).joined(separator: "; "))")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) failures, first: \(failures.prefix(10).joined(separator: "\n"))")
    }

    /// Random, empty, repeated, all one muscle, too long, or a wrong number of days.
    static func junkPlan(kind: Int, ids: [String], request: TemplateRequest, using generator: inout SeededGenerator) -> TemplatePlan {
        func randomID() -> String { ids[Int.random(in: 0..<ids.count, using: &generator)] }
        let dayCount = kind == 5 ? Int.random(in: 0...9, using: &generator) : request.workoutsPerWeek
        let days: [TemplatePlan.Day] = (0..<dayCount).map { _ in
            var exerciseIDs: [String]
            switch kind {
            case 0: exerciseIDs = (0..<Int.random(in: 0...10, using: &generator)).map { _ in randomID() }
            case 1: exerciseIDs = []
            case 2: exerciseIDs = Array(repeating: randomID(), count: Int.random(in: 1...8, using: &generator))
            case 3:
                let muscle = Muscle.allCases[Int.random(in: 0..<Muscle.allCases.count, using: &generator)]
                exerciseIDs = BuilderExercise.catalog.filter { $0.primary == muscle }.map(\.id)
            case 4: exerciseIDs = (0..<Int.random(in: 12...30, using: &generator)).map { _ in randomID() }
            default: exerciseIDs = (0..<Int.random(in: 0...8, using: &generator)).map { _ in randomID() }
            }
            var supersets: [TemplatePlan.Superset] = []
            if exerciseIDs.count >= 2 {
                for _ in 0..<Int.random(in: 0...3, using: &generator) {
                    supersets.append(.init(first: exerciseIDs.randomElement(using: &generator)!,
                                           second: exerciseIDs.randomElement(using: &generator)!))
                }
            }
            return TemplatePlan.Day(exerciseIDs: exerciseIDs, supersets: supersets)
        }
        let names = ["", "My Plan", String(repeating: "x", count: 80), "  "]
        return TemplatePlan(name: names[Int.random(in: 0..<names.count, using: &generator)], days: days)
    }
}

/// SplitMix64, so every run makes the same junk.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
