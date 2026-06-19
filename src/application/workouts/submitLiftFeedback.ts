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
  if (!isFeedbackScaleValue(input.levelOfPain) || !isFeedbackScaleValue(input.levelOfEffort)) {
    throw new Error("Choose a feedback value from 1 to 5.");
  }

  return repository.submitLiftFeedback(input);
}

function isFeedbackScaleValue(value: number): boolean {
  return Number.isInteger(value) && value >= 1 && value <= 5;
}
