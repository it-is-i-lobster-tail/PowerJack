//
//  BuilderCandidates.swift
//  PowerJack
//
//  The only exercises Build for Me can put in a template (G1): the ones the lifter has the
//  equipment and setup for, best fit first, at most 6 per main muscle.
//

import Foundation

struct BuilderCandidates: Sendable {
    static let perMuscle = 6

    /// Best fit first.
    let ranked: [BuilderExercise]
    let byID: [String: BuilderExercise]

    init(_ exercises: [BuilderExercise], for request: TemplateRequest) {
        var seen = Set<String>()
        let usable = exercises.filter { request.allows($0) && seen.insert($0.id).inserted }
        // Ties keep the order they came in, so the result never changes from run to run.
        let sorted = usable.enumerated().sorted { first, second in
            let firstScore = Self.score(first.element, for: request)
            let secondScore = Self.score(second.element, for: request)
            return firstScore != secondScore ? firstScore > secondScore : first.offset < second.offset
        }
        var perMuscle: [Muscle: Int] = [:]
        ranked = sorted.map(\.element).filter { exercise in
            perMuscle[exercise.primary, default: 0] += 1
            return perMuscle[exercise.primary, default: 0] <= Self.perMuscle
        }
        byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })
    }

    func contains(_ id: String) -> Bool { byID[id] != nil }

    /// Fit to the lean, the focus muscles, how familiar the lift is and the program type.
    static func score(_ exercise: BuilderExercise, for request: TemplateRequest) -> Double {
        var score = 0.0
        switch request.lean {
        case .freeWeights where freeWeights.contains(exercise.equipment): score += 2
        case .machines where !freeWeights.contains(exercise.equipment): score += 2
        default: break
        }
        if request.focus.contains(exercise.primary) { score += 1 }
        score += Double(min(exercise.uses, 20)) / 10
        switch request.type {
        case .strength:
            if TemplateRules.bigThree.contains(exercise.id) { score += 5 }
            if exercise.isStrengthMainLift { score += 1 }
        case .powerJack:
            if powerJackBigFour.contains(exercise.id) { score += 5 }
            if exercise.powerJackMainPattern != nil { score += 1 }
        case .hypertrophy:
            break
        }
        return score
    }

    private static let freeWeights: Set<Equipment> = [.barbell, .dumbbell, .kettlebell, .bodyweight, .loadableBodyweight]
    private static let powerJackBigFour: Set<String> = TemplateRules.bigThree.union(["barbell-overhead-press"])
}
