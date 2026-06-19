import type { CompletedTemplateDraft, TemplateDraft } from "../Template";

export interface TemplateDraftValidationResult {
  ok: boolean;
  message?: string;
  completedDraft?: CompletedTemplateDraft;
}

export function validateTemplateDraft(draft: TemplateDraft): TemplateDraftValidationResult {
  const name = draft.name.trim();
  const nameLength = draft.name.length;

  if (!name) {
    return { ok: false, message: "Name the template." };
  }

  if (nameLength > 64) {
    return { ok: false, message: "Template name must be 64 characters or fewer." };
  }

  if (draft.focusMuscleIds.length === 0) {
    return { ok: false, message: "Choose at least one muscle group." };
  }

  if (draft.focusMuscleIds.length > 4) {
    return { ok: false, message: "Choose no more than 4 muscle groups." };
  }

  if (!draft.workoutsPerWeek) {
    return { ok: false, message: "Choose days per week." };
  }

  if (draft.days.length !== draft.workoutsPerWeek) {
    return { ok: false, message: "Template days do not match days per week." };
  }

  const emptyDay = draft.days.find((day) => day.exerciseIds.length === 0);

  if (emptyDay) {
    return { ok: false, message: `Add at least one exercise to Day ${emptyDay.order}.` };
  }

  return {
    ok: true,
    completedDraft: {
      name,
      focusMuscleIds: [...draft.focusMuscleIds],
      workoutsPerWeek: draft.workoutsPerWeek,
      days: draft.days.map((day) => ({
        order: day.order,
        exerciseIds: [...day.exerciseIds],
      })),
    },
  };
}
