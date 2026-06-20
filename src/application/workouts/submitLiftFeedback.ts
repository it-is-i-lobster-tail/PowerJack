import type { EntityId } from "../../domain/ids";
import type { WorkoutRepository } from "../../domain/workouts/WorkoutRepository";

export async function submitLiftFeedback(
  input: {
    liftId: EntityId;
    levelOfPain: number;
    levelOfEffort: number;
  },
  repository: WorkoutRepository,
) {
  if (!isPainScaleValue(input.levelOfPain)) {
    throw new Error("Choose a pain value from 1 to 5.");
  }

  if (!isEffortScaleValue(input.levelOfEffort)) {
    throw new Error("Choose an effort value from 1 to 5.");
  }

  return repository.submitLiftFeedback(input);
}

function isPainScaleValue(value: number): boolean {
  return Number.isInteger(value) && value >= 1 && value <= 5;
}

function isEffortScaleValue(value: number): boolean {
  return Number.isInteger(value) && value >= 1 && value <= 5;
}
