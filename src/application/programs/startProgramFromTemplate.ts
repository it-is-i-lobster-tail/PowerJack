import type { AppState } from "../../domain/app-state/AppState";
import type { AppStateRepository } from "../../domain/app-state/AppStateRepository";
import type { EntityId } from "../../domain/ids";
import type { ProgramRepository } from "../../domain/programs/ProgramRepository";
import { validateProgramLengthWeeks } from "../../domain/programs/rules/validateProgramLengthWeeks";
import type { TemplateRepository } from "../../domain/templates/TemplateRepository";

export async function startProgramFromTemplate(
  input: { templateId: EntityId; programLengthWeeks: number; replaceActiveProgram?: boolean },
  repositories: {
    appState: AppStateRepository;
    templates: TemplateRepository;
    programs: ProgramRepository;
  },
): Promise<AppState> {
  const lengthValidation = validateProgramLengthWeeks(input.programLengthWeeks);

  if (!lengthValidation.ok) {
    throw new Error(lengthValidation.message ?? "Choose a valid program length.");
  }

  const appState = await repositories.appState.load();

  if (appState?.activeProgramId && !input.replaceActiveProgram) {
    throw new Error("An active program already exists.");
  }

  const template = await repositories.templates.loadAggregate(input.templateId);

  if (!template) {
    throw new Error("Selected template could not be loaded.");
  }

  return repositories.programs.startFromTemplate({
    template,
    programLengthWeeks: input.programLengthWeeks,
    replaceActiveProgram: input.replaceActiveProgram,
  });
}
