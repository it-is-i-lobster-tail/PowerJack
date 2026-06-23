import type { EntityId } from "../ids";
import type { ActiveWorkoutView } from "./Workout";

export type ManualCheckinDecision = "skip" | "continue" | "reset";

export interface WorkoutRepository {
  listWorkoutIdsForProgram(programId: EntityId): Promise<EntityId[]>;
  loadActive(): Promise<ActiveWorkoutView | null>;
  loadWorkoutView(workoutId: EntityId): Promise<ActiveWorkoutView | null>;
  updateSetActuals(input: {
    setId: EntityId;
    actualReps: number | null;
    actualWeight: number | null;
  }): Promise<ActiveWorkoutView>;
  addSetToLift(input: {
    liftId: EntityId;
  }): Promise<ActiveWorkoutView>;
  removeLastSetFromLift(input: {
    liftId: EntityId;
  }): Promise<ActiveWorkoutView>;
  changeLiftExercise(input: {
    liftId: EntityId;
    exerciseId: EntityId;
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
