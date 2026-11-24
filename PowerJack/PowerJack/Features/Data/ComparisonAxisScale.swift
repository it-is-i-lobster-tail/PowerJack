import Foundation

/// The two axes occupy the same plot height, but each has its own bounds and tick spacing.
struct ComparisonAxisScale {
    let lowerBound: Double
    let upperBound: Double
    private let intervals: Int

    init(values: [Double], wholeNumbers: Bool) {
        let low = values.min() ?? 0
        let high = values.max() ?? low
        let minimumPadding = wholeNumbers ? 1 : max(0.5, high * 0.01)
        let padding = max(minimumPadding, (high - low) * 0.08)
        let bottom = max(0, low - padding)
        let top = high + padding

        // Aim for about five intervals with readable labels, including integer-only rep counts.
        let preferred = max(wholeNumbers ? 1 : 0.1, (top - bottom) / 5)
        let magnitude = pow(10, floor(log10(preferred)))
        let candidates = [1.0, 2, 4, 5, 10].map { $0 * magnitude }
        let step = candidates.min { abs($0 - preferred) < abs($1 - preferred) } ?? magnitude
        let first = Int(floor(bottom / step))
        let last = max(first + 1, Int(ceil(top / step)))
        lowerBound = Double(first) * step
        upperBound = Double(last) * step
        intervals = last - first
    }

    var tickPositions: [Double] { (0...intervals).map { Double($0) / Double(intervals) } }

    func position(of value: Double) -> Double {
        (value - lowerBound) / (upperBound - lowerBound)
    }

    func value(at position: Double) -> Double {
        lowerBound + position * (upperBound - lowerBound)
    }
}
