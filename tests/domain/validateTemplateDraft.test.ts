import { describe, expect, it } from "vitest";
import {
  TEMPLATE_DAY_EXERCISE_MAX,
  TEMPLATE_NAME_MAX_LENGTH,
} from "../../src/domain/templates/rules/templateDraftLimits";
import { validateTemplateDraft } from "../../src/domain/templates/rules/validateTemplateDraft";

describe("validateTemplateDraft", () => {
  it("requires a name", () => {
    expect(validateTemplateDraft({ name: " ", focusMuscleIds: [1], workoutsPerWeek: 2, days: [] })).toMatchObject({
      ok: false,
      message: "Name the template.",
    });
  });

  it("requires a name no longer than 24 characters", () => {
    expect(
      validateTemplateDraft({
        name: "A".repeat(TEMPLATE_NAME_MAX_LENGTH + 1),
        focusMuscleIds: [1],
        workoutsPerWeek: 2,
        days: [],
      }),
    ).toMatchObject({
      ok: false,
      message: "Template name must be 24 characters or fewer.",
    });
  });

  it("requires at least one focus muscle", () => {
    expect(
      validateTemplateDraft({
        name: "Back In Action",
        focusMuscleIds: [],
        workoutsPerWeek: 2,
        days: [],
      }),
    ).toMatchObject({
      ok: false,
      message: "Choose at least one muscle group.",
    });
  });

  it("allows no more than four focus muscles", () => {
    expect(
      validateTemplateDraft({
        name: "Back In Action",
        focusMuscleIds: [1, 2, 3, 4, 5],
        workoutsPerWeek: 2,
        days: [],
      }),
    ).toMatchObject({
      ok: false,
      message: "Choose no more than 4 muscle groups.",
    });
  });

  it("requires days per week", () => {
    expect(
      validateTemplateDraft({ name: "Back In Action", focusMuscleIds: [1], workoutsPerWeek: null, days: [] }),
    ).toMatchObject({
      ok: false,
      message: "Choose days per week.",
    });
  });

  it("requires every day to have at least one exercise", () => {
    expect(
      validateTemplateDraft({
        name: "Back In Action",
        focusMuscleIds: [1],
        workoutsPerWeek: 2,
        days: [
          { order: 1, exerciseIds: [1] },
          { order: 2, exerciseIds: [] },
        ],
      }),
    ).toMatchObject({
      ok: false,
      message: "Add at least one exercise to Day 2.",
    });
  });

  it("allows a day with exactly 20 exercises", () => {
    const result = validateTemplateDraft({
      name: "Back In Action",
      focusMuscleIds: [1],
      workoutsPerWeek: 1,
      days: [{ order: 1, exerciseIds: Array.from({ length: TEMPLATE_DAY_EXERCISE_MAX }, (_, index) => index + 1) }],
    });

    expect(result.ok).toBe(true);
  });

  it("rejects a day with more than 20 exercises", () => {
    expect(
      validateTemplateDraft({
        name: "Back In Action",
        focusMuscleIds: [1],
        workoutsPerWeek: 1,
        days: [
          {
            order: 1,
            exerciseIds: Array.from({ length: TEMPLATE_DAY_EXERCISE_MAX + 1 }, (_, index) => index + 1),
          },
        ],
      }),
    ).toMatchObject({
      ok: false,
      message: "Workouts are limited to 20 exercises.",
    });
  });

  it("applies the exercise limit to the overloaded day only", () => {
    expect(
      validateTemplateDraft({
        name: "Back In Action",
        focusMuscleIds: [1],
        workoutsPerWeek: 2,
        days: [
          {
            order: 1,
            exerciseIds: Array.from({ length: TEMPLATE_DAY_EXERCISE_MAX + 1 }, (_, index) => index + 1),
          },
          { order: 2, exerciseIds: [99] },
        ],
      }),
    ).toMatchObject({
      ok: false,
      message: "Workouts are limited to 20 exercises.",
    });
  });

  it("returns a completed draft for valid templates", () => {
    expect(
      validateTemplateDraft({
        name: " Back In Action ",
        focusMuscleIds: [1, 2],
        workoutsPerWeek: 2,
        days: [
          { order: 1, exerciseIds: [1] },
          { order: 2, exerciseIds: [2, 3] },
        ],
      }),
    ).toEqual({
      ok: true,
      completedDraft: {
        name: "Back In Action",
        focusMuscleIds: [1, 2],
        workoutsPerWeek: 2,
        days: [
          { order: 1, exerciseIds: [1] },
          { order: 2, exerciseIds: [2, 3] },
        ],
      },
    });
  });
});
