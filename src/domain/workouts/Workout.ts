import type { EntityId } from "../ids";
import type { Program } from "../programs/Program";
import type { PowerJackStatus } from "../status";

export const manualCheckinStatuses = ["none", "pending", "resolved"] as const;

export type ManualCheckinStatus = (typeof manualCheckinStatuses)[number];

export interface Workout {
  id: EntityId;
  order: number;
  workoutDay: number;
  programWeek: number;
  hidden: boolean;
  locked: boolean;
  status: PowerJackStatus;
  programId: EntityId;
  createdAt: string;
  updatedAt: string;
}

export interface Lift {
  id: EntityId;
  exerciseId: EntityId;
  workoutId: EntityId;
  locked: boolean;
  hidden: boolean;
  order: number;
  status: PowerJackStatus;
  planned: boolean;
  manualCheckinStatus: ManualCheckinStatus;
  manualCheckinSourceLiftId: EntityId | null;
  createdAt: string;
  updatedAt: string;
}

export interface WorkoutSet {
  id: EntityId;
  plannedReps: number | null;
  actualReps: number | null;
  plannedWeight: number | null;
  actualWeight: number | null;
  order: number;
  liftId: EntityId;
  locked: boolean;
  hidden: boolean;
  status: PowerJackStatus;
  planned: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface Feedback {
  id: EntityId;
  levelOfPain: number;
  levelOfEffort: number;
  liftId: EntityId;
  createdAt: string;
  updatedAt: string;
}

export interface ActiveWorkoutSetView {
  id: EntityId;
  order: number;
  plannedReps: number | null;
  actualReps: number | null;
  plannedWeight: number | null;
  actualWeight: number | null;
  status: PowerJackStatus;
  locked: boolean;
}

export interface ActiveWorkoutLiftView {
  id: EntityId;
  exerciseId: EntityId;
  exerciseName: string;
  repsOnly: boolean;
  timeBased: boolean;
  order: number;
  status: PowerJackStatus;
  locked: boolean;
  feedbackSubmitted: boolean;
  manualCheckinStatus: ManualCheckinStatus;
  manualCheckinSourceLiftId: EntityId | null;
  manualCheckinSourcePain: number | null;
  sets: ActiveWorkoutSetView[];
}

export interface ActiveWorkoutWeekItem {
  id: EntityId;
  workoutDay: number;
  status: PowerJackStatus;
  locked: boolean;
}

export interface ActiveWorkoutView {
  program: Program;
  workout: Workout;
  weekWorkouts: ActiveWorkoutWeekItem[];
  previousWorkoutId: EntityId | null;
  nextWorkoutId: EntityId | null;
  completedSets: number;
  totalSets: number;
  canFinish: boolean;
  isReadOnly: boolean;
  lifts: ActiveWorkoutLiftView[];
}
