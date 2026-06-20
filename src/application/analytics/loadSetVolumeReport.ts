import {
  buildSetVolumeReport,
  getPeriodBounds,
  parsePeriodStart,
  type SetVisualizationRange,
} from "../../domain/analytics/TrainingAnalytics";
import type { TrainingAnalyticsRepository } from "../../domain/analytics/TrainingAnalyticsRepository";

export async function loadSetVolumeReport(
  input: {
    range: SetVisualizationRange;
    periodStart: string | null;
    now?: Date;
  },
  repository: TrainingAnalyticsRepository,
) {
  const periodStart = parsePeriodStart(input.periodStart, input.range, input.now);
  const bounds = getPeriodBounds(input.range, periodStart);
  const events = await repository.loadCompletedSetEvents({
    fromInclusive: bounds.previousStart.toISOString(),
    toExclusive: bounds.currentEnd.toISOString(),
  });

  return buildSetVolumeReport({
    events,
    periodStart,
    range: input.range,
  });
}
