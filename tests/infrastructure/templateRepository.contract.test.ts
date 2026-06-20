import { describe, expect, it } from "vitest";
import { startProgramFromTemplate } from "../../src/application/programs/startProgramFromTemplate";
import { saveTemplate, updateTemplate } from "../../src/application/templates/saveTemplate";
import { createInMemoryAppServices } from "../../src/infrastructure/database/repositories/InMemoryRepositories";

describe("TemplateRepository contract", () => {
  it("starts empty by default", async () => {
    const services = createInMemoryAppServices();

    await expect(services.templates.list()).resolves.toEqual([]);
  });

  it("saves and lists a complete template summary", async () => {
    const services = createInMemoryAppServices();

    const savedTemplate = await saveTemplate(
      {
        name: "Back In Action",
        focusMuscleIds: [1, 2],
        workoutsPerWeek: 2,
        days: [
          { order: 1, exerciseIds: [1] },
          { order: 2, exerciseIds: [2, 3] },
        ],
      },
      services.templates,
    );

    expect(savedTemplate).toMatchObject({
      id: 1,
      name: "Back In Action",
      workoutsPerWeek: 2,
      exerciseCount: 3,
      usedByActiveProgram: false,
      focusMuscles: [
        { id: 1, name: "Back" },
        { id: 2, name: "Biceps" },
      ],
    });
    await expect(services.templates.list()).resolves.toEqual([savedTemplate]);
    await expect(services.templates.findById(savedTemplate.id)).resolves.toMatchObject({
      id: savedTemplate.id,
      focusMuscleIds: [1, 2],
    });
  });

  it("updates a template aggregate while preserving the template id", async () => {
    const services = createInMemoryAppServices();
    const savedTemplate = await saveTemplate(
      {
        name: "Back In Action",
        focusMuscleIds: [1],
        workoutsPerWeek: 2,
        days: [
          { order: 1, exerciseIds: [1] },
          { order: 2, exerciseIds: [2] },
        ],
      },
      services.templates,
    );

    const updatedTemplate = await updateTemplate(
      savedTemplate.id,
      {
        name: "Updated Action",
        focusMuscleIds: [3, 4],
        workoutsPerWeek: 3,
        days: [
          { order: 1, exerciseIds: [3, 2] },
          { order: 2, exerciseIds: [4] },
          { order: 3, exerciseIds: [5] },
        ],
      },
      services.templates,
    );

    expect(updatedTemplate).toMatchObject({
      id: savedTemplate.id,
      name: "Updated Action",
      workoutsPerWeek: 3,
      exerciseCount: 4,
    });
    await expect(services.templates.loadAggregate(savedTemplate.id)).resolves.toEqual({
      id: savedTemplate.id,
      name: "Updated Action",
      workoutsPerWeek: 3,
      focusMuscleIds: [3, 4],
      days: [
        { id: savedTemplate.id * 100 + 1, order: 1, exerciseIds: [3, 2] },
        { id: savedTemplate.id * 100 + 2, order: 2, exerciseIds: [4] },
        { id: savedTemplate.id * 100 + 3, order: 3, exerciseIds: [5] },
      ],
    });
  });

  it("soft-deletes templates from lists and detects active program usage", async () => {
    const services = createInMemoryAppServices();
    const activeTemplate = await saveTemplate(
      {
        name: "Active Template",
        focusMuscleIds: [1],
        workoutsPerWeek: 1,
        days: [{ order: 1, exerciseIds: [1] }],
      },
      services.templates,
    );
    const unusedTemplate = await saveTemplate(
      {
        name: "Unused Template",
        focusMuscleIds: [2],
        workoutsPerWeek: 1,
        days: [{ order: 1, exerciseIds: [2] }],
      },
      services.templates,
    );

    await startProgramFromTemplate(
      { templateId: activeTemplate.id, programLengthWeeks: 4 },
      {
        appState: services.appState,
        templates: services.templates,
        programs: services.programs,
      },
    );

    await expect(services.templates.isUsedByActiveProgram(activeTemplate.id)).resolves.toBe(true);
    await expect(services.templates.isUsedByActiveProgram(unusedTemplate.id)).resolves.toBe(false);

    const listedTemplates = await services.templates.list();
    expect(listedTemplates.find((template) => template.id === activeTemplate.id)).toMatchObject({
      usedByActiveProgram: true,
    });
    expect(listedTemplates.find((template) => template.id === unusedTemplate.id)).toMatchObject({
      usedByActiveProgram: false,
    });

    await services.templates.softDelete(unusedTemplate.id);

    await expect(services.templates.list()).resolves.toEqual([expect.objectContaining({ id: activeTemplate.id })]);
    await expect(services.templates.findById(unusedTemplate.id)).resolves.toBeNull();
  });
});
