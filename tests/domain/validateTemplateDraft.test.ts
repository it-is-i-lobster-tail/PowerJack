import { describe, expect, it } from "vitest";
import { validateTemplateDraft } from "../../src/domain/templates/rules/validateTemplateDraft";

describe("validateTemplateDraft", () => {
  it("requires a name", () => {
    expect(validateTemplateDraft({ name: " ", focusMuscleIds: [1], workoutsPerWeek: 2, days: [] })).toMatchObject({
      ok: false,
      message: "Name the template.",
    });
  });

  it("requires a name no longer than 64 characters", () => {
    expect(
      validateTemplateDraft({
        name: "A".repeat(65),
        focusMuscleIds: [1],
        workoutsPerWeek: 2,
        days: [],
      }),
    ).toMatchObject({
      ok: false,
      message: "Template name must be 64 characters or fewer.",
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
