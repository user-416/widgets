import Testing
@testable import WidgetsShared

struct ThresholdsTests {
    @Test func zeroAndNegativeAreBucketZero() {
        #expect(Thresholds.bucket(for: 0, thresholds: [1, 5, 10, 20]) == 0)
        #expect(Thresholds.bucket(for: -1, thresholds: [1, 5, 10, 20]) == 0)
    }

    @Test func smallPositiveCountIsBucketOne() {
        #expect(Thresholds.bucket(for: 0.5, thresholds: [1, 5, 10, 20]) == 1)
        #expect(Thresholds.bucket(for: 4.99, thresholds: [1, 5, 10, 20]) == 1)
    }

    @Test func boundariesPushIntoNextBucket() {
        let t: [Double] = [1, 5, 10, 20]
        #expect(Thresholds.bucket(for: 5, thresholds: t) == 2)
        #expect(Thresholds.bucket(for: 10, thresholds: t) == 3)
        #expect(Thresholds.bucket(for: 20, thresholds: t) == 4)
    }

    @Test func largeValuesCapAtBucketFour() {
        #expect(Thresholds.bucket(for: 1_000_000, thresholds: [1, 5, 10, 20]) == 4)
    }

    @Test func stepsDefaults() {
        let t = MetricKind.healthkitSteps.defaultThresholds
        #expect(Thresholds.bucket(for: 4_999, thresholds: t) == 1)
        #expect(Thresholds.bucket(for: 5_000, thresholds: t) == 2)
        #expect(Thresholds.bucket(for: 9_999, thresholds: t) == 2)
        #expect(Thresholds.bucket(for: 10_000, thresholds: t) == 3)
        #expect(Thresholds.bucket(for: 14_999, thresholds: t) == 3)
        #expect(Thresholds.bucket(for: 15_000, thresholds: t) == 4)
    }
}
