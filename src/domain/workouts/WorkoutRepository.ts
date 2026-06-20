import type { EntityId } from "../ids";
import type { ActiveWorkoutView } from "./Workout";

export type ManualCheckinDecision = "skip" | "continue" | "reset";

export interface WorkoutRepository {
  loadActive(): Promise<ActiveWorkoutView | null>;
  loadWorkoutView(workoutId: EntityId): Promise<ActiveWorkoutView | null>;
  updateSetActuals(input: {
    setId: EntityId;
    actualReps: number | null;
    actualWeight: number | null;
  }): Promise<ActiveWorkoutView>;
  submitLiftFeedback(input: {
    liftId: EntityId;
    levelOfPain: number;
    levelOfEffort: number;
  }): Promise<ActiveWorkoutView>;
  resolveManualCheckIn(input: {
    liftId: EntityId;
    decision: ManualCheckinDecision;
  }): Promise<ActiveWorkoutView>;
  finishWorkout(workoutId: EntityId): Promise<ActiveWorkoutView | null>;
}
