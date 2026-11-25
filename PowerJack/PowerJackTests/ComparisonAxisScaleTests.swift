import Testing
@testable import PowerJack

struct ComparisonAxisScaleTests {
    @Test func squatAxesFitIndependently() {
        let weight = ComparisonAxisScale(values: [175, 170, 185, 180], wholeNumbers: false)
        let reps = ComparisonAxisScale(values: [13, 8, 7], wholeNumbers: true)
        #expect(weight.lowerBound == 168 && weight.upperBound == 188)
        #expect(reps.lowerBound == 6 && reps.upperBound == 14)
        #expect(reps.tickPositions.map(reps.value(at:)) == [6, 8, 10, 12, 14])
        #expect(abs(weight.value(at: weight.position(of: 175)) - 175) < 0.0001)
    }

    @Test func constantAndZeroLoadsHaveRoom() {
        let constant = ComparisonAxisScale(values: [82.5, 82.5], wholeNumbers: false)
        #expect(constant.lowerBound > 0 && constant.lowerBound < 82.5)
        #expect(constant.upperBound > 82.5)
        let zero = ComparisonAxisScale(values: [0], wholeNumbers: false)
        #expect(zero.lowerBound == 0 && zero.upperBound > 0)
        #expect(zero.position(of: 0) == 0)
    }
}
