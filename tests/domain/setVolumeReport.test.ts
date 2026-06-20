import { describe, expect, it } from "vitest";
import {
  buildSetVolumeReport,
  parsePeriodStart,
  serializePeriodStart,
  type CompletedSetEvent,
} from "../../src/domain/analytics/TrainingAnalytics";

describe("set volume report", () => {
  it("groups completed sets by muscle and compares against the previous matching range", () => {
    const events: CompletedSetEvent[] = [
      completedSet(1, 1, "Back", "2026-04-10T12:00:00.000Z"),
      completedSet(2, 1, "Back", "2026-07-10T12:00:00.000Z"),
      completedSet(3, 1, "Back", "2026-09-08T12:00:00.000Z"),
      completedSet(4, 4, "Chest", "2026-08-02T12:00:00.000Z"),
      completedSet(5, 9, "Quads", "2025-09-08T12:00:00.000Z"),
    ];

    const report = buildSetVolumeReport({
      events,
      periodStart: new Date(2026, 6, 1),
      range: "quarter",
    });

    expect(report.periodLabel).toBe("Q3 2026");
    expect(report.previousPeriodLabel).toBe("Q2 2026");
    expect(report.totalCompletedSets).toBe(3);
    expect(report.previousTotalCompletedSets).toBe(1);
    expect(report.delta).toBe(2);
    expect(report.metricUnitLabel).toBe("sets/week");
    expect(report.metricValue).toBeCloseTo(3 / (92 / 7), 5);
    expect(report.previousMetricValue).toBeCloseTo(1 / 13, 5);
    expect(report.metricDelta).toBeCloseTo(3 / (92 / 7) - 1 / 13, 5);
    expect(report.buckets.map((bucket) => bucket.shortLabel)).toEqual(["Jul", "Aug", "Sep"]);
    expect(report.rows).toEqual([
      expect.objectContaining({
        muscleName: "Back",
        completedSets: 2,
        previousCompletedSets: 1,
        delta: 1,
        metricValue: 2 / (92 / 7),
        previousMetricValue: 1 / 13,
        metricDelta: 2 / (92 / 7) - 1 / 13,
        bucketCounts: [1, 0, 1],
        bucketValues: [1 / (31 / 7), 0, 1 / (30 / 7)],
      }),
      expect.objectContaining({
        muscleName: "Chest",
        completedSets: 1,
        previousCompletedSets: 0,
        delta: 1,
        metricValue: 1 / (92 / 7),
        previousMetricValue: 0,
        metricDelta: 1 / (92 / 7),
        bucketCounts: [0, 1, 0],
        bucketValues: [0, 1 / (31 / 7), 0],
      }),
    ]);
  });

  it("keeps week reports as completed-set totals", () => {
    const report = buildSetVolumeReport({
      events: [
        completedSet(1, 1, "Back", "2026-06-15T12:00:00.000Z"),
        completedSet(2, 1, "Back", "2026-06-16T12:00:00.000Z"),
        completedSet(3, 1, "Back", "2026-06-08T12:00:00.000Z"),
      ],
      periodStart: new Date(2026, 5, 15),
      range: "week",
    });

    expect(report.periodLabel).toBe("Jun 15-21, 2026");
    expect(report.metricUnitLabel).toBe("sets");
    expect(report.metricValue).toBe(2);
    expect(report.previousMetricValue).toBe(1);
    expect(report.metricDelta).toBe(1);
    expect(report.rows[0]).toEqual(
      expect.objectContaining({
        bucketCounts: [1, 1, 0, 0, 0, 0, 0],
        bucketValues: [1, 1, 0, 0, 0, 0, 0],
        metricValue: 2,
        previousMetricValue: 1,
      }),
    );
  });

  it("normalizes arbitrary dates to the requested period start", () => {
    expect(serializePeriodStart(parsePeriodStart("2026-08-19", "quarter"))).toBe("2026-07-01");
    expect(serializePeriodStart(parsePeriodStart("2026-08-19", "year"))).toBe("2026-01-01");
  });
});

function completedSet(
  setId: number,
  muscleId: number,
  muscleName: string,
  completedAt: string,
): CompletedSetEvent {
  return {
    setId,
    muscleId,
    muscleName,
    completedAt,
  };
}
