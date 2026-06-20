import type { CompletedSetEvent } from "./TrainingAnalytics";

export interface TrainingAnalyticsRepository {
  loadCompletedSetEvents(input: {
    fromInclusive: string;
    toExclusive: string;
  }): Promise<CompletedSetEvent[]>;
}
