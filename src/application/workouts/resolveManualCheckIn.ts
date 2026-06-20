import type { EntityId } from "../../domain/ids";
import type {
  ManualCheckinDecision,
  WorkoutRepository,
} from "../../domain/workouts/WorkoutRepository";

export async function resolveManualCheckIn(
  input: {
    liftId: EntityId;
    decision: ManualCheckinDecision;
  },
  repository: WorkoutRepository,
) {
  return repository.resolveManualCheckIn(input);
}
