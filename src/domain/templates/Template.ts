import type { EntityId } from "../ids";

export interface TemplateFocusMuscle {
  id: EntityId;
  name: string;
}

export interface TemplateSummary {
  id: EntityId;
  name: string;
  workoutsPerWeek: number;
  exerciseCount: number;
  focusMuscles: TemplateFocusMuscle[];
  createdAt: string;
  updatedAt: string;
}

export interface Template {
  id: EntityId;
  name: string;
  workoutsPerWeek: number;
  focusMuscleIds: EntityId[];
  createdAt: string;
  updatedAt: string;
}

export interface WorkoutTemplate {
  id: EntityId;
  templateId: EntityId;
  order: number;
  createdAt: string;
  updatedAt: string;
}

export interface TemplateDayDraft {
  order: number;
  exerciseIds: EntityId[];
}

export interface TemplateDraft {
  name: string;
  focusMuscleIds: EntityId[];
  workoutsPerWeek: number | null;
  days: TemplateDayDraft[];
}

export interface CompletedTemplateDraft {
  name: string;
  focusMuscleIds: EntityId[];
  workoutsPerWeek: number;
  days: Array<{
    order: number;
    exerciseIds: EntityId[];
  }>;
}

export interface LiftTemplate {
  id: EntityId;
  workoutTemplateId: EntityId;
  exerciseId: EntityId;
  order: number;
  createdAt: string;
  updatedAt: string;
}

export interface TemplateAggregateDay {
  id: EntityId;
  order: number;
  exerciseIds: EntityId[];
}

export interface TemplateAggregate {
  id: EntityId;
  name: string;
  workoutsPerWeek: number;
  focusMuscleIds: EntityId[];
  days: TemplateAggregateDay[];
}
