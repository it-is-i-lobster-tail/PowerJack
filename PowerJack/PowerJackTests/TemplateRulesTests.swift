//
//  TemplateRulesTests.swift
//  PowerJackTests
//
//  Each Build for Me guardrail (G1-G12) with a plan that passes it and one that breaks it.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct TemplateRulesTests {
    /// The only lifts these examples know, so a new built-in never changes what a rule can find.
    private static let fixtureIDs = [
        "barbell-back-squat", "barbell-bench-press", "barbell-deadlift", "barbell-overhead-press",
        "barbell-romanian-deadlift", "barbell-row", "cable-chest-fly", "cable-crunch", "cable-curl", "cable-face-pull",
        "cable-glute-kickback", "cable-lateral-raise", "cable-triceps-pushdown", "cable-woodchop",
        "chest-supported-dumbbell-row", "dumbbell-bench-press", "dumbbell-curl", "dumbbell-lateral-raise", "hack-squat",
        "incline-dumbbell-bench-press", "incline-dumbbell-curl", "lat-pulldown", "leg-extension", "leg-press",
        "lying-leg-curl", "machine-chest-press", "pull-up", "seated-cable-row", "seated-leg-curl", "standing-calf-raise",
    ]
    private static let fixture = BuilderExercise.catalog.filter { fixtureIDs.contains($0.id) }

    private func rules(_ request: TemplateRequest = TemplateRequest(workoutsPerWeek: 3)) -> TemplateRules {
        // Every allowed lift, so the examples needn't care which six of a muscle rank first.
        TemplateRules(request: request, candidates: BuilderCandidates(Self.fixture, for: request, perMuscle: 100))
    }

    @Test("Every lift the examples use is a built-in")
    func fixtureIsComplete() {
        #expect(Self.fixture.count == Self.fixtureIDs.count)
    }

    private func plan(_ days: [[String]], supersets: [[TemplatePlan.Superset]] = []) -> TemplatePlan {
        TemplatePlan(name: "Test", days: days.enumerated().map { index, ids in
            TemplatePlan.Day(exerciseIDs: ids, supersets: supersets.indices.contains(index) ? supersets[index] : [])
        })
    }

    private func rules(of violations: [TemplateViolation]) -> Set<TemplateViolation.Rule> { Set(violations.map(\.rule)) }

    // A Hypertrophy full body day that is in G9's order and fits 60 minutes.
    private let dayA = ["barbell-back-squat", "dumbbell-bench-press", "seated-cable-row", "dumbbell-lateral-raise", "seated-leg-curl"]
    private let dayB = ["barbell-romanian-deadlift", "incline-dumbbell-bench-press", "lat-pulldown", "cable-lateral-raise", "leg-extension"]
    private let dayC = ["hack-squat", "machine-chest-press", "chest-supported-dumbbell-row", "cable-face-pull", "cable-glute-kickback"]

    @Test("A sensible full body week passes every rule")
    func sensibleWeekPasses() {
        let rules = rules()
        #expect(rules.violations(plan([dayA, dayB, dayC])).isEmpty)
    }

    @Test("G1: only candidates")
    func g1() {
        let rules = rules(TemplateRequest(workoutsPerWeek: 3, equipment: [.dumbbell, .bodyweight]))
        #expect(rules.g1(plan([["dumbbell-bench-press"]])).isEmpty)
        #expect(rules.g1(plan([["barbell-back-squat"]])).map(\.exerciseID) == ["barbell-back-squat"])
        #expect(rules.g1(plan([["made-up"]])).count == 1)
        // No bench: bench lifts aren't candidates.
        let noBench = self.rules(TemplateRequest(setups: [.pullUpBar]))
        #expect(noBench.g1(plan([["dumbbell-bench-press"]])).count == 1)
    }

    @Test("G2: no repeat in a day, nor on back-to-back days unless it's a main lift")
    func g2() {
        let rules = rules()
        #expect(rules.g2(plan([dayA, dayB, dayA])).isEmpty)
        #expect(rules.g2(plan([dayA + ["seated-leg-curl"]])).count == 1)
        #expect(rules.g2(plan([dayA, dayA])).count == dayA.count)
        let strength = self.rules(TemplateRequest(type: .strength))
        #expect(strength.g2(plan([["barbell-back-squat"], ["barbell-back-squat"]])).isEmpty)
        #expect(strength.g2(plan([["dumbbell-lateral-raise"], ["dumbbell-lateral-raise"]])).count == 1)
    }

    @Test("G3: the time estimate fits the session")
    func g3() {
        let rules = rules(TemplateRequest(workoutsPerWeek: 3, sessionMinutes: 45))
        // 630 + 450 + 450 + 315 + 315 s plus 300 s of warmups is 41 minutes.
        #expect(rules.seconds(plan([dayA]).days[0]) == 2460)
        #expect(rules.g3(plan([dayA])).isEmpty)
        #expect(rules.g3(plan([dayA + ["cable-curl", "cable-triceps-pushdown"]])).count == 1)
        // A superset's two share one rest, so they take less time than apart.
        let apart = plan([["cable-curl", "cable-triceps-pushdown"]]).days[0]
        let together = plan([["cable-curl", "cable-triceps-pushdown"]],
                            supersets: [[.init(first: "cable-curl", second: "cable-triceps-pushdown")]]).days[0]
        #expect(rules.seconds(together) < rules.seconds(apart))
    }

    @Test("G4: one day per workout, 3 to 8 exercises, at most 2 High fatigue")
    func g4() {
        let rules = rules()
        let week = { (p: TemplatePlan) in rules.g4(p, rules.resolve(p)) }
        #expect(week(plan([dayA, dayB, dayC])).isEmpty)
        #expect(week(plan([dayA, dayB])).count == 1)
        #expect(week(plan([dayA, dayB, ["leg-extension", "cable-curl"]])).count == 1)
        let crowded = ["leg-extension", "cable-curl", "cable-crunch", "seated-leg-curl", "cable-chest-fly",
                       "dumbbell-lateral-raise", "cable-triceps-pushdown", "standing-calf-raise", "cable-woodchop"]
        #expect(week(plan([dayA, dayB, crowded])).count == 1)
        #expect(week(plan([dayA, dayB, ["barbell-back-squat", "barbell-deadlift", "leg-press"]])).count == 1)
    }

    @Test("G5: each big muscle twice a week with 3+ days, once with 2")
    func g5() {
        let rules = rules()
        #expect(rules.g5(rules.resolve(plan([dayA, dayB, dayC]))).isEmpty)
        let noLegs = [["dumbbell-bench-press", "seated-cable-row", "dumbbell-lateral-raise"]]
        let missing = Set(rules.g5(rules.resolve(plan(noLegs + noLegs + noLegs))).compactMap(\.muscle))
        #expect(missing == [.quads, .hamstrings, .glutes])
        let twoDays = self.rules(TemplateRequest(workoutsPerWeek: 2))
        #expect(twoDays.g5(twoDays.resolve(plan([dayA, dayB]))).isEmpty)
        // With no candidate for a muscle, it can't be asked for.
        let machines = self.rules(TemplateRequest(workoutsPerWeek: 2, equipment: [.machine], setups: []))
        let machineWeek = machines.resolve(plan([["leg-press", "machine-chest-press", "seated-leg-curl"], ["hack-squat", "leg-extension", "lying-leg-curl"]]))
        #expect(!machines.g5(machineWeek).contains { $0.muscle == .back })
    }

    @Test("G6: focus muscles get more than the rest, and aren't last while other work shares their tier")
    func g6() {
        let rules = rules(TemplateRequest(workoutsPerWeek: 3, focus: [.shoulders]))
        let p = plan([dayA, dayB, dayC])
        #expect(rules.g6(p, rules.resolve(p)).isEmpty)
        let calves = self.rules(TemplateRequest(workoutsPerWeek: 3, focus: [.calves]))
        #expect(calves.g6(p, calves.resolve(p)).contains { $0.muscle == .calves })
        let lastFocus = plan([["dumbbell-bench-press", "seated-leg-curl", "dumbbell-lateral-raise"]])
        #expect(rules.g6(lastFocus, rules.resolve(lastFocus)).contains { $0.day == 0 })
    }

    @Test("G7: at most 6 direct exercises per muscle a week")
    func g7() {
        let rules = rules()
        let chest = ["barbell-bench-press", "dumbbell-bench-press", "incline-dumbbell-bench-press", "cable-chest-fly"]
        #expect(rules.g7(rules.resolve(plan([chest, ["leg-press"], chest.prefix(2).map { $0 }]))).isEmpty)
        #expect(rules.g7(rules.resolve(plan([chest, ["leg-press"], chest]))).map(\.muscle) == [.chest])
    }

    @Test("G8: at least as much pulling as pushing")
    func g8() {
        let rules = rules()
        #expect(rules.g8(rules.resolve(plan([dayA, dayB, dayC]))).isEmpty)
        let pushy = [["dumbbell-bench-press", "barbell-overhead-press", "cable-chest-fly", "seated-cable-row"]]
        #expect(rules.g8(rules.resolve(plan(pushy))).count == 1)
        // Nothing to pull with: machines only.
        let machines = self.rules(TemplateRequest(equipment: [.machine], setups: []))
        #expect(machines.g8(machines.resolve(plan([["machine-chest-press"]]))).isEmpty)
    }

    @Test("G9: heavy, then compound, then isolation, focus first; supersets only of accessories")
    func g9() {
        let request = TemplateRequest(workoutsPerWeek: 3, supersets: true)
        let rules = rules(request)
        #expect(rules.g9(plan([dayA])).isEmpty)
        #expect(rules.g9(plan([dayA.reversed()])).count == 1)
        let good = plan([dayA], supersets: [[.init(first: "dumbbell-lateral-raise", second: "seated-leg-curl")]])
        #expect(rules.g9(good).isEmpty)
        let compound = plan([dayA], supersets: [[.init(first: "dumbbell-bench-press", second: "seated-cable-row")]])
        #expect(rules.g9(compound).count == 1)
        let apart = plan([dayA], supersets: [[.init(first: "dumbbell-lateral-raise", second: "seated-cable-row")]])
        #expect(rules.g9(apart).count == 1)
        let sameMuscle = plan([["dumbbell-curl", "cable-curl"]], supersets: [[.init(first: "dumbbell-curl", second: "cable-curl")]])
        #expect(rules.g9(sameMuscle).count == 1)
        let unasked = self.rules(TemplateRequest(workoutsPerWeek: 3))
        #expect(unasked.g9(good).count == 1)
        // Focus muscles come first within their tier.
        let focus = self.rules(TemplateRequest(workoutsPerWeek: 3, focus: [.hamstrings]))
        #expect(focus.g9(plan([dayA])).count == 1)
    }

    @Test("G10: Strength days open with a loaded compound, and the big three come every week")
    func g10() {
        let rules = rules(TemplateRequest(type: .strength, workoutsPerWeek: 3))
        let good = [["barbell-back-squat", "barbell-bench-press", "barbell-row"],
                    ["barbell-deadlift", "barbell-overhead-press", "pull-up"],
                    ["barbell-back-squat", "barbell-bench-press", "dumbbell-lateral-raise"]]
        #expect(rules.g10(rules.resolve(plan(good))).isEmpty)
        var noDeadlift = good
        noDeadlift[1][0] = "barbell-romanian-deadlift"
        #expect(rules.g10(rules.resolve(plan(noDeadlift))).map(\.exerciseID) == ["barbell-deadlift"])
        var curlFirst = good
        curlFirst[2] = ["dumbbell-curl"] + good[2]
        #expect(rules.g10(rules.resolve(plan(curlFirst))).map(\.day) == [2])
        // Without a bench the big three aren't asked for.
        let noBench = self.rules(TemplateRequest(type: .strength, setups: [.pullUpBar]))
        #expect(noBench.g10(noBench.resolve(plan([["barbell-back-squat"]]))).isEmpty)
        #expect(self.rules().g10(self.rules().resolve(plan([["dumbbell-curl"]]))).isEmpty)
    }

    @Test("G11: PowerJack days open with a main lift, each main lift twice a week with 4+ days")
    func g11() {
        let rules = rules(TemplateRequest(type: .powerJack, workoutsPerWeek: 4))
        let upper = ["barbell-bench-press", "barbell-overhead-press", "barbell-row"]
        let lower = ["barbell-back-squat", "barbell-deadlift", "seated-leg-curl"]
        #expect(rules.g11(rules.resolve(plan([upper, lower, upper, lower]))).isEmpty)
        let once = rules.g11(rules.resolve(plan([upper, lower, upper, ["barbell-back-squat", "leg-extension", "seated-leg-curl"]])))
        #expect(once.map(\.pattern) == [.hinge])
        let curlFirst = rules.g11(rules.resolve(plan([["dumbbell-curl"] + upper, lower, upper, lower])))
        #expect(curlFirst.map(\.day) == [0])
        // Three days only ask for the openers.
        let three = self.rules(TemplateRequest(type: .powerJack, workoutsPerWeek: 3))
        #expect(three.g11(three.resolve(plan([upper, lower, upper]))).isEmpty)
    }

    @Test("G12: Hypertrophy adds nothing to G1-G9")
    func g12() {
        let rules = rules()
        let week = rules.resolve(plan([["dumbbell-curl"]]))
        #expect(rules.g10(week).isEmpty && rules.g11(week).isEmpty)
    }

    @Test("Candidates leave out what the lifter can't do and keep 6 per muscle, focus ranked up")
    func candidates() {
        let request = TemplateRequest(focus: [.biceps], equipment: [.dumbbell, .cable], setups: [], lean: .machines)
        let candidates = BuilderCandidates(Self.fixture, for: request)
        #expect(candidates.ranked.allSatisfy { [.dumbbell, .cable].contains($0.equipment) && $0.setups.isEmpty })
        #expect(Dictionary(grouping: candidates.ranked, by: \.primary).values.allSatisfy { $0.count <= 6 })
        #expect(candidates.ranked.first?.primary == .biceps)
        #expect(candidates.ranked.first?.equipment == .cable)
        #expect(!candidates.contains("incline-dumbbell-curl"))
    }

    @Test("A named piece the lifter doesn't have leaves its lifts out, while the rest of its kind stays")
    func missingNamedEquipment() {
        let trapBar = BuilderExercise(id: "trap", name: "Trap Bar Deadlift", equipment: .barbell, equipmentName: "Trap Bar",
                                      primary: .quads, secondaries: [.glutes, .hamstrings], fatigue: .high, pattern: .hipHinge)
        let squat = BuilderExercise(id: "squat", name: "Barbell Back Squat", equipment: .barbell, primary: .quads,
                                    secondaries: [.glutes, .abs], fatigue: .high, pattern: .squat)
        let request = TemplateRequest(equipment: [.barbell], missingEquipmentNames: ["Trap Bar"])
        #expect(BuilderCandidates([trapBar, squat], for: request).ranked.map(\.id) == ["squat"])
        #expect(BuilderCandidates([trapBar, squat], for: TemplateRequest(equipment: [.barbell])).ranked.count == 2)
    }

    @Test("The snapshot reads catalog exercises the way the engines do")
    func snapshotMatchesEngines() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        try ExerciseCatalog.seed(in: container.mainContext)
        for exercise in try container.mainContext.fetch(FetchDescriptor<Exercise>()) where exercise.catalogID != nil {
            let snapshot = BuilderExercise(exercise)
            let entry = try #require(ExerciseCatalog.entries.first { $0.id == exercise.catalogID })
            #expect(snapshot == BuilderExercise(entry), "\(entry.id)")
            #expect(snapshot.isStrengthMainLift == StrengthLifts.isCompound(exercise), "\(entry.id)")
            #expect((snapshot.powerJackMainPattern != nil) == PowerJackPlanner.exercise(exercise).isMainLiftEligible, "\(entry.id)")
        }
    }

    @Test("A plan becomes an unsaved draft with its days, order and supersets")
    func draft() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        try ExerciseCatalog.seed(in: container.mainContext)
        let exercises = try container.mainContext.fetch(FetchDescriptor<Exercise>())
        let request = TemplateRequest(workoutsPerWeek: 3, focus: [.chest], supersets: true)
        let builder = PlanBuilder(request: request, exercises: exercises.map { BuilderExercise($0) })
        guard case .plan(let plan) = builder.build() else { Issue.record("no plan"); return }
        let draft = plan.makeDraft(for: request, exercises: exercises)
        #expect(draft.workoutsPerWeek == 3)
        #expect(draft.templateMuscleFocus == [.chest])
        #expect(draft.templateName == plan.name)
        #expect(draft.templateWorkoutDrafts.map { $0.templateExerciseDrafts.map { StrengthLifts.key(for: $0.exercise) } }
                == plan.days.map(\.exerciseIDs))
        #expect(draft.templateWorkoutDrafts.map(\.supersets.count) == plan.days.map(\.supersets.count))
        #expect(!draft.isDraft)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TemplateProgram>()) == 0)
    }
}
