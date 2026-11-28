//
//  TemplateSplit.swift
//  PowerJack
//
//  The standard split for each number of days, as the built-in templates use them, and the muscles
//  each day trains in the order they're filled.
//

import Foundation

enum TemplateSplit {
    /// One exercise wanted for a muscle. Patterns narrow it, like rear delts on a pull day.
    struct Slot: Hashable, Sendable {
        let muscle: Muscle
        var patterns: Set<MovementPattern>? = nil

        func matches(_ exercise: BuilderExercise) -> Bool {
            exercise.primary == muscle && (patterns.map { exercise.pattern.map($0.contains) ?? false } ?? true)
        }
    }

    private static let row = Slot(muscle: .back, patterns: [.horizontalPull, .verticalPull])

    enum Day: Sendable {
        case fullBody, upper, lower, push, pull, legs

        private var row: Slot { TemplateSplit.row }

        var slots: [Slot] {
            switch self {
            case .fullBody:
                [.init(muscle: .quads), .init(muscle: .chest), row, .init(muscle: .hamstrings),
                 .init(muscle: .shoulders), .init(muscle: .glutes), row, .init(muscle: .triceps),
                 .init(muscle: .biceps), .init(muscle: .calves), .init(muscle: .abs)]
            case .upper:
                [.init(muscle: .chest), row, .init(muscle: .shoulders), row,
                 .init(muscle: .chest), .init(muscle: .triceps), .init(muscle: .biceps), .init(muscle: .shoulders)]
            case .lower:
                [.init(muscle: .quads), .init(muscle: .hamstrings), .init(muscle: .glutes), .init(muscle: .quads),
                 .init(muscle: .calves), .init(muscle: .abs), .init(muscle: .hamstrings), .init(muscle: .obliques)]
            case .push:
                [.init(muscle: .chest), .init(muscle: .shoulders), .init(muscle: .chest), .init(muscle: .triceps),
                 .init(muscle: .shoulders), .init(muscle: .triceps), .init(muscle: .abs)]
            case .pull:
                [row, row, .init(muscle: .shoulders, patterns: [.reverseFly, .facePull]),
                 .init(muscle: .biceps), .init(muscle: .back), .init(muscle: .biceps), .init(muscle: .forearms)]
            case .legs:
                [.init(muscle: .quads), .init(muscle: .hamstrings), .init(muscle: .glutes), .init(muscle: .quads),
                 .init(muscle: .calves), .init(muscle: .abs), .init(muscle: .hamstrings)]
            }
        }
    }

    static func days(for count: Int) -> [Day] {
        switch count {
        case ...3: Array(repeating: .fullBody, count: count)
        case 4: [.upper, .lower, .upper, .lower]
        case 5: [.push, .pull, .legs, .upper, .lower]
        default: [.push, .pull, .legs, .push, .pull, .legs]
        }
    }

    /// A plain name for the split, such as "Upper Lower 4x".
    static func name(for count: Int) -> String {
        let split = switch count {
        case ...3: "Full Body"
        case 4: "Upper Lower"
        case 5: "PPL Upper Lower"
        default: "Push Pull Legs"
        }
        return "\(split) \(count)x"
    }
}
