import type { CompletedSetEvent } from "./TrainingAnalytics";
import type { EntityId } from "../ids";

export interface TrainingAnalyticsRepository {
  loadCompletedSetEvents(input: {
    fromInclusive: string;
    toExclusive: string;
  }): Promise<CompletedSetEvent[]>;
  loadCompletedSetEventsForProgram(programId: EntityId): Promise<CompletedSetEvent[]>;
}
