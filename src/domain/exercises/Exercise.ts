import type { EntityId } from "../ids";

export interface Muscle {
  id: EntityId;
  name: string;
  createdAt: string;
  updatedAt: string;
}

export interface Equipment {
  id: EntityId;
  name: string;
  weightOverloadable: boolean;
  repOverloadable: boolean;
  timeOverloadable: boolean;
}

export interface Exercise {
  id: EntityId;
  name: string;
  primaryMuscleId: EntityId;
  secondaryMuscleIds: EntityId[];
  equipmentId: EntityId;
  minRepsHypertrophy: number;
  maxRepsHypertrophy: number;
  createdAt: string;
  updatedAt: string;
}

export interface ExerciseSummary {
  id: EntityId;
  name: string;
  primaryMuscleName: string;
  secondaryMuscleNames: string[];
  equipmentName: string;
  minRepsHypertrophy: number;
  maxRepsHypertrophy: number;
}
