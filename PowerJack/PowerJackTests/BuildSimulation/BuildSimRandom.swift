//
//  BuildSimRandom.swift
//  PowerJackTests
//
//  The Build simulation's seeded random numbers. Only integer math and plain arithmetic, so a seed
//  replays exactly on any machine and Swift version.
//

import Foundation

struct BuildSimRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// SplitMix64.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    mutating func pick<Element>(_ elements: [Element]) -> Element {
        elements[int(0...(elements.count - 1))]
    }

    /// Picks an element, each as likely as its weight.
    mutating func pick<Element>(weighted elements: [(Element, Double)]) -> Element {
        var roll = unit() * elements.reduce(0) { $0 + $1.1 }
        for (element, weight) in elements {
            if roll < weight { return element }
            roll -= weight
        }
        return elements[elements.count - 1].0
    }

    /// Roughly normal, with mean 0 and spread 1: four uniforms summed and rescaled.
    mutating func bell() -> Double {
        (unit() + unit() + unit() + unit() - 2) * Double(3).squareRoot()
    }

    /// A seed from text that is the same in every run, unlike `hashValue` (FNV-1a).
    static func seed(_ text: String) -> UInt64 {
        text.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0100_0000_01B3 }
    }
}
